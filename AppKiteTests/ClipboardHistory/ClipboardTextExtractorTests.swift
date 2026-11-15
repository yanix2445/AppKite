import AppKit
import CoreText
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers

@testable import AppKite

struct ClipboardTextExtractorTests {
    private typealias Item = ClipboardPayload.Item
    private typealias Representation = ClipboardPayload.Representation
    private typealias PasteboardType = NSPasteboard.PasteboardType

    @Test func `Immediate index keeps complete text, URLs and table values`() {
        let longText = String(repeating: "copie ", count: 800) + "DernierMot"
        let address = "https://example.org/projets?etat=actif#comptes"
        let rows = "Mars\t123\nAvril\t456"
        let payload = ClipboardPayload(items: [
            .init(representations: [
                representation(.string, longText),
                representation(.URL, address),
                representation(.tabularText, rows),
            ])
        ])

        let indexed = ClipboardTextExtractor.immediateText(in: payload)

        #expect(indexed.contains(longText))
        #expect(indexed.contains(address))
        #expect(indexed.contains(rows))
        #expect(!ClipboardTextExtractor.requiresRecognition(payload))
    }

    @Test func `HTML with a URL indexes the visible text`() {
        let html = "<html><body><h1>Rapport annuel</h1><script>Interne123</script></body></html>"
        let payload = ClipboardPayload(items: [
            .init(representations: [
                representation(.URL, "https://example.org/rapport"),
                representation(.html, html),
            ])
        ])

        let indexed = ClipboardTextExtractor.immediateText(in: payload)
        #expect(indexed.contains("Rapport annuel"))
        #expect(indexed.contains("https://example.org/rapport"))
        #expect(!indexed.contains("Interne123"))
    }

    @Test func `Finder folders contribute only their names even when a nested PDF is readable`()
        throws
    {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "Dossier Projet \(UUID().uuidString)", directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pdf = try makePDF(selectable: "CHAPITRE ORCHIDEE", raster: makeImage("VENTE MANDARINE"))
        try pdf.write(to: folder.appending(path: "archives.pdf"))
        let payload = ClipboardPayload(items: [
            .init(representations: [], fileURL: folder)
        ])

        #expect(ClipboardTextExtractor.immediateText(in: payload) == folder.lastPathComponent)
        #expect(!ClipboardTextExtractor.requiresRecognition(payload))
        #expect(try ClipboardTextExtractor.recognizedText(in: payload).isEmpty)
    }

    @Test func `A directly copied image becomes searchable and stays searchable after reopening`()
        async throws
    {
        let image = try makeImage("PLANETE CERISE")
        let bytes = NSMutableData()
        let encoder = try #require(
            CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(encoder, image, nil)
        try #require(CGImageDestinationFinalize(encoder))
        let payload = ClipboardPayload(items: [
            .init(representations: [
                Representation(type: PasteboardType.png.rawValue, data: bytes as Data)
            ])
        ])

        #expect(ClipboardTextExtractor.requiresRecognition(payload))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "history.store")
        let query = ClipboardHistoryQuery(text: "cerise", kind: .image, source: "com.apple.Safari")
        let card: ClipboardEntry
        do {
            let store = try await SwiftDataClipboardHistoryStore.open(at: storeURL)
            try await store.record(
                payload: payload, sourceBundleIdentifier: "com.apple.Safari", at: .now)
            #expect(try await store.search(query).entries.isEmpty)
            #expect(try await store.indexNextPendingEntry())
            #expect(try await !store.indexNextPendingEntry())
            let results = try await store.search(query)
            card = try #require(results.entries.first)
            #expect(card.thumbnail == nil)
            #expect(try await store.thumbnails(for: [card.id])[card.id] != nil)
        }

        let reopened = try await SwiftDataClipboardHistoryStore.open(at: storeURL)
        let recovered = try await reopened.search(query)
        #expect(recovered.entries.map(\.id) == [card.id])
    }

    @Test func `A hybrid PDF indexes selectable words and the scanned region on the same page`()
        throws
    {
        let pdf = try makePDF(selectable: "CHAPITRE ORCHIDEE", raster: makeImage("VENTE MANDARINE"))
        let document = try #require(PDFDocument(data: pdf))
        let selectable = try #require(document.page(at: 0)?.string)
        #expect(selectable.contains("ORCHIDEE"))
        #expect(!selectable.contains("MANDARINE"))
        let payload = ClipboardPayload(items: [
            .init(representations: [Representation(type: PasteboardType.pdf.rawValue, data: pdf)])
        ])

        #expect(ClipboardTextExtractor.requiresRecognition(payload))
        let indexed = try ClipboardTextExtractor.recognizedText(in: payload)
        #expect(indexed.localizedCaseInsensitiveContains("ORCHIDEE"))
        #expect(indexed.localizedCaseInsensitiveContains("MANDARINE"))
    }

    private func representation(_ type: PasteboardType, _ text: String) -> Representation {
        Representation(type: type.rawValue, data: Data(text.utf8))
    }

    private func makeImage(_ text: String) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 950, height: 210, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 950, height: 210))
        draw(text, in: context, x: 32, y: 70, size: 76)
        return try #require(context.makeImage())
    }

    private func makePDF(selectable: String, raster: CGImage) throws -> Data {
        let bytes = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: bytes))
        var bounds = CGRect(x: 0, y: 0, width: 650, height: 450)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        draw(selectable, in: context, x: 32, y: 350, size: 28)
        context.draw(raster, in: CGRect(x: 20, y: 60, width: 610, height: 135))
        context.endPDFPage()
        context.closePDF()
        return bytes as Data
    }

    private func draw(_ text: String, in context: CGContext, x: CGFloat, y: CGFloat, size: CGFloat)
    {
        let attributes =
            [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
                    "Helvetica-Bold" as CFString, size, nil
                ),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
                    gray: 0, alpha: 1),
            ] as [NSAttributedString.Key: Any]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }
}
