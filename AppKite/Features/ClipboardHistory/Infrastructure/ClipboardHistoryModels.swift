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
    // Nil identifies older entries. Empty data marks a prepared preview without table rows.
    var previewRowsData: Data?

    init(text: String, fingerprint: String, sourceBundleIdentifier: String?, copiedAt: Date) {
        self.id = UUID()
        self.text = text
        self.fingerprint = fingerprint
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.lastCopiedAt = copiedAt
        self.lastUsedAt = copiedAt
    }

    var entry: ClipboardEntry { card(includingThumbnail: true) }

    func setPreviewRows(_ rows: [[String]]) throws {
        previewRowsData = rows.isEmpty ? Data() : try JSONEncoder().encode(rows)
    }

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
            isRemote: isRemote == true,
            tablePreviewRows: tablePreviewRows
        )
    }

    var isProtected: Bool { isPinned || collections?.isEmpty == false }

    private var tablePreviewRows: [[String]] {
        guard let previewRowsData, !previewRowsData.isEmpty else { return [] }
        return (try? JSONDecoder().decode([[String]].self, from: previewRowsData)) ?? []
    }
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
