import Foundation

nonisolated struct ClipboardEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let sourceBundleIdentifier: String?
    let probableSourceBundleIdentifier: String?
    let isRemote: Bool
    let lastUsedAt: Date
    let isPinned: Bool
    let collectionIDs: Set<UUID>
    let kind: ClipboardPayload.Kind
    let thumbnail: Data?

    var isProtected: Bool { isPinned || !collectionIDs.isEmpty }

    init(
        id: UUID, text: String, sourceBundleIdentifier: String?, lastUsedAt: Date,
        isPinned: Bool = false, collectionIDs: Set<UUID> = [],
        kind: ClipboardPayload.Kind = .text, thumbnail: Data? = nil,
        probableSourceBundleIdentifier: String? = nil, isRemote: Bool = false
    ) {
        self.id = id
        self.text = text
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.probableSourceBundleIdentifier = probableSourceBundleIdentifier
        self.isRemote = isRemote
        self.lastUsedAt = lastUsedAt
        self.isPinned = isPinned
        self.collectionIDs = collectionIDs
        self.kind = kind
        self.thumbnail = thumbnail
    }
}
