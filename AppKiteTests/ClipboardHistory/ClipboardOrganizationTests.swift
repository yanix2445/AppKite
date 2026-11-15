import CryptoKit
import Foundation
import SwiftData
import Testing

@testable import AppKite

struct ClipboardOrganizationTests {
    @MainActor
    @Test func `A phase one history opens with the original card intact`() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.store")
        let text = "Café\nPhase 1"
        let origin = "com.apple.TextEdit"
        let copiedAt = Date(timeIntervalSince1970: 100)
        let lastUsedAt = copiedAt + 1
        let id = try createPhaseOneHistory(
            at: url, text: text, origin: origin, copiedAt: copiedAt, lastUsedAt: lastUsedAt)

        let store = try await SwiftDataClipboardHistoryStore.open(at: url)
        let entries = try await store.entries()
        let collections = try await store.collections()
        let expected = ClipboardEntry(
            id: id, text: text, sourceBundleIdentifier: origin, lastUsedAt: lastUsedAt)
        #expect(entries == [expected])
        #expect(collections.isEmpty)

        try await store.record(text: text, sourceBundleIdentifier: nil, at: lastUsedAt + 1)
        let afterRecopy = try await store.entries()
        #expect(afterRecopy.map(\.id) == [id])
    }

    @Test func `Recopy and reopen preserve pins and multiple memberships`() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.store")
        let start = Date(timeIntervalSince1970: 100)
        let id: UUID
        let personal: ClipboardCollection
        let work: ClipboardCollection
        do {
            let store = try await SwiftDataClipboardHistoryStore.open(at: url)
            let manage = ManageClipboardHistory(store: store)
            try await store.record(text: "Card", sourceBundleIdentifier: nil, at: start)
            let initialEntries = try await store.entries()
            id = try #require(initialEntries.first?.id)

            try await manage(.setPinned(true, entryID: id))
            try await manage(.createCollection("Work"))
            try await manage(.createCollection("Personal"))
            let collections = try await store.collections()
            personal = try #require(collections.first { $0.name == "Personal" })
            work = try #require(collections.first { $0.name == "Work" })
            try await manage(.setMembership(true, entryID: id, collectionID: personal.id))
            try await manage(.setMembership(true, entryID: id, collectionID: work.id))
            try await manage(.setMembership(true, entryID: id, collectionID: work.id))

            try await store.record(text: "Newer card", sourceBundleIdentifier: nil, at: start + 1)
            try await store.record(
                text: "Card", sourceBundleIdentifier: "com.apple.Safari", at: start + 2)
        }

        let reopened = try await SwiftDataClipboardHistoryStore.open(at: url)
        let reopenedEntries = try await reopened.entries()
        let recopied = try #require(reopenedEntries.first)
        #expect(reopenedEntries.map(\.text) == ["Card", "Newer card"])
        #expect(recopied.id == id)
        #expect(recopied.isPinned)
        #expect(recopied.collectionIDs == [personal.id, work.id])
        #expect(recopied.sourceBundleIdentifier == "com.apple.Safari")
        #expect(recopied.lastUsedAt == start + 2)

        let manageReopened = ManageClipboardHistory(store: reopened)
        try await manageReopened(.deleteCollection(work.id))
        let afterCollectionDeletion = try await reopened.entries()
        let remainingCollections = try await reopened.collections()
        #expect(afterCollectionDeletion.map(\.id) == reopenedEntries.map(\.id))
        #expect(afterCollectionDeletion.first?.isPinned == true)
        #expect(afterCollectionDeletion.first?.collectionIDs == [personal.id])
        #expect(remainingCollections == [personal])
        try await manageReopened(.setMembership(false, entryID: id, collectionID: personal.id))
        let afterUnclassifying = try await reopened.entries()
        #expect(afterUnclassifying.first?.collectionIDs.isEmpty == true)
    }

    @Test func `Clearing and deletion protect pinned or collected cards`() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await SwiftDataClipboardHistoryStore.open(
            at: directory.appending(path: "history.store"))
        let manage = ManageClipboardHistory(store: store)
        let start = Date(timeIntervalSince1970: 100)
        try await store.record(text: "Pinned", sourceBundleIdentifier: nil, at: start)
        try await store.record(text: "Collected", sourceBundleIdentifier: nil, at: start + 1)
        try await store.record(text: "Ordinary", sourceBundleIdentifier: nil, at: start + 2)
        let entries = try await store.entries()
        let pinned = try #require(entries.first { $0.text == "Pinned" })
        let collected = try #require(entries.first { $0.text == "Collected" })

        try await manage(.setPinned(true, entryID: pinned.id))
        try await manage(.createCollection("Work"))
        let collections = try await store.collections()
        let work = try #require(collections.first)
        try await manage(.setMembership(true, entryID: collected.id, collectionID: work.id))
        try await manage(.clearUnprotectedEntries)

        let afterClear = try await store.entries()
        let allProtected = afterClear.allSatisfy(\.isProtected)
        #expect(afterClear.map(\.id) == [collected.id, pinned.id])
        #expect(allProtected)
        for id in [pinned.id, collected.id] {
            await #expect(throws: ClipboardHistoryStoreError.protectedEntry) {
                try await manage(.deleteEntry(id, confirmingProtection: false))
            }
        }
        let afterRefusedDeletion = try await store.entries()
        #expect(afterRefusedDeletion == afterClear)

        try await manage(.deleteEntry(collected.id, confirmingProtection: true))
        try await manage(.setPinned(false, entryID: pinned.id))
        try await manage(.deleteEntry(pinned.id, confirmingProtection: false))
        let remaining = try await store.entries()
        let remainingCollections = try await store.collections()
        #expect(remaining.isEmpty)
        #expect(remainingCollections == [work])
    }

    private func makeTestDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    @MainActor
    private func createPhaseOneHistory(
        at url: URL, text: String, origin: String, copiedAt: Date, lastUsedAt: Date
    ) throws -> UUID {
        let schema = Schema([PhaseOne.StoredClipboardEntry.self])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let entry = PhaseOne.StoredClipboardEntry(
            text: text, origin: origin, copiedAt: copiedAt, lastUsedAt: lastUsedAt)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        return entry.id
    }

    // The entity name and persisted fields match the phase-one store.
    fileprivate enum PhaseOne {
        @Model
        nonisolated final class StoredClipboardEntry {
            #Index<StoredClipboardEntry>([\.fingerprint], [\.lastUsedAt])

            @Attribute(.unique) var id: UUID
            var text: String
            var fingerprint: String
            var sourceBundleIdentifier: String?
            var lastCopiedAt: Date
            var lastUsedAt: Date

            init(text: String, origin: String, copiedAt: Date, lastUsedAt: Date) {
                self.id = UUID()
                self.text = text
                self.fingerprint = Data(SHA256.hash(data: Data(text.utf8))).base64EncodedString()
                self.sourceBundleIdentifier = origin
                self.lastCopiedAt = copiedAt
                self.lastUsedAt = lastUsedAt
            }
        }
    }
}
