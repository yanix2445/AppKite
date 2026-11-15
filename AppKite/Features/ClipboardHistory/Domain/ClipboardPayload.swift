import Foundation

nonisolated struct ClipboardPayload: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case text
        case richText
        case link
        case image
        case files
        case spreadsheet
        case pdf
        case color
        case mixed
    }

    struct Item: Equatable, Sendable {
        let representations: [Representation]
        let fileURL: URL?

        init(representations: [Representation], fileURL: URL? = nil) {
            self.representations = representations
            self.fileURL = fileURL
        }
    }

    struct Representation: Equatable, Sendable {
        let type: String
        let data: Data
    }

    static let utf8TextType = "public.utf8-plain-text"
    let items: [Item]

    static func plainText(_ text: String) -> Self {
        Self(items: [
            Item(representations: [
                Representation(type: utf8TextType, data: Data(text.utf8))
            ])
        ])
    }

    var plainText: String? {
        guard items.count == 1, let item = items.first, item.fileURL == nil,
            item.representations.count == 1,
            let representation = item.representations.first,
            representation.type == Self.utf8TextType
        else { return nil }
        return String(data: representation.data, encoding: .utf8)
    }
}
