import Foundation
import Testing
import os

@testable import AppKite

struct ClipboardStorageRecoveryTests {
    @Test func `A second open leaves the active store's staging untouched`() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "history.store")
        let staged = root.appending(path: "archives/staging/pending")
        do {
            let store = try await SwiftDataClipboardHistoryStore.open(at: url)
            try await store.record(text: "Carte valide", sourceBundleIdentifier: nil, at: .now)
            try Data("Copie en cours".utf8).write(to: staged)

            await #expect(throws: ClipboardHistoryStoreError.storageInUse) {
                _ = try await SwiftDataClipboardHistoryStore.open(at: url)
            }
            #expect(try Data(contentsOf: staged) == Data("Copie en cours".utf8))
            #expect(try await store.entries().map(\.text) == ["Carte valide"])
        }
        let reopened = try await SwiftDataClipboardHistoryStore.open(at: url)
        #expect(try await reopened.entries().map(\.text) == ["Carte valide"])
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test func `Deleting a Finder card removes its archived file even with a deny-delete ACL`()
        async throws
    {
        let files = FileManager.default
        let root = try makeDirectory()
        let source = root.appending(path: "Sources/Données.csv")
        let archives = root.appending(path: "archives")
        defer {
            try? chmod(["-RN", root.path])
            try? files.removeItem(at: root)
        }
        try files.createDirectory(
            at: source.deletingLastPathComponent(), withIntermediateDirectories: false)
        let data = Data("a,b\n1,2".utf8)
        try data.write(to: source)
        try chmod(["+a", "\(NSUserName()) deny delete", source.path])

        let url = root.appending(path: "history.store")
        do {
            let store = try await SwiftDataClipboardHistoryStore.open(at: url)
            try await store.record(text: "Carte valide", sourceBundleIdentifier: nil, at: .now)
            let payload = ClipboardPayload(items: [
                .init(representations: [], fileURL: source.deletingLastPathComponent())
            ])
            try await store.record(payload: payload, sourceBundleIdentifier: nil, at: .now)
            let card = try #require(try await store.entries().first { $0.kind == .files })
            let archivedPayload = try await store.payload(for: card.id)
            let archivedFolder = try #require(archivedPayload.items.first?.fileURL)
            let archived = archivedFolder.appending(path: source.lastPathComponent)
            #expect(try Data(contentsOf: archived) == data)
            #expect(throws: CocoaError.self) { try files.removeItem(at: archived) }

            try await store.deleteEntry(id: card.id, confirmingProtection: true)
            #expect(!files.fileExists(atPath: archives.appending(path: card.id.uuidString).path))
            #expect(throws: CocoaError.self) { try files.removeItem(at: source) }
            #expect(try Data(contentsOf: source) == data)
        }
        let reopened = try await SwiftDataClipboardHistoryStore.open(at: url)
        #expect(try await reopened.entries().map(\.text) == ["Carte valide"])
    }

    @Test func `An undeletable orphan leaves valid history available and cleanup can retry later`()
        async throws
    {
        let files = FileManager.default
        let root = try makeDirectory()
        let archives = root.appending(path: "archives")
        let orphans = [archives, archives.appending(path: "staging")].map {
            $0.appending(path: UUID().uuidString)
        }
        defer {
            try? chmod(["-RN", root.path])
            try? files.removeItem(at: root)
        }

        let url = root.appending(path: "history.store")
        do {
            let store = try await SwiftDataClipboardHistoryStore.open(at: url)
            try await store.record(text: "Carte valide", sourceBundleIdentifier: nil, at: .now)
        }
        for orphan in orphans {
            try files.createDirectory(at: orphan, withIntermediateDirectories: false)
        }
        for parent in orphans.map({ $0.deletingLastPathComponent() }) {
            try chmod(["+a", "\(NSUserName()) deny delete_child", parent.path])
        }
        for orphan in orphans {
            #expect(throws: CocoaError.self) { try files.removeItem(at: orphan) }
        }
        do {
            let store = try await SwiftDataClipboardHistoryStore.open(at: url)
            #expect(try await store.entries().map(\.text) == ["Carte valide"])
            for orphan in orphans {
                #expect(files.fileExists(atPath: orphan.path))
            }
        }

        try chmod(["-RN", archives.path])
        let reopened = try await SwiftDataClipboardHistoryStore.open(at: url)
        #expect(try await reopened.entries().map(\.text) == ["Carte valide"])
        for orphan in orphans {
            #expect(!files.fileExists(atPath: orphan.path))
        }
    }

    @Test func `Clearing cards still removes other archives after one removal fails`() async throws
    {
        let files = FileManager.default
        let root = try makeDirectory()
        defer { try? files.removeItem(at: root) }
        let url = root.appending(path: "history.store")
        let archives = root.appending(path: "archives")
        let blockedArchive = OSAllocatedUnfairLock(initialState: Optional<UUID>.none)
        let orphan: URL

        do {
            let store = try await SwiftDataClipboardHistoryStore.open(at: url) { archive, id in
                let isFirst = blockedArchive.withLock { first in
                    guard first == nil else { return false }
                    first = id
                    return true
                }
                if isFirst { throw CocoaError(.fileWriteNoPermission) }
                try archive.remove(id: id)
            }
            try await store.record(text: "Première carte", sourceBundleIdentifier: nil, at: .now)
            try await store.record(text: "Deuxième carte", sourceBundleIdentifier: nil, at: .now)
            let ids = try await store.entries().map(\.id)
            try #require(ids.count == 2)

            await #expect(throws: ClipboardHistoryStoreError.archiveCleanupDeferred) {
                try await store.clearUnprotectedEntries()
            }
            let blockedID = try #require(blockedArchive.withLock { $0 })
            orphan = archives.appending(path: blockedID.uuidString)
            #expect(try await store.entries().isEmpty)
            #expect(try await store.search(ClipboardHistoryQuery()).entries.isEmpty)
            #expect(files.fileExists(atPath: orphan.path))
            for id in ids where id != blockedID {
                #expect(!files.fileExists(atPath: archives.appending(path: id.uuidString).path))
            }
        }

        let reopened = try await SwiftDataClipboardHistoryStore.open(at: url)
        #expect(try await reopened.entries().isEmpty)
        #expect(!files.fileExists(atPath: orphan.path))
    }

    private func makeDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func chmod(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/chmod")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
    }
}
