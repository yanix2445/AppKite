import Foundation

nonisolated struct RecordClipboard: Sendable {
    let store: any ClipboardHistoryStore

    func callAsFunction(_ copy: ClipboardCopy, at date: Date = .now) async throws {
        try await store.record(copy, at: date)
    }
}
