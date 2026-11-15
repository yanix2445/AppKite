import Foundation
import Synchronization

nonisolated final class ClipboardSearchIndex: Sendable {
    private struct Row: Sendable {
        let card: ClipboardEntry
        let text: String
    }

    private let rows = Mutex<[UUID: Row]>([:])

    func update(_ card: ClipboardEntry, text: String) {
        let row = Row(card: card, text: Self.fold(text))
        rows.withLock { $0[card.id] = row }
    }

    func remove(_ ids: [UUID]) {
        rows.withLock { rows in
            for id in ids { rows.removeValue(forKey: id) }
        }
    }

    func search(_ query: ClipboardHistoryQuery) throws -> ClipboardHistoryResults {
        let snapshot = rows.withLock { $0 }
        let terms = Self.fold(query.text).split(whereSeparator: \.isWhitespace)
        var matches: [ClipboardEntry] = []
        var sources: Set<String> = []
        var canClearHistory = false

        for row in snapshot.values {
            try Task.checkCancellation()
            let card = row.card
            let source = card.sourceBundleIdentifier ?? ClipboardHistoryQuery.unknownSource
            sources.insert(source)
            canClearHistory = canClearHistory || !card.isProtected
            guard query.collection.map(card.collectionIDs.contains) ?? true,
                query.kind.map({ $0 == card.kind }) ?? true,
                query.source.map({ $0 == source }) ?? true,
                terms.allSatisfy({ row.text.contains($0) })
            else { continue }
            matches.append(card)
        }

        matches.sort(by: Self.isMoreRecent)
        let mostRecent = matches.first
        let pinnedLimit = mostRecent?.isPinned == false ? max(0, query.limit - 1) : query.limit
        let ordered = matches.lazy.filter(\.isPinned).prefix(pinnedLimit)
        var page = Array(ordered)
        page.append(
            contentsOf: matches.lazy.filter { !$0.isPinned }.prefix(query.limit - page.count))
        return ClipboardHistoryResults(
            entries: page, sourceIdentifiers: sources.sorted(), mostRecentID: mostRecent?.id,
            hasMoreEntries: matches.count > page.count, canClearHistory: canClearHistory
        )
    }

    private static func isMoreRecent(_ left: ClipboardEntry, _ right: ClipboardEntry) -> Bool {
        if left.lastUsedAt != right.lastUsedAt { return left.lastUsedAt > right.lastUsedAt }
        return left.id < right.id
    }

    private static func fold(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
