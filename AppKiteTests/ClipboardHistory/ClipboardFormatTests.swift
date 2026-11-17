import AppKit
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers

@testable import AppKite

@MainActor
struct ClipboardFormatTests {
    private typealias Format = NSPasteboard.PasteboardType
    private typealias Representation = ClipboardPayload.Representation

    @Test func `Plain text preserves UTF-8 bytes and line boundaries`() throws {
        let text = "  Cafe\u{301}\t📎\n\n "
        let payload = try roundTrip([.init(representations: [representation(.string, text)])])
        #expect(payload.plainText?.utf8.elementsEqual(text.utf8) == true)
        #expect(ClipboardFormatCodec.presentation(for: payload).kind == .text)
    }

    @Test func `A UTF-16 only copy shares decoding between preview and search`() throws {
        let value = "Résumé 🙌"
        let encoded = try #require(value.data(using: .utf16))
        let payload = ClipboardPayload(items: [
            .init(representations: [
                .init(type: UTType.utf16PlainText.identifier, data: encoded)
            ])
        ])

        #expect(ClipboardFormatCodec.presentation(for: payload).summary == value)
        #expect(ClipboardTextExtractor.immediateText(in: payload) == value)
    }

    @Test func `A preview clips on a complete grapheme and the index keeps full text`() {
        let prefix = String(repeating: "👩‍💻", count: 218)
        let value = prefix + "e\u{301} et la suite"
        let payload = ClipboardPayload.plainText(value)
        let preview = ClipboardFormatCodec.presentation(for: payload).summary

        #expect(preview == prefix)
        #expect(ClipboardTextExtractor.immediateText(in: payload) == value)
    }

    @Test func `Rich text preserves attributes alongside the plain version`() throws {
        let attributed = NSAttributedString(
            string: "Texte",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 16), .foregroundColor: NSColor.red]
        )
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let payload = try roundTrip([
            .init(representations: [
                Representation(type: Format.rtf.rawValue, data: data),
                representation(.string, attributed.string),
            ])
        ])
        #expect(ClipboardFormatCodec.presentation(for: payload).kind == .richText)
        let restoredData = try #require(payload.items.first?.representations.first?.data)
        let restored = try NSAttributedString(
            data: restoredData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        #expect(restored.string == attributed.string)
        let font = try #require(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    @Test func `A URL retains its destination and display name`() throws {
        let address = "https://example.org/rendez-vous?q=1#date"
        let payload = try roundTrip([
            .init(representations: [
                representation(.URL, address), representation(.init("public.url-name"), "Planning"),
                representation(.string, address),
            ])
        ])
        let presentation = ClipboardFormatCodec.presentation(for: payload)
        #expect(presentation.kind == .link)
        #expect(presentation.summary == address)
    }

    @Test func `An image retains its full resolution and provides a small thumbnail`() throws {
        let png = try makePNG()
        let payload = try roundTrip([
            .init(representations: [
                Representation(type: Format.png.rawValue, data: png)
            ])
        ])
        let presentation = ClipboardFormatCodec.presentation(for: payload)
        #expect(presentation.kind == .image)
        let thumbnail = try #require(presentation.thumbnail)
        let source = try #require(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(max(image.width, image.height) <= 320)
        #expect(payload.items[0].representations[0].data == png)
    }

    @Test func `Direct audiovisual representations keep their bytes and take priority over text`()
        throws
    {
        let movie = Representation(type: UTType.quickTimeMovie.identifier, data: Data([8, 9, 10]))
        let audio = Representation(type: UTType.mpeg4Audio.identifier, data: Data([1, 2, 3]))
        let text = representation(.string, "Description du média")
        let payload = try roundTrip([.init(representations: [movie, text, audio])])

        #expect(ClipboardFormatCodec.presentation(for: payload).kind == .mixed)
        let media = payload.items[0].representations.filter { $0 == movie || $0 == audio }
        #expect(media == [movie, audio])
    }

    @Test func `A media file URL stays a file when Finder supplies media bytes too`() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Capture.mov")
        let bytes = Data([1, 2, 3])
        try bytes.write(to: url)
        let movie = Representation(type: UTType.quickTimeMovie.identifier, data: bytes)
        let payload = try roundTrip(
            [.init(representations: [movie], fileURL: url)],
            expected: [.init(representations: [], fileURL: url)])

        #expect(payload.items[0].representations.isEmpty)
        #expect(ClipboardFormatCodec.presentation(for: payload).kind == .files)
    }

    @Test func `A Finder selection preserves both file URLs and their order`() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = [
            folder.appending(path: "Dossier été", directoryHint: .isDirectory),
            folder.appending(path: "facture + mars.pdf"),
        ]
        try FileManager.default.createDirectory(at: urls[0], withIntermediateDirectories: false)
        try Data().write(to: urls[1])
        let payload = try roundTrip(urls.map { .init(representations: [], fileURL: $0) })
        #expect(payload.items.compactMap(\.fileURL) == urls)
        let presentation = ClipboardFormatCodec.presentation(for: payload)
        #expect(presentation.kind == .files)
        #expect(presentation.summary == "Dossier été\nfacture + mars.pdf")
    }

    @Test func `File replay omits the original path disguised as text`() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "Version précédente.pdf")
        try Data().write(to: file)
        let payload = try roundTrip(
            [
                .init(representations: [representation(.string, file.path)], fileURL: file)
            ], expected: [.init(representations: [], fileURL: file)])
        #expect(payload.items[0].representations.isEmpty)
    }

    @Test func `Native spreadsheet data and standard tabular values are replayed together`() throws
    {
        let values = "Article\tQuantité\nPommes\t4\nPoires\t2"
        let native = representation(.init("com.apple.iWork.TSTNativeData"), "Cellules et formules")
        let plain = representation(.string, values)
        let tabular = representation(.tabularText, values)
        let input = ClipboardPayload.Item(representations: [native, plain])
        let payload = try roundTrip(
            [input],
            expected: [
                .init(representations: [native, plain, tabular])
            ])
        let presentation = ClipboardFormatCodec.presentation(for: payload)
        #expect(presentation.kind == .spreadsheet)
        #expect(presentation.summary == values)
        #expect(payload.items[0].representations[0] == native)
    }

    @Test func `Tabular fallback preserves a single column and empty rows`() throws {
        let values = "Lundi\n\nMercredi"
        let input = ClipboardPayload.Item(representations: [representation(.tabularText, values)])
        let payload = try roundTrip(
            [input],
            expected: [
                .init(representations: input.representations + [representation(.string, values)])
            ])
        #expect(ClipboardFormatCodec.presentation(for: payload).summary == values)
    }

    @Test func `CSV and TSV previews read quoted cells and bound the grid`() {
        let csv = representation(
            .init(UTType.commaSeparatedText.identifier),
            "\"Été, pommes\",,\"a\"\"b\",masqué\r\n\"ligne 1\r\nligne 2\",prix\r\n3,4,\r\n5,6\r\nmasqué"
        )
        let tsv = representation(.tabularText, "\"A\tB\"\t\"ligne 1\nligne 2\"\t\"a\"\"b\"")
        let tsvPreview = ClipboardFormatCodec.presentation(
            for: ClipboardPayload(items: [.init(representations: [tsv])]))
        let csvPreview = ClipboardFormatCodec.presentation(
            for: ClipboardPayload(items: [.init(representations: [csv])]))

        #expect(csvPreview.kind == .spreadsheet)
        #expect(
            csvPreview.tablePreviewRows == [
                ["Été, pommes", "", "a\"b"], ["ligne 1\r\nligne 2", "prix"], ["3", "4", ""],
                ["5", "6"],
            ])
        #expect(tsvPreview.tablePreviewRows == [["A\tB", "ligne 1\nligne 2", "a\"b"]])
    }

    @Test func `A bounded table preview keeps prior rows when the next quoted cell is clipped`() {
        let csv = representation(
            .init(UTType.commaSeparatedText.identifier),
            "A,B\n\"" + String(repeating: "long", count: 3_000) + "\",D"
        )
        let payload = ClipboardPayload(items: [.init(representations: [csv])])

        #expect(ClipboardFormatCodec.presentation(for: payload).tablePreviewRows == [["A", "B"]])
    }

    @Test
    func `An archived CSV card recovers its grid from the original representation after reopening`()
        async throws
    {
        let directory = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "history.store")
        let id = try writeOldCSVCard(at: storeURL)
        let rows = [["A", "B"], ["C", "D"]]
        let query = ClipboardHistoryQuery(kind: .spreadsheet)

        do {
            let store = try await SwiftDataClipboardHistoryStore.open(at: storeURL)
            #expect(try await store.search(query).entries.first?.tablePreviewRows == [])
            #expect(try await store.indexNextPendingEntry())
            #expect(try await !store.indexNextPendingEntry())
            let updated = try #require(try await store.search(query).entries.first)
            #expect(updated.id == id)
            #expect(updated.tablePreviewRows == rows)
            #expect(updated.isPinned)
            #expect(
                try await store.payload(for: id).items[0].representations == [
                    representation(.init(UTType.commaSeparatedText.identifier), "A,B\nC,D")
                ])
        }

        let reopened = try await SwiftDataClipboardHistoryStore.open(at: storeURL)
        #expect(try await reopened.search(query).entries.first?.tablePreviewRows == rows)
        #expect(try await !reopened.indexNextPendingEntry())
    }

    private func writeOldCSVCard(at storeURL: URL) throws -> UUID {
        let schema = Schema([StoredClipboardEntry.self, StoredClipboardCollection.self])
        let configuration = ModelConfiguration(
            schema: schema, url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        let archive = try ClipboardArchive(
            root: storeURL.deletingLastPathComponent().appending(path: "archives"))
        let csv = representation(.init(UTType.commaSeparatedText.identifier), "A,B\nC,D")
        let payload = ClipboardPayload(items: [.init(representations: [csv])])
        let card = StoredClipboardEntry(
            text: "A,B\nC,D", fingerprint: "", sourceBundleIdentifier: nil, copiedAt: .now)
        let staged = try archive.stage(payload, id: card.id)
        try archive.publish(staged)
        card.fingerprint = staged.fingerprint
        card.hasArchive = true
        card.isPinned = true
        card.kindIdentifier = ClipboardPayload.Kind.spreadsheet.rawValue
        card.indexedText = "A,B\nC,D"
        context.insert(card)
        try context.save()
        return card.id
    }

    @Test func `Replay adds a tabular fallback to archived CSV`() throws {
        let csv = representation(
            .init(UTType.commaSeparatedText.identifier),
            "\u{FEFF}\"Été, pommes\",,\"a\"\"b\"\r\n,\"ligne 1\r\nligne 2\",\"a\tb\"\r\n\r\nfin,2,\r\n"
        )
        let values = "Été, pommes\t\t\"a\"\"b\"\n\t\"ligne 1\r\nligne 2\"\t\"a\tb\"\n\nfin\t2\t"
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let writer = PasteboardClient(pasteboard: pasteboard)
        let payload = ClipboardPayload(items: [.init(representations: [csv])])

        guard case .written = writer.write(payload, replacing: pasteboard.changeCount) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let item = try #require(pasteboard.pasteboardItems?.first)
        #expect(item.data(forType: .init(csv.type)) == csv.data)
        #expect(item.string(forType: .tabularText) == values)
        #expect(item.string(forType: .string) == values)
    }

    @Test func `CSV fallback preserves existing plain text and spreadsheet data`() {
        let csv = representation(.init(UTType.commaSeparatedText.identifier), "A,B\rC,D")
        let plain = representation(.string, "Résumé")
        let genericTSV = representation(.init(UTType.tabSeparatedText.identifier), "X\tY")
        let fallback = representation(.tabularText, "A\tB\nC\tD")
        let provided = [csv, plain, genericTSV]

        #expect(
            ClipboardFormatCodec.replayRepresentations([csv, plain]) == [csv, plain, fallback])
        #expect(
            ClipboardFormatCodec.replayRepresentations(provided)
                == provided + [representation(.tabularText, "X\tY")])
    }

    @Test func `Malformed CSV is replayed without a guessed table`() {
        let csv = representation(.init(UTType.commaSeparatedText.identifier), "A,\"unfinished")
        #expect(ClipboardFormatCodec.replayRepresentations([csv]) == [csv])
    }

    @Test func `CSV fallback distinguishes a final empty row from a line terminator`() {
        let csvType = Format(UTType.commaSeparatedText.identifier)
        let oneRow = [representation(csvType, "a\r\n")]
        let twoRows = [representation(csvType, "a\r\n\r\n")]
        #expect(
            ClipboardFormatCodec.replayRepresentations(oneRow)
                == oneRow + [representation(.tabularText, "a"), representation(.string, "a")])
        #expect(
            ClipboardFormatCodec.replayRepresentations(twoRows)
                == twoRows
                + [
                    representation(.tabularText, "a\n\"\""),
                    representation(.string, "a\n\"\""),
                ])
    }

    @Test func `Numbers native table markers preserve the table and its value fallback`() throws {
        let values = "19\t42\nVERDE\t31"
        let representations: [ClipboardPayload.Representation] = [
            representation(.init("com.apple.iWork.TSPNativeData"), "Native Numbers data"),
            representation(.init("com.apple.iWork.TSPNativeMetadata"), "Native metadata"),
            representation(.init("com.apple.iWork.TSPDescription"), "Native description"),
            representation(.init("com.apple.iWork.pasteboardState.applicationName-Numbers"), ""),
            representation(.init("com.apple.iWork.pasteboardState.hasTables"), ""),
            representation(.init("com.apple.iWork.pasteboardState.hasPastableFormulas"), ""),
            representation(.string, values),
        ]
        let payload = try roundTrip(
            [.init(representations: representations)],
            expected: [
                .init(representations: representations + [representation(.tabularText, values)])
            ]
        )
        #expect(ClipboardFormatCodec.presentation(for: payload).kind == .spreadsheet)
    }

    @Test func `PDF bytes and page geometry survive replay`() throws {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var bounds = CGRect(x: 0, y: 0, width: 640, height: 480)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 1, green: 0.4, blue: 0, alpha: 1))
        context.fill(bounds)
        context.endPDFPage()
        context.closePDF()

        let payload = try roundTrip([
            .init(representations: [
                Representation(type: Format.pdf.rawValue, data: data as Data)
            ])
        ])
        let presentation = ClipboardFormatCodec.presentation(for: payload)
        #expect(presentation.kind == .pdf)
        #expect(presentation.thumbnail != nil)
        let restored = try #require(
            CGDataProvider(data: payload.items[0].representations[0].data as CFData))
        let document = try #require(CGPDFDocument(restored))
        #expect(document.page(at: 1)?.getBoxRect(.mediaBox) == bounds)
    }

    @Test func `A native color is readable after replay`() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let client = PasteboardClient(pasteboard: pasteboard)
        let color = NSColor(srgbRed: 0.1, green: 0.3, blue: 0.5, alpha: 0.8)
        pasteboard.clearContents()
        try #require(pasteboard.writeObjects([color]))
        let copy = try #require(client.pollPayload())
        let preview = ClipboardFormatCodec.presentation(for: copy.payload)
        #expect(preview.kind == .color)
        #expect(preview.summary == "#1A4D80CC")
        if case .written = client.write(copy.payload, replacing: pasteboard.changeCount) {
            let restored = pasteboard.readObjects(forClasses: [NSColor.self])?.first as? NSColor
            #expect(restored?.usingColorSpace(.sRGB) == color.usingColorSpace(.sRGB))
        } else {
            Issue.record("Le presse-papiers de test n’a pas accepté la nuance.")
        }
    }

    @Test func `Mixed selections preserve separate items and embedded attachments`() throws {
        let png = try makePNG()
        let wrapper = FileWrapper(regularFileWithContents: png)
        wrapper.preferredFilename = "Illustration.png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        let attributed = NSMutableAttributedString(string: "Illustration\n")
        attributed.append(NSAttributedString(attachment: attachment))
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )
        let payload = try roundTrip([
            .init(representations: [
                Representation(type: Format.rtfd.rawValue, data: data),
                representation(.string, "Illustration"),
            ]),
            .init(representations: [representation(.string, "Légende")]),
        ])
        #expect(ClipboardFormatCodec.presentation(for: payload).kind == .mixed)
        let restored = try NSAttributedString(
            data: payload.items[0].representations[0].data,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        )
        #expect(restored.containsAttachments)
    }

    @Test func `A malformed file URL discards the entire selection`() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "Valide.pdf")
        try Data().write(to: file)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let client = PasteboardClient(pasteboard: pasteboard)
        let first = NSPasteboardItem()
        try #require(first.setString(file.absoluteString, forType: .fileURL))
        let second = NSPasteboardItem()
        try #require(second.setString("https://example.org/invalide", forType: .fileURL))
        try #require(second.setString("Repli texte", forType: .string))
        pasteboard.clearContents()
        try #require(pasteboard.writeObjects([first, second]))

        #expect(client.pollPayload() == nil)
        #expect(client.readStatus == .invalidFileSelection)
    }

    @Test func `Mixed declared sources are checked against app exclusions`() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let client = PasteboardClient(pasteboard: pasteboard)
        let declaredSource = Format("org.nspasteboard.source")
        let sources = ["example.org.Allowed", "example.org.Excluded"]

        func copy() throws {
            let items = try sources.map { source in
                let item = NSPasteboardItem()
                try #require(item.setString("Contenu", forType: .string))
                try #require(item.setString(source, forType: declaredSource))
                return item
            }
            pasteboard.clearContents()
            try #require(pasteboard.writeObjects(items))
        }

        try copy()
        #expect(client.pollPayload(isSourceExcluded: { $0 == sources[1] }) == nil)

        try copy()
        let result = try #require(client.pollPayload())
        #expect(result.sourceBundleIdentifier == nil)
        #expect(result.payload.items.count == 2)
    }

    private func roundTrip(
        _ items: [ClipboardPayload.Item],
        expected: [ClipboardPayload.Item]? = nil
    ) throws -> ClipboardPayload {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = PasteboardClient(pasteboard: pasteboard)
        let writer = PasteboardClient(pasteboard: pasteboard)
        let payload = ClipboardPayload(items: items)
        guard case .written = writer.write(payload, replacing: pasteboard.changeCount) else {
            Issue.record("Écriture sur le presse-papiers de test impossible.")
            throw CocoaError(.fileWriteUnknown)
        }
        let copy = try #require(reader.pollPayload())
        let expectedItems = expected ?? items
        try #require(copy.payload.items.count == expectedItems.count)
        for (capturedItem, expectedItem) in zip(copy.payload.items, expectedItems) {
            #expect(capturedItem.fileURL == expectedItem.fileURL)
            // AppKit can advertise an equivalent UTF-16 representation for a rich text item.
            for representation in expectedItem.representations {
                #expect(capturedItem.representations.contains(representation))
            }
        }
        #expect(writer.pollPayload() == nil)
        guard case .written = writer.write(copy.payload, replacing: pasteboard.changeCount) else {
            Issue.record("Restitution sur le presse-papiers de test impossible.")
            throw CocoaError(.fileWriteUnknown)
        }
        let replayed = try #require(reader.pollPayload())
        #expect(replayed.payload == copy.payload)
        return replayed.payload
    }

    private func representation(_ type: Format, _ value: String) -> Representation {
        Representation(type: type.rawValue, data: Data(value.utf8))
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func makePNG() throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: 800, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 400))
        let image = try #require(context.makeImage())
        let buffer = NSMutableData()
        let writer = try #require(
            CGImageDestinationCreateWithData(
                buffer, Format.png.rawValue as CFString, 1, nil
            ))
        CGImageDestinationAddImage(writer, image, nil)
        try #require(CGImageDestinationFinalize(writer))
        return buffer as Data
    }
}
