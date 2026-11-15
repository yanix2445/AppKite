import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

nonisolated enum ClipboardTextExtractor {
    private typealias Representation = ClipboardPayload.Representation
    private typealias PasteboardType = NSPasteboard.PasteboardType

    static func immediateText(in payload: ClipboardPayload) -> String {
        var texts: [String] = []
        for item in payload.items {
            if let file = item.fileURL {
                texts.append(file.lastPathComponent)
                continue
            }
            let plain = item.representations.compactMap(text(from:))
            texts.append(contentsOf: plain)
            if !item.representations.contains(where: { ClipboardFormatCodec.isTextType($0.type) }),
                let richText = item.representations.lazy.compactMap(richText(from:)).first
            {
                texts.append(richText)
            }
        }
        return joined(texts)
    }

    static func requiresRecognition(_ payload: ClipboardPayload) -> Bool {
        payload.items.contains { item in
            item.fileURL == nil
                && item.representations.contains { representation in
                    isImage(representation) || isPDF(representation)
                }
        }
    }

    static func recognizedText(in payload: ClipboardPayload) throws -> String {
        try Task.checkCancellation()
        var texts: [String] = []
        for item in payload.items where item.fileURL == nil {
            try Task.checkCancellation()
            if let pdf = item.representations.lazy.filter(isPDF)
                .compactMap({ PDFDocument(data: $0.data) }).first
            {
                texts.append(contentsOf: try text(in: pdf))
            }
            if let images = item.representations.lazy.filter(isImage)
                .compactMap({ CGImageSourceCreateWithData($0.data as CFData, nil) }).first
            {
                texts.append(contentsOf: try text(in: images))
            }
        }
        return joined(texts)
    }

    private static func text(from representation: Representation) -> String? {
        switch representation.type {
        case UTType.utf16PlainText.identifier, UTType.utf16ExternalPlainText.identifier:
            String(data: representation.data, encoding: .utf16)
        case ClipboardPayload.utf8TextType, UTType.plainText.identifier,
            PasteboardType.URL.rawValue, "public.url-name", PasteboardType.tabularText.rawValue,
            UTType.tabSeparatedText.identifier, UTType.commaSeparatedText.identifier:
            String(data: representation.data, encoding: .utf8)
                ?? String(data: representation.data, encoding: .utf16)
        default:
            nil
        }
    }

    private static func richText(from representation: Representation) -> String? {
        let documentType: NSAttributedString.DocumentType
        switch representation.type {
        case PasteboardType.rtf.rawValue:
            documentType = .rtf
        case PasteboardType.rtfd.rawValue, UTType.rtfd.identifier:
            documentType = .rtfd
        case PasteboardType.html.rawValue:
            // Parse markup locally without fetching HTML resources or running WebKit.
            guard
                let document = try? XMLDocument(
                    data: representation.data,
                    options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]
                ),
                let nodes = try? document.nodes(
                    forXPath: "//body//text()[not(ancestor::script or ancestor::style)]"
                )
            else { return nil }
            return nodes.compactMap(\.stringValue).joined(separator: " ")
        default:
            return nil
        }
        return
            (try? NSAttributedString(
                data: representation.data, options: [.documentType: documentType],
                documentAttributes: nil
            ))?.string
    }

    private static func text(in source: CGImageSource) throws -> [String] {
        var texts: [String] = []
        for index in 0..<CGImageSourceGetCount(source) {
            try Task.checkCancellation()
            let lines = try autoreleasepool {
                guard
                    let image = CGImageSourceCreateThumbnailAtIndex(
                        source, index,
                        [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: 4_096,
                        ] as CFDictionary
                    )
                else { return [String]() }
                return try text(in: image)
            }
            texts.append(contentsOf: lines)
        }
        return texts
    }

    private static func text(in document: PDFDocument) throws -> [String] {
        var texts: [String] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            let lines = try autoreleasepool {
                guard let page = document.page(at: index) else { return [String]() }
                var content = page.string.map { [$0] } ?? []
                // A page can contain selectable text alongside a scanned region.
                if let reference = page.pageRef, let image = render(reference) {
                    content.append(contentsOf: try text(in: image))
                }
                return content
            }
            texts.append(contentsOf: lines)
        }
        return texts
    }

    private static func render(_ page: CGPDFPage) -> CGImage? {
        let crop = page.getBoxRect(.cropBox).standardized
        guard crop.minX.isFinite, crop.minY.isFinite,
            crop.width.isFinite, crop.height.isFinite, crop.width > 0, crop.height > 0
        else {
            return nil
        }
        let rotated = abs(page.rotationAngle % 180) == 90
        let width = rotated ? crop.height : crop.width
        let height = rotated ? crop.width : crop.height
        let scale = min(3, 3_072 / max(width, height))
        guard scale.isFinite, scale > 0 else { return nil }
        let pixelWidth = Int(max(1, (width * scale).rounded(.up)))
        let pixelHeight = Int(max(1, (height * scale).rounded(.up)))
        let bounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        guard
            let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(bounds)
        context.concatenate(
            page.getDrawingTransform(.cropBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return context.makeImage()
    }

    private static func text(in image: CGImage) throws -> [String] {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        try Task.checkCancellation()
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    private static func isImage(_ representation: Representation) -> Bool {
        UTType(representation.type)?.conforms(to: .image) == true
    }

    private static func isPDF(_ representation: Representation) -> Bool {
        UTType(representation.type)?.conforms(to: .pdf) == true
    }

    private static func joined(_ texts: [String]) -> String {
        var seen: Set<String> = []
        return texts.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: "\n")
    }
}
