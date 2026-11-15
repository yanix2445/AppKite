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
        guard let tabular = tabSeparatedCSV(csv.data) else { return representations }
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

    private static func tabSeparatedCSV(_ data: Data) -> Data? {
        let hasUTF16BOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        guard var csv = String(data: data, encoding: hasUTF16BOM ? .utf16 : .utf8)
        else { return nil }

        // Scan UTF-8 bytes so delimiters are independent of Unicode grapheme boundaries.
        return csv.withUTF8 { bytes in
            let tab: UInt8 = 0x09
            let lineFeed: UInt8 = 0x0A
            let carriageReturn: UInt8 = 0x0D
            let quote: UInt8 = 0x22
            let comma: UInt8 = 0x2C
            var index = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
            guard index < bytes.count else { return nil }
            var output = Data()
            output.reserveCapacity(bytes.count)
            while index < bytes.count {
                let start = index
                var needsQuotes = false
                if bytes[index] == quote {
                    index += 1
                    while true {
                        guard index < bytes.count else { return nil }
                        let byte = bytes[index]
                        index += 1
                        if byte == quote {
                            if index == bytes.count || bytes[index] != quote { break }
                            index += 1
                            needsQuotes = true
                        } else if byte == tab || byte == lineFeed || byte == carriageReturn {
                            needsQuotes = true
                        }
                    }
                    // Keep quotes around cells that contain a quote, tab, or line break.
                    let field = needsQuotes ? start..<index : (start + 1)..<(index - 1)
                    output.append(contentsOf: bytes[field])
                } else {
                    while index < bytes.count {
                        let byte = bytes[index]
                        if byte == comma || byte == lineFeed || byte == carriageReturn { break }
                        guard byte != quote else { return nil }
                        needsQuotes = needsQuotes || byte == tab
                        index += 1
                    }
                    if needsQuotes { output.append(quote) }
                    output.append(contentsOf: bytes[start..<index])
                    if needsQuotes { output.append(quote) }
                }
                guard index < bytes.count else { break }

                let delimiter = bytes[index]
                index += 1
                switch delimiter {
                case comma:
                    output.append(tab)
                case lineFeed, carriageReturn:
                    if delimiter == carriageReturn, index < bytes.count, bytes[index] == lineFeed {
                        index += 1
                    }
                    if index < bytes.count { output.append(lineFeed) }
                default:
                    return nil
                }
            }
            // Encode a final empty cell explicitly so it is not read as a record terminator.
            if output.isEmpty || output.last == lineFeed {
                output.append(quote)
                output.append(quote)
            }
            return output
        }
    }

    static func presentation(for payload: ClipboardPayload)
        -> (kind: ClipboardPayload.Kind, summary: String, thumbnail: Data?)
    {
        let kinds = Set(payload.items.map(kind(for:)))
        let kind = kinds.count == 1 ? kinds.first ?? .text : .mixed
        let summary = payload.items.lazy.compactMap { item in
            item.fileURL?.lastPathComponent ?? summary(for: item)
        }.prefix(4).joined(separator: "\n")

        let thumbnail = payload.items.lazy.flatMap(\.representations).compactMap {
            let kind = Self.kind(for: $0.type)
            guard kind == .image || kind == .pdf else { return nil as Data? }
            return Self.thumbnail(from: $0.data)
        }.first

        return (kind, summary.isEmpty ? defaultSummary(for: kind) : summary, thumbnail)
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
            UTType.commaSeparatedText.identifier,
        ]
        for type in candidates {
            guard let representation = item.representations.first(where: { $0.type == type }) else {
                continue
            }
            // Avoid decoding an entire large text representation for a card's short preview.
            let prefix = representation.data.prefix(2_400)
            let text = String(decoding: prefix, as: UTF8.self)
            if !text.isEmpty { return String(text.prefix(600)) }
        }
        return nil
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
