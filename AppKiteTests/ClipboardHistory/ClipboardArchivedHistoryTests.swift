import AppKit
import Testing

@testable import AppKite

struct ClipboardArchivedHistoryTests {
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
        let pasted = await PasteClipboardEntry(
            pasteboard: client, pasteTarget: AppKitPasteTarget())(
                payload: replay, target: nil, replacing: client.changeCount
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
