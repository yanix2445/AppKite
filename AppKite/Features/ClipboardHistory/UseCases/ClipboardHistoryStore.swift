import Foundation

nonisolated protocol ClipboardHistoryStore: Sendable {
    func entries() async throws -> [ClipboardEntry]
    func search(_ query: ClipboardHistoryQuery) async throws -> ClipboardHistoryResults
    func thumbnails(for ids: [UUID]) async throws -> [UUID: Data]
    func indexNextPendingEntry() async throws -> Bool
    func record(text: String, sourceBundleIdentifier: String?, at date: Date) async throws
    func record(payload: ClipboardPayload, sourceBundleIdentifier: String?, at date: Date)
        async throws
    func record(_ copy: ClipboardCopy, at date: Date) async throws
    func payload(for id: UUID) async throws -> ClipboardPayload
    func prepareReplay(for id: UUID, replayID: UUID) async throws -> ClipboardPayload
    func removeReplays(exceptKeeping replayID: UUID?) async throws
    func markUsed(id: UUID, at date: Date) async throws
    func collections() async throws -> [ClipboardCollection]
    func setPinned(_ isPinned: Bool, for entryID: UUID) async throws
    func createCollection(named name: String) async throws
    func setMembership(_ isMember: Bool, for entryID: UUID, in collectionID: UUID) async throws
    func deleteCollection(id: UUID) async throws
    func deleteEntry(id: UUID, confirmingProtection: Bool) async throws
    func clearUnprotectedEntries() async throws
}

nonisolated enum ClipboardHistoryStoreError: Error {
    case storageInUse
    case invalidCollectionName
    case protectedEntry
    case missingEntry
    case insufficientArchiveCapacity
}
