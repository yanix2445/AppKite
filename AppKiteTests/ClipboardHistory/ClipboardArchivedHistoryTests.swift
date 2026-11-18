import AppKit
import Testing

@testable import AppKite

struct ClipboardArchivedHistoryTests {
    @Test func groupedReplayRejectsOversizedArchivesBeforeCopyingFiles() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: root) }
        let original = root.appending(path: "Note.txt")
        try Data("Fichier".utf8).write(to: original)

        let store = try await SwiftDataClipboardHistoryStore.open(
            at: root.appending(path: "history.store"))
        let date = Date.now
        try await store.record(
            payload: .init(items: [.init(representations: [], fileURL: original)]),
            sourceBundleIdentifier: nil, at: date)
        let fileID = try #require(try await store.entries().first).id
        let existing = try await store.prepareReplay(for: fileID, replayID: UUID())
        let existingFile = try #require(existing.items.first?.fileURL)

        let archiveRoot = root.appending(path: "archives")
        let archive = try ClipboardArchive(root: archiveRoot)
        var ids = [fileID]
        for (index, content) in ["Un", "Deux"].enumerated() {
            try await store.record(
                payload: .plainText(content), sourceBundleIdentifier: nil,
                at: date.addingTimeInterval(Double(index + 1)))
            let id = try #require(try await store.entries().first).id
            ids.append(id)
            let source = try archive.previewSource(for: id)
            let representation = try #require(source.items.first?.representations.first?.url)
            let file = try FileHandle(forWritingTo: representation)
            defer { try? file.close() }
            try file.truncate(atOffset: UInt64(ClipboardArchive.groupedReplayByteLimit / 2 + 1))
        }

        let replayID = UUID()
        await #expect(throws: ClipboardHistoryStoreError.groupedReplayTooLarge) {
            _ = try await store.prepareReplay(for: ids, replayID: replayID)
        }
        let replays = archiveRoot.appending(path: "replays")
        #expect(!files.fileExists(atPath: replays.appending(path: replayID.uuidString).path))
        #expect(try String(contentsOf: existingFile, encoding: .utf8) == "Fichier")
        #expect(try await store.entries().count == ids.count)
    }

    @MainActor
    @Test func groupedReplayKeepsSameNamedFilesAndJoinsTextInSelectionOrder() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: root) }

        let store = try await SwiftDataClipboardHistoryStore.open(
            at: root.appending(path: "history.store"))
        var fileIDs: [UUID] = []
        var textIDs: [UUID] = []
        for (index, value) in ["Premier", "Deuxième"].enumerated() {
            let file = root.appending(path: "\(index)/Note.txt")
            try files.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(value.utf8).write(to: file)
            let date = Date.now.addingTimeInterval(Double(index * 2))
            try await store.record(
                payload: .init(items: [.init(representations: [], fileURL: file)]),
                sourceBundleIdentifier: nil, at: date)
            fileIDs.append(try #require(try await store.entries().first).id)
            try await store.record(
                payload: .plainText(value), sourceBundleIdentifier: nil,
                at: date.addingTimeInterval(1))
            textIDs.append(try #require(try await store.entries().first).id)
            try files.removeItem(at: file)
        }

        let replayID = UUID()
        let replay = try await store.prepareReplay(for: fileIDs, replayID: replayID)
        let urls = replay.items.compactMap(\.fileURL)
        #expect(urls.map(\.lastPathComponent) == ["Note.txt", "Note.txt"])
        #expect(
            try urls.map { try String(contentsOf: $0, encoding: .utf8) } == ["Premier", "Deuxième"])
        try await store.removeReplays(exceptKeeping: replayID)
        #expect(urls.allSatisfy { files.fileExists(atPath: $0.path) })

        let groupedText = try await store.prepareReplay(for: textIDs, replayID: UUID())
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let client = PasteboardClient(pasteboard: board, readAccessBehavior: { .alwaysAllow })
        let outcome = await ClipboardHistoryComposition.makePaste(pasteboard: client)(
            payload: groupedText, replacing: client.changeCount)
        #expect(outcome == .copied)
        #expect(board.string(forType: .string) == "Premier\nDeuxième")

        try await store.setPinned(true, for: fileIDs[0])
        await #expect(throws: ClipboardHistoryStoreError.protectedEntry) {
            try await store.deleteEntries(ids: Set(fileIDs), confirmingProtection: false)
        }
        #expect(try await store.entries().count == 4)
        try await store.deleteEntries(ids: Set(fileIDs), confirmingProtection: true)
        #expect(Set(try await store.entries().map(\.id)) == Set(textIDs))
        #expect(urls.allSatisfy { files.fileExists(atPath: $0.path) })
        try await store.removeReplays(exceptKeeping: nil)
        #expect(urls.allSatisfy { !files.fileExists(atPath: $0.path) })
    }

    @Test func `An unchanged Finder selection updates its card without staging an archive`()
        async throws
    {
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: UUID().uuidString)
        let source = root.appending(path: "Projet/Données.csv")
        try files.createDirectory(
            at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let values = Data("nom,nombre\nA,5\n".utf8)
        try values.write(to: source)

        let store = try await SwiftDataClipboardHistoryStore.open(
            at: root.appending(path: "history.store"))
        let folder = source.deletingLastPathComponent()
        let payload = ClipboardPayload(items: [.init(representations: [], fileURL: folder)])
        let date = Date.now
        try await store.record(payload: payload, sourceBundleIdentifier: nil, at: date)
        let card = try #require(try await store.entries().first)
        try await store.setPinned(true, for: card.id)

        let staging = root.appending(path: "archives/staging")
        try files.removeItem(at: staging)
        try Data().write(to: staging)

        let updatedDate = date.addingTimeInterval(1)
        let newOrigin = "com.apple.finder"
        try await store.record(payload: payload, sourceBundleIdentifier: newOrigin, at: updatedDate)
        let entries = try await store.entries()
        #expect(entries.map(\.id) == [card.id])
        #expect(entries.first?.sourceBundleIdentifier == newOrigin)
        #expect(entries.first?.lastUsedAt == updatedDate)
        #expect(entries.first?.isPinned == true)
        let archived = try await store.payload(for: card.id)
        let archivedFolder = try #require(archived.items.first?.fileURL)
        #expect(try Data(contentsOf: archivedFolder.appending(path: "Données.csv")) == values)
    }

    @MainActor
    @Test
    func `Finder cards replay after original files are removed and delete with their archive`()
        async throws
    {
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: root) }
        let source = root.appending(path: "Sources")
        let folder = source.appending(path: "Projet")
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let document = folder.appending(path: "Données.csv")
        let values = Data("nom,nombre\nA,5\n".utf8)
        try values.write(to: document)

        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let client = PasteboardClient(pasteboard: board, readAccessBehavior: { .alwaysAllow })
        board.clearContents()
        try #require(board.writeObjects([folder as NSURL, document as NSURL]))
        let copy = try #require(client.pollPayload())
        #expect(
            copy.payload.items.map { $0.fileURL?.lastPathComponent } == ["Projet", "Données.csv"])

        let storeURL = root.appending(path: "history.store")
        let card: ClipboardEntry
        do {
            let store = try await SwiftDataClipboardHistoryStore.open(at: storeURL)
            try await store.record(payload: copy.payload, sourceBundleIdentifier: nil, at: .now)
            card = try #require(try await store.entries().first)
            try await store.setPinned(true, for: card.id)
            try await store.record(payload: copy.payload, sourceBundleIdentifier: nil, at: .now)
            let afterRecopy = try await store.entries()
            #expect(afterRecopy.map(\.id) == [card.id])
            #expect(afterRecopy.first?.isPinned == true)
            try files.removeItem(at: source)
        }

        let reopened = try await SwiftDataClipboardHistoryStore.open(at: storeURL)
        let replayID = UUID()
        let replay = try await reopened.prepareReplay(for: card.id, replayID: replayID)
        let archived = try await reopened.payload(for: card.id)
        let replayedFolder = try #require(replay.items.first?.fileURL)
        #expect(try Data(contentsOf: replayedFolder.appending(path: "Données.csv")) == values)
        #expect(replayedFolder != archived.items.first?.fileURL)
        let pasted = await ClipboardHistoryComposition.makePaste(pasteboard: client)(
            payload: replay, replacing: client.changeCount
        )
        #expect(pasted == .copied)
        #expect(client.pollPayload() == nil)
        let pastedFiles = try #require(board.readObjects(forClasses: [NSURL.self]) as? [URL])
        #expect(pastedFiles == replay.items.compactMap(\.fileURL))

        try await reopened.deleteEntry(id: card.id, confirmingProtection: true)
        #expect(try await reopened.entries().isEmpty)
        let archivedFolder = try #require(archived.items.first?.fileURL)
        #expect(!files.fileExists(atPath: archivedFolder.path))
        #expect(files.fileExists(atPath: replayedFolder.path))
        board.clearContents()
        try await reopened.removeReplays(exceptKeeping: nil)
        #expect(!files.fileExists(atPath: replayedFolder.path))
    }
}
