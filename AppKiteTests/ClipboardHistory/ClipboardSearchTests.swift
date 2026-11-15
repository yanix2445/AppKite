import Foundation
import Testing

@testable import AppKite

struct ClipboardSearchTests {
    @Test func `Filters combine and include only matching pins`() throws {
        let index = ClipboardSearchIndex()
        let source = "com.apple.Safari"
        let wanted = card(kind: .image, source: source, pinned: true)
        let wrongKind = card(kind: .pdf, source: source, pinned: true)
        let wrongSource = card(kind: .image, source: nil)
        index.update(wanted, text: "Échéance du budget")
        index.update(wrongKind, text: "Échéance du budget")
        index.update(wrongSource, text: "Échéance du budget")

        let filters = ClipboardHistoryQuery(kind: .image, source: source)
        #expect(try index.search(filters).entries.map(\.id) == [wanted.id])
        let query = ClipboardHistoryQuery(text: "budget ECHEANCE", kind: .image, source: source)
        #expect(try index.search(query).entries.map(\.id) == [wanted.id])
        let unknown = ClipboardHistoryQuery(source: ClipboardHistoryQuery.unknownSource)
        #expect(try index.search(unknown).entries.map(\.id) == [wrongSource.id])
    }

    @Test func `The first page includes the newest card even with many pins`() throws {
        let index = ClipboardSearchIndex()
        for position in 0..<100 {
            index.update(card(at: position, pinned: true), text: "Épinglé")
        }
        let newest = card(at: 101)
        index.update(newest, text: "Nouvelle copie")

        let result = try index.search(ClipboardHistoryQuery(limit: 5))
        #expect(result.entries.count == 5)
        let pinsFirst = result.entries.prefix(4).allSatisfy(\.isPinned)
        #expect(pinsFirst)
        #expect(result.mostRecentID == newest.id)
        #expect(result.entries.last?.id == newest.id)
        #expect(result.hasMoreEntries)
    }

    @Test func `Search survives reopen and reflects new origins, collections and deletion`()
        async throws
    {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appending(path: UUID().uuidString)
        try files.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: folder) }
        let storeURL = folder.appending(path: "history.store")
        let entry: ClipboardEntry
        let collection: ClipboardCollection
        do {
            let store = try await SwiftDataClipboardHistoryStore.open(at: storeURL)
            let text = String(repeating: "Introduction ", count: 400) + "Dernière échéance"
            let date = Date(timeIntervalSince1970: 10)
            try await store.record(text: text, sourceBundleIdentifier: "com.apple.Safari", at: date)
            let firstQuery = ClipboardHistoryQuery(
                text: "derniere echeance", source: "com.apple.Safari")
            let initial = try await store.search(firstQuery)
            entry = try #require(initial.entries.first)

            try await store.setPinned(true, for: entry.id)
            try await store.createCollection(named: "Travail")
            collection = try #require(try await store.collections().first)
            try await store.setMembership(true, for: entry.id, in: collection.id)
            try await store.record(
                text: text, sourceBundleIdentifier: "com.apple.TextEdit", at: date + 1)
            #expect(try await store.search(firstQuery).entries.isEmpty)
        }

        let reopened = try await SwiftDataClipboardHistoryStore.open(at: storeURL)
        let filtered = ClipboardHistoryQuery(
            text: "echeance", source: "com.apple.TextEdit", collection: collection.id)
        let results = try await reopened.search(filtered)
        #expect(results.entries.map(\.id) == [entry.id])
        #expect(results.entries.first?.isPinned == true)
        try await reopened.deleteCollection(id: collection.id)
        #expect(try await reopened.search(filtered).entries.isEmpty)
        try await reopened.deleteEntry(id: entry.id, confirmingProtection: true)
        #expect(try await reopened.search(ClipboardHistoryQuery(text: "echeance")).entries.isEmpty)
    }

    private func card(
        kind: ClipboardPayload.Kind = .text, source: String? = nil, at position: Int = 0,
        pinned: Bool = false
    ) -> ClipboardEntry {
        ClipboardEntry(
            id: UUID(), text: "Aperçu", sourceBundleIdentifier: source,
            lastUsedAt: Date(timeIntervalSince1970: Double(position)), isPinned: pinned, kind: kind
        )
    }
}
