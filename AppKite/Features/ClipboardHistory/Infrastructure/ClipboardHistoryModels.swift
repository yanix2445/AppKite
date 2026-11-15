import Foundation
import SwiftData

@Model
nonisolated final class StoredClipboardEntry {
    #Index<StoredClipboardEntry>([\.fingerprint], [\.lastUsedAt])

    @Attribute(.unique) var id: UUID
    var text: String
    var fingerprint: String
    var sourceBundleIdentifier: String?
    var probableSourceBundleIdentifier: String?
    var isRemote: Bool?
    var lastCopiedAt: Date
    var lastUsedAt: Date
    var isPinned: Bool = false
    var collections: [StoredClipboardCollection]?
    var hasArchive: Bool = false
    var kindIdentifier: String?
    var thumbnail: Data?
    var indexedText: String?
    var recognizedText: String?
    var needsRecognition: Bool = false

    init(text: String, fingerprint: String, sourceBundleIdentifier: String?, copiedAt: Date) {
        self.id = UUID()
        self.text = text
        self.fingerprint = fingerprint
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.lastCopiedAt = copiedAt
        self.lastUsedAt = copiedAt
    }

    var entry: ClipboardEntry { card(includingThumbnail: true) }

    func card(includingThumbnail: Bool) -> ClipboardEntry {
        ClipboardEntry(
            id: id,
            text: text,
            sourceBundleIdentifier: sourceBundleIdentifier,
            lastUsedAt: lastUsedAt,
            isPinned: isPinned,
            collectionIDs: Set((collections ?? []).map(\.id)),
            kind: kindIdentifier.flatMap(ClipboardPayload.Kind.init(rawValue:)) ?? .text,
            thumbnail: includingThumbnail ? thumbnail : nil,
            probableSourceBundleIdentifier: probableSourceBundleIdentifier,
            isRemote: isRemote == true
        )
    }

    var isProtected: Bool { isPinned || collections?.isEmpty == false }
}

@Model
nonisolated final class StoredClipboardCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    @Relationship(deleteRule: .nullify, inverse: \StoredClipboardEntry.collections)
    var entries: [StoredClipboardEntry]?

    init(name: String) {
        self.id = UUID()
        self.name = name
    }

    var collection: ClipboardCollection {
        ClipboardCollection(id: id, name: name)
    }
}
