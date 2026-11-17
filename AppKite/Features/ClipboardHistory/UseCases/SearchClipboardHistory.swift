import Foundation

nonisolated struct ClipboardHistoryQuery: Sendable, Equatable {
    static let unknownSource = ""
    static let pageSize = 48

    var text = ""
    var kind: ClipboardPayload.Kind?
    var source: String?
    var collection: UUID?
    var limit = pageSize

    var isFiltering: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || kind != nil || source != nil
    }
}

nonisolated struct ClipboardHistoryResults: Sendable {
    let entries: [ClipboardEntry]
    let matchingUnpinnedIDs: [UUID]
    let sourceIdentifiers: [String]
    let mostRecentID: UUID?
    let hasMoreEntries: Bool
    let canClearHistory: Bool
}

nonisolated struct SearchClipboardHistory: Sendable {
    let store: any ClipboardHistoryStore

    func callAsFunction(_ query: ClipboardHistoryQuery) async throws -> ClipboardHistoryResults {
        try await store.search(query)
    }
}
