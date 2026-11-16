import AppKit
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ClipboardFormatCodec {
    private typealias Representation = ClipboardPayload.Representation
    private typealias PasteboardType = NSPasteboard.PasteboardType

    private static let alternateTextTypes: Set<String> = [
        UTType.utf16PlainText.identifier,
        UTType.utf16ExternalPlainText.identifier,
        UTType.plainText.identifier,
    ]

    private static let tabularTypes: Set<String> = [
        PasteboardType.tabularText.rawValue,
        UTType.tabSeparatedText.identifier,
        UTType.commaSeparatedText.identifier,
    ]

    private static let nativeSpreadsheetTypes: Set<String> = [
        "com.apple.iwork.tstnativedata",
        "com.microsoft.excel.biff",
        "com.microsoft.excel.biff8",
        "com.microsoft.excel.biff12",
        "com.microsoft.excel.xls",
        "org.openxmlformats.spreadsheetml.sheet",
    ]

    // These representations may accompany rich text, images, or cells in iWork.
    private static let iWorkTypes: Set<String> = [
        "com.apple.iwork.tspnativedata",
        "com.apple.iwork.tspnativemetadata",
        "com.apple.iwork.tspdescription",
    ]
    private static let iWorkStatePrefix = "com.apple.iwork.pasteboardstate."
    private static let numbersApplication = iWorkStatePrefix + "applicationname-numbers"
    private static let iWorkHasTables = iWorkStatePrefix + "hastables"

    private static let attachmentTypes: Set<String> = [
        PasteboardType.rtfd.rawValue, UTType.rtfd.identifier, PasteboardType.fileContents.rawValue,
    ]

    private static let richTextTypes: Set<String> = [
        PasteboardType.rtf.rawValue, PasteboardType.html.rawValue,
    ]

    static func supports(_ type: String) -> Bool {
        type == "public.url-name" || kind(for: type) != nil
            || iWorkTypes.contains(type.lowercased())
            || type.lowercased().hasPrefix(iWorkStatePrefix)
    }

    static func isTextType(_ type: String) -> Bool {
        type == PasteboardType.string.rawValue || alternateTextTypes.contains(type)
    }

    static func withTabularFallback(
        _ representations: [ClipboardPayload.Representation]
    ) -> [ClipboardPayload.Representation] {
        let appKitTSV = representations.first { $0.type == PasteboardType.tabularText.rawValue }
        let genericTSV = representations.first { $0.type == UTType.tabSeparatedText.identifier }
        let hasNativeTable = hasSpreadsheetRepresentation(representations)
        let plain = representations.first { $0.type == PasteboardType.string.rawValue }
        guard let tabular = appKitTSV ?? genericTSV ?? (hasNativeTable ? plain : nil),
            !tabular.data.isEmpty, String(data: tabular.data, encoding: .utf8) != nil
        else { return representations }

        return addingTabularFallback(to: representations, data: tabular.data)
    }

    static func replayRepresentations(_ representations: [ClipboardPayload.Representation])
        -> [ClipboardPayload.Representation]
    {
        guard
            let csv = representations.first(where: {
                $0.type == UTType.commaSeparatedText.identifier
            }),
            !representations.contains(where: { $0.type == PasteboardType.tabularText.rawValue })
        else { return representations }

        let genericTSV = representations.first { $0.type == UTType.tabSeparatedText.identifier }
        if let genericTSV, !genericTSV.data.isEmpty,
            String(data: genericTSV.data, encoding: .utf8) != nil
        {
            return addingTabularFallback(to: representations, data: genericTSV.data)
        }
        guard let tabular = ClipboardDelimitedText.tabSeparatedCSV(csv.data) else {
            return representations
        }
        return addingTabularFallback(to: representations, data: tabular)
    }

    private static func addingTabularFallback(to representations: [Representation], data: Data)
        -> [Representation]
    {
        var result = representations
        if !representations.contains(where: { $0.type == PasteboardType.tabularText.rawValue }) {
            result.append(Representation(type: PasteboardType.tabularText.rawValue, data: data))
        }
        if !representations.contains(where: { $0.type == PasteboardType.string.rawValue }) {
            result.append(Representation(type: PasteboardType.string.rawValue, data: data))
        }
        return result
    }

    static func presentation(for payload: ClipboardPayload)
        -> (
            kind: ClipboardPayload.Kind, summary: String, thumbnail: Data?,
            tablePreviewRows: [[String]]
        )
    {
        let kinds = Set(payload.items.map(kind(for:)))
        let kind = kinds.count == 1 ? kinds.first ?? .text : .mixed
        let preview = textPreview(for: payload, kind: kind)

        let thumbnail = payload.items.lazy.flatMap(\.representations).compactMap {
            let kind = Self.kind(for: $0.type)
            guard kind == .image || kind == .pdf else { return nil as Data? }
            return Self.thumbnail(from: $0.data)
        }.first

        return (kind, preview.summary, thumbnail, preview.tablePreviewRows)
    }

    static func textPreview(for payload: ClipboardPayload, kind: ClipboardPayload.Kind)
        -> (summary: String, tablePreviewRows: [[String]])
    {
        let summary = payload.items.lazy.compactMap { item in
            item.fileURL?.lastPathComponent ?? summary(for: item)
        }.prefix(4).joined(separator: "\n")
        let rows =
            kind == .spreadsheet
            ? Array(payload.items.lazy.flatMap { tablePreviewRows(for: $0) }.prefix(4)) : []
        return (summary.isEmpty ? defaultSummary(for: kind) : summary, rows)
    }

    private static func kind(for item: ClipboardPayload.Item) -> ClipboardPayload.Kind {
        let kinds = Set(item.representations.compactMap { kind(for: $0.type) })
        if item.fileURL != nil {
            return kinds.isEmpty || kinds == [.text] ? .files : .mixed
        }
        if hasSpreadsheetRepresentation(item.representations) { return .spreadsheet }
        for kind: ClipboardPayload.Kind in [
            .spreadsheet, .mixed, .link, .color, .image, .pdf, .richText,
        ] {
            if kinds.contains(kind) { return kind }
        }
        if let text = item.representations.first(where: {
            $0.type == PasteboardType.string.rawValue
        }),
            text.data.count <= 8_192, let value = String(data: text.data, encoding: .utf8),
            let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
            url.host?.isEmpty == false, !value.contains(where: { $0.isWhitespace })
        {
            return .link
        }
        return .text
    }

    private static func kind(for type: String) -> ClipboardPayload.Kind? {
        if isTextType(type) {
            return .text
        }
        if type == PasteboardType.URL.rawValue { return .link }
        if type == PasteboardType.color.rawValue { return .color }
        if type == PasteboardType.pdf.rawValue { return .pdf }
        if attachmentTypes.contains(type) { return .mixed }
        if richTextTypes.contains(type) { return .richText }
        if tabularTypes.contains(type) || isNativeSpreadsheetType(type) { return .spreadsheet }
        if let contentType = UTType(type), contentType.conforms(to: .image) { return .image }
        return nil
    }

    private static func isNativeSpreadsheetType(_ type: String) -> Bool {
        if nativeSpreadsheetTypes.contains(type.lowercased()) { return true }
        guard let contentType = UTType(type) else { return false }
        return contentType.conforms(to: .spreadsheet)
    }

    private static func hasSpreadsheetRepresentation(_ representations: [Representation]) -> Bool {
        if representations.contains(where: { isNativeSpreadsheetType($0.type) }) { return true }
        let types = Set(representations.map { $0.type.lowercased() })
        return types.contains(numbersApplication) && types.contains(iWorkHasTables)
            && types.contains("com.apple.iwork.tspnativedata")
    }

    private static func summary(for item: ClipboardPayload.Item) -> String? {
        if let bytes = item.representations.first(where: {
            $0.type == PasteboardType.color.rawValue
        })?.data, let hex = colorHex(from: bytes) {
            return hex
        }
        let candidates = [
            PasteboardType.URL.rawValue, PasteboardType.tabularText.rawValue,
            PasteboardType.string.rawValue, UTType.tabSeparatedText.identifier,
            UTType.commaSeparatedText.identifier, UTType.utf16PlainText.identifier,
            UTType.utf16ExternalPlainText.identifier, UTType.plainText.identifier,
        ]
        for type in candidates {
            guard let representation = item.representations.first(where: { $0.type == type }),
                let text = ClipboardTextDecoding.text(from: representation, byteLimit: 2_400),
                !text.isEmpty
            else { continue }
            return String(text.prefix(600))
        }
        return nil
    }

    private static func tablePreviewRows(for item: ClipboardPayload.Item) -> [[String]] {
        let byteLimit = 8_192
        var candidates: [(type: String, format: ClipboardDelimitedText.Format)] = [
            (PasteboardType.tabularText.rawValue, .tsv),
            (UTType.tabSeparatedText.identifier, .tsv),
            (UTType.commaSeparatedText.identifier, .csv),
        ]
        if hasSpreadsheetRepresentation(item.representations) {
            candidates.append((PasteboardType.string.rawValue, .tsv))
        }
        for (type, format) in candidates {
            guard let representation = item.representations.first(where: { $0.type == type }),
                let text = ClipboardTextDecoding.text(from: representation, byteLimit: byteLimit),
                let rows = ClipboardDelimitedText.previewRows(
                    in: text, format: format, isClipped: representation.data.count > byteLimit),
                !rows.isEmpty
            else { continue }
            return rows
        }
        return []
    }

    private static func colorHex(from data: Data) -> String? {
        guard
            let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data),
            let rgb = color.usingColorSpace(.sRGB)
        else { return nil }
        let components = [
            rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent,
        ]
        guard components.allSatisfy(\.isFinite) else { return nil }
        let bytes = components.map { Int((min(1, max(0, $0)) * 255).rounded()) }
        let hex = String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
        return bytes[3] == 255 ? hex : hex + String(format: "%02X", bytes[3])
    }

    private static func defaultSummary(for kind: ClipboardPayload.Kind) -> String {
        switch kind {
        case .text: "Texte"
        case .richText: "Texte enrichi"
        case .link: "Lien"
        case .image: "Image"
        case .files: "Fichiers"
        case .spreadsheet: "Cellules de tableur"
        case .pdf: "PDF"
        case .color: "Couleur"
        case .mixed: "Contenu mixte"
        }
    }

    private static func thumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 320,
                ] as CFDictionary)
        else { return nil }

        let result = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                result, UTType.png.identifier as CFString, 1, nil
            )
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? result as Data : nil
    }
}
