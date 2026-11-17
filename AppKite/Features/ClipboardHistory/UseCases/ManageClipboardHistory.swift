import Foundation

nonisolated struct ManageClipboardHistory: Sendable {
    enum Action: Sendable {
        case setPinned(Bool, entryID: UUID)
        case createCollection(String)
        case setMembership(Bool, entryID: UUID, collectionID: UUID)
        case deleteCollection(UUID)
        case deleteEntry(UUID, confirmingProtection: Bool)
        case deleteEntries(Set<UUID>)
        case clearUnprotectedEntries
    }

    let store: any ClipboardHistoryStore

    func callAsFunction(_ action: Action) async throws {
        switch action {
        case .setPinned(let isPinned, let entryID):
            try await store.setPinned(isPinned, for: entryID)
        case .createCollection(let name):
            try await store.createCollection(named: name)
        case .setMembership(let isMember, let entryID, let collectionID):
            try await store.setMembership(isMember, for: entryID, in: collectionID)
        case .deleteCollection(let id):
            try await store.deleteCollection(id: id)
        case .deleteEntry(let id, let confirmingProtection):
            try await store.deleteEntries(ids: [id], confirmingProtection: confirmingProtection)
        case .deleteEntries(let ids):
            try await store.deleteEntries(ids: ids, confirmingProtection: true)
        case .clearUnprotectedEntries:
            try await store.clearUnprotectedEntries()
        }
    }
}
