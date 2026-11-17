import Foundation

nonisolated struct ClipboardPreview: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case image
        case document
        case table
        case folder
        case selection
        case audio
        case video
    }

    struct Picture: Equatable, Sendable {
        let png: Data
        var pixelWidth: Int? = nil
        var pixelHeight: Int? = nil
        var hasTransparency = false
    }

    struct Tile: Equatable, Sendable {
        let name: String
        let picture: Picture?
    }

    struct Media: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case gif, audio, video }

        let kind: Kind
        let url: URL
        var duration: Double? = nil
        var mimeType: String? = nil
    }

    enum Content: Equatable, Sendable {
        case picture(Picture)
        case table([[String]])
        case waveform([Float])
        case mosaic(tiles: [Tile], count: Int)
        case unavailable
    }

    let kind: Kind
    let content: Content
    var name: String? = nil
    var format: String? = nil
    var byteCount: Int64? = nil
    var media: Media? = nil
}

nonisolated struct ClipboardPreviewSource: Sendable {
    struct Item: Sendable {
        struct Representation: Sendable {
            let type: String
            let url: URL
        }

        let fileURL: URL?
        let representations: [Representation]
    }

    let items: [Item]
}
