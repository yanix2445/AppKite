import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AppKite

struct ClipboardPreviewTests {
    @Test func archivedFileAndDirectPNGKeepTheWholeImage() async throws {
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let archive = try ClipboardArchive(root: workspace.appending(path: "archive"))
        let png = try imageData(width: 1_200, height: 200, type: .png)
        let original = workspace.appending(path: "Panorama.png")
        try png.write(to: original)
        let file = try archive.stage(
            .init(items: [.init(representations: [], fileURL: original)]), id: UUID())
        let direct = try archive.stage(
            .init(items: [
                .init(representations: [.init(type: UTType.png.identifier, data: png)])
            ]), id: UUID())
        try archive.publish(file)
        try archive.publish(direct)
        try FileManager.default.removeItem(at: original)

        let reopened = try ClipboardArchive(root: workspace.appending(path: "archive"))
        let filePreview = try #require(
            await ClipboardPreviewRenderer.render(reopened.previewSource(for: file.id)))
        let directPreview = try #require(
            await ClipboardPreviewRenderer.render(reopened.previewSource(for: direct.id)))
        #expect(filePreview.kind == .image)
        #expect(filePreview.name == original.lastPathComponent)
        #expect(filePreview.content == directPreview.content)
        guard case .picture(let picture) = filePreview.content else {
            Issue.record("La copie archivée ne produit pas d’image")
            return
        }
        #expect(picture.pixelWidth == 1_200)
        #expect(picture.pixelHeight == 200)
        #expect(picture.hasTransparency)
        let rendition = try decodedPNG(picture.png)
        #expect(rendition.width <= 512)
        #expect(abs(Double(rendition.width) / Double(rendition.height) - 6) < 0.1)
        #expect(try reopened.load(id: direct.id).items.first?.representations.first?.data == png)
    }

    @Test func portraitOrientationControlsDimensionsAndThumbnail() async throws {
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let file = workspace.appending(path: "Portrait.jpg")
        try imageData(width: 180, height: 90, type: .jpeg, orientation: 6).write(to: file)
        let preview = try #require(await ClipboardPreviewRenderer.render(source(file)))

        guard case .picture(let picture) = preview.content else {
            Issue.record("La photo orientée ne produit pas d’image")
            return
        }
        #expect(picture.pixelWidth == 90)
        #expect(picture.pixelHeight == 180)
        let rendition = try decodedPNG(picture.png)
        #expect(rendition.width * 2 == rendition.height)
    }

    @Test func readableImageSurvivesAnUnreadableMovieRepresentation() async throws {
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let archive = try ClipboardArchive(root: workspace.appending(path: "archive"))
        let png = try imageData(width: 80, height: 40, type: .png)
        let staged = try archive.stage(
            .init(items: [
                .init(representations: [
                    .init(
                        type: UTType.quickTimeMovie.identifier, data: Data("Unreadable MOV".utf8)),
                    .init(type: UTType.png.identifier, data: png),
                ])
            ]), id: UUID())
        try archive.publish(staged)

        let preview = try #require(
            await ClipboardPreviewRenderer.render(
                archive.previewSource(for: staged.id), media: ClipboardMediaPreview.render))
        #expect(preview.kind == .image)
        #expect(preview.format == "PNG")
        guard case .picture(let picture) = preview.content else {
            Issue.record("Le PNG lisible est masqué par la vidéo illisible.")
            return
        }
        #expect(picture.pixelWidth == 80)
    }

    @Test(arguments: [true, false])
    func filePreviewFallsBackToArchivedImageAndKeepsName(fileIsReadable: Bool) async throws {
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let archive = try ClipboardArchive(root: workspace.appending(path: "archive"))
        let original = workspace.appending(path: "Original.png")
        let fileBytes =
            fileIsReadable ? try imageData(width: 160, height: 90, type: .png) : Data([0, 1, 2])
        let fallback = try imageData(width: 80, height: 40, type: .png)
        try fileBytes.write(to: original)
        let staged = try archive.stage(
            .init(items: [
                .init(
                    representations: [.init(type: UTType.png.identifier, data: fallback)],
                    fileURL: original)
            ]), id: UUID())
        try archive.publish(staged)
        try FileManager.default.removeItem(at: original)

        let preview = try #require(
            await ClipboardPreviewRenderer.render(archive.previewSource(for: staged.id)))
        #expect(preview.name == original.lastPathComponent)
        #expect(preview.kind == .image)
        guard case .picture(let picture) = preview.content else {
            Issue.record("L’image archivée ne produit pas d’aperçu.")
            return
        }
        #expect(picture.pixelWidth == (fileIsReadable ? 160 : 80))

        let archived = try #require(try archive.load(id: staged.id).items.first)
        let archivedFile = try #require(archived.fileURL)
        #expect(try Data(contentsOf: archivedFile) == fileBytes)
        #expect(archived.representations.first?.data == fallback)
    }

    @Test(arguments: [true, false])
    func anAnimatedGIFIsPreferredWithPNGAsFallback(gifIsReadable: Bool) async throws {
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let archive = try ClipboardArchive(root: workspace.appending(path: "archive"))
        let png = try imageData(width: 24, height: 16, type: .png)
        let gif = gifIsReadable ? try animatedGIF() : Data("Unreadable GIF".utf8)
        let staged = try archive.stage(
            .init(items: [
                .init(representations: [
                    .init(type: UTType.png.identifier, data: png),
                    .init(type: UTType.gif.identifier, data: gif),
                ])
            ]), id: UUID())
        try archive.publish(staged)

        let preview = try #require(
            await ClipboardPreviewRenderer.render(archive.previewSource(for: staged.id)))
        #expect(preview.format == (gifIsReadable ? "GIF" : "PNG"))
        #expect(preview.media?.kind == (gifIsReadable ? .gif : nil))
        if let media = preview.media {
            #expect(try Data(contentsOf: media.url) == gif)
        }
    }

    @Test func documentPreviewUsesTheFirstPDFPage() async throws {
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let file = workspace.appending(path: "Deux pages.pdf")
        var bounds = CGRect(x: 0, y: 0, width: 200, height: 400)
        let document = try #require(CGContext(file as CFURL, mediaBox: &bounds, nil))
        for color in [
            CGColor(red: 1, green: 0, blue: 0, alpha: 1),
            CGColor(red: 0, green: 0, blue: 1, alpha: 1),
        ] {
            document.beginPDFPage(nil)
            document.setFillColor(color)
            document.fill(bounds)
            document.endPDFPage()
        }
        document.closePDF()

        let preview = try #require(await ClipboardPreviewRenderer.render(source(file)))
        #expect(preview.kind == .document)
        #expect(preview.name == file.lastPathComponent)
        guard case .picture(let picture) = preview.content else {
            Issue.record("La première page du PDF est manquante")
            return
        }
        let rendition = try decodedPNG(picture.png)
        #expect(rendition.width * 2 == rendition.height)
        let rgba = try pixel(rendition)
        // Color conversion may lift secondary channels. The first page is red, the second blue.
        #expect(Int(rgba[0]) > Int(rgba[2]) + 80)
    }

    @Test(arguments: ["docx", "odt"])
    func archivedDocumentReturnsAPageInsteadOfAFileIcon(fileExtension: String) async throws {
        let bundle = Bundle(for: FixtureBundle.self)
        let document = try #require(
            bundle.url(forResource: "Document", withExtension: fileExtension)
                ?? bundle.url(
                    forResource: "Document", withExtension: fileExtension,
                    subdirectory: "PreviewFixtures")
        )
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let archive = try ClipboardArchive(root: workspace.appending(path: "archive"))
        let staged = try archive.stage(
            .init(items: [.init(representations: [], fileURL: document)]), id: UUID())
        try archive.publish(staged)
        let preview = try #require(
            await ClipboardPreviewRenderer.render(archive.previewSource(for: staged.id)))
        #expect(preview.name == "Document.\(fileExtension)")
        #expect(preview.format == fileExtension.uppercased())
        guard case .picture(let picture) = preview.content else {
            Issue.record("Quick Look n’a pas produit de page \(fileExtension.uppercased())")
            return
        }
        let rendition = try decodedPNG(picture.png)
        #expect(rendition.width < rendition.height)
        #expect(max(rendition.width, rendition.height) <= 512)
    }

    @Test func csvFilesAndNativeTabularDataKeepQuotedFields() async throws {
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let csv = workspace.appending(path: "Table.csv")
        let tsv = workspace.appending(path: "Table.tsv")
        let binary = workspace.appending(path: "representation.bin")
        let csvText = try #require(
            ("\"A,B\",Valeur\r\n\"Ligne 1\nLigne 2\",€\r\n\""
                + String(repeating: "x", count: 10_000)).data(using: .utf16))
        let tsvText = "\"A\tB\"\tValeur\n\"Ligne 1\nLigne 2\"\t€"
        try csvText.write(to: csv)
        try Data(tsvText.utf8).write(to: tsv)
        try Data(tsvText.utf8).write(to: binary)

        let csvPreview = await ClipboardPreviewRenderer.render(source(csv))
        let tsvPreview = await ClipboardPreviewRenderer.render(source(tsv))
        let directPreview = await ClipboardPreviewRenderer.render(
            .init(items: [
                .init(
                    fileURL: nil,
                    representations: [
                        .init(type: NSPasteboard.PasteboardType.tabularText.rawValue, url: binary)
                    ])
            ]))
        #expect(csvPreview?.content == .table([["A,B", "Valeur"], ["Ligne 1\nLigne 2", "€"]]))
        #expect(tsvPreview?.content == .table([["A\tB", "Valeur"], ["Ligne 1\nLigne 2", "€"]]))
        #expect(tsvPreview?.content == directPreview?.content)
    }

    @Test func tablesKeepCompleteRowsAtTheReadLimit() async throws {
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let fixtures = [
            ("csv", ",", "\n", "\n", String.Encoding.utf8),
            ("tsv", "\t", "\r\n", "\r\n", String.Encoding.utf16),
            ("tsv", "\t", "\r\n", "\r", String.Encoding.utf16),
        ]

        for (index, fixture) in fixtures.enumerated() {
            let (fileExtension, delimiter, newline, newlinePrefix, encoding) = fixture
            let file = workspace.appending(path: "Table-\(index).\(fileExtension)")
            let firstCell = "Nom\(delimiter)"
            let fixed = try #require((firstCell + newlinePrefix).data(using: encoding))
            let bytesPerCharacter = encoding == .utf16 ? 2 : 1
            let padding = String(repeating: "x", count: (8_192 - fixed.count) / bytesPerCharacter)
            let row = firstCell + padding
            let prefix = try #require((row + newlinePrefix).data(using: encoding))
            try #require(prefix.count == 8_192)
            let csv = try #require((row + newline + "Suite\(delimiter)z").data(using: encoding))
            try csv.write(to: file)

            let preview = await ClipboardPreviewRenderer.render(source(file))
            #expect(preview?.content == .table([["Nom", String(repeating: "x", count: 120)]]))
        }
    }

    @Test func aClippedRepresentationWithoutRowsDoesNotMaskAReadableTable() async throws {
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let tsv = workspace.appending(path: "tsv.bin")
        let csv = workspace.appending(path: "csv.bin")
        try Data(repeating: 0x78, count: 8_193).write(to: tsv)
        try Data("Nom,Valeur\nA,1".utf8).write(to: csv)
        let first = ClipboardPreviewSource.Item.Representation(
            type: NSPasteboard.PasteboardType.tabularText.rawValue, url: tsv)
        let second = ClipboardPreviewSource.Item.Representation(
            type: UTType.commaSeparatedText.identifier, url: csv)

        let clipped = await ClipboardPreviewRenderer.render(
            .init(items: [.init(fileURL: nil, representations: [first])]))
        #expect(clipped?.content == .unavailable)

        let preview = await ClipboardPreviewRenderer.render(
            .init(items: [.init(fileURL: nil, representations: [first, second])]))
        #expect(preview?.content == .table([["Nom", "Valeur"], ["A", "1"]]))
        #expect(preview?.format == "CSV")
    }

    @Test func folderMosaicCountsImmediateChildrenAndNeverFollowsLinks() async throws {
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let folder = workspace.appending(path: "Dossier", directoryHint: .isDirectory)
        let nested = folder.appending(path: "03 Sous-dossier", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let png = try imageData(width: 20, height: 10, type: .png)
        let external = workspace.appending(path: "Image extérieure.png")
        try png.write(to: external)
        try png.write(to: folder.appending(path: "01 Image.png"))
        try FileManager.default.createSymbolicLink(
            at: folder.appending(path: "02 Lien.png"), withDestinationURL: external)
        try png.write(to: nested.appending(path: "Enfant.png"))
        try png.write(to: folder.appending(path: "04 Image.png"))
        try Data([0]).write(to: folder.appending(path: "05 Données.bin"))

        let preview = try #require(await ClipboardPreviewRenderer.render(source(folder)))
        guard case .mosaic(let tiles, let count) = preview.content else {
            Issue.record("Le dossier archivé ne produit pas de mosaïque")
            return
        }
        #expect(preview.kind == .folder)
        #expect(count == 5)
        #expect(
            tiles.map(\.name) == ["01 Image.png", "02 Lien.png", "03 Sous-dossier", "04 Image.png"])
        #expect(tiles[0].picture != nil)
        #expect(tiles[1].picture == nil)
        #expect(tiles[2].picture == nil)
        #expect(tiles[3].picture != nil)
    }

    @Test func aSelectionPreservesOrderAndUnavailableFilesStayIdentifiable() async throws {
        let workspace = try workspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let unknown = workspace.appending(path: "Second dans le nom.bin")
        let image = workspace.appending(path: "Premier dans le nom.png")
        try Data([1, 2, 3]).write(to: unknown)
        try imageData(width: 20, height: 10, type: .png).write(to: image)
        let preview = try #require(
            await ClipboardPreviewRenderer.render(
                .init(items: [unknown, image].map { .init(fileURL: $0, representations: []) })))
        guard case .mosaic(let tiles, let count) = preview.content else {
            Issue.record("La sélection archivée ne produit pas de mosaïque")
            return
        }
        #expect(preview.kind == .selection)
        #expect(count == 2)
        #expect(tiles.map(\.name) == [unknown.lastPathComponent, image.lastPathComponent])
        #expect(tiles[0].picture == nil)
        #expect(tiles[1].picture != nil)
        let unavailable = await ClipboardPreviewRenderer.render(source(unknown))
        #expect(unavailable?.content == .unavailable)
        #expect(unavailable?.name == unknown.lastPathComponent)
        #expect(unavailable?.format == "BIN")
    }

    private final class FixtureBundle: NSObject {}

    private func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func source(_ url: URL) -> ClipboardPreviewSource {
        .init(items: [.init(fileURL: url, representations: [])])
    }

    private func imageData(
        width: Int, height: Int, type: UTType, orientation: Int = 1
    ) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(
            destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func decodedPNG(_ png: Data) throws -> CGImage {
        let image = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(image, 0, nil))
    }

    private func animatedGIF() throws -> Data {
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 2, nil))
        let png = try imageData(width: 32, height: 16, type: .png)
        let frame = try decodedPNG(png)
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]
        ]
        for _ in 0..<2 {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixel(_ image: CGImage) throws -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try #require(
                CGContext(
                    data: bytes.baseAddress,
                    width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba
    }
}
