import CoreGraphics
import CoreText
import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

nonisolated enum ClipboardPreviewRenderer {
    typealias MediaRenderer = @Sendable (URL, String?, String?, Int64?) async -> ClipboardPreview?

    private static let cardPixels = 512
    private static let tilePixels = 112
    private static let tileCount = 4
    private static let textBytes = 8_192
    private static let nativeTabularText = "public.utf8-tab-separated-values-text"
    private static let fileKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey, .isDirectoryKey, .isPackageKey,
        .contentTypeKey, .fileSizeKey,
    ]
    private static let officeExtensions: Set<String> = [
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "rtf", "rtfd",
    ]

    static func render(
        _ source: ClipboardPreviewSource, media: MediaRenderer? = nil
    ) async -> ClipboardPreview? {
        guard let first = source.items.first, !Task.isCancelled else { return nil }
        if source.items.count == 1 {
            return await renderItem(first, pixels: cardPixels, media: media)
        }
        guard
            source.items.contains(where: { item in
                item.fileURL != nil
                    || item.representations.contains {
                        guard let type = UTType($0.type) else { return false }
                        return isMedia(type) || isVisual(type)
                    }
            })
        else { return nil }

        var tiles: [ClipboardPreview.Tile] = []
        for item in source.items.prefix(tileCount) {
            guard !Task.isCancelled else { return nil }
            let preview = await renderItem(
                item, pixels: tilePixels, allowFolder: false, media: media)
            let name =
                item.fileURL?.lastPathComponent ?? preview?.name ?? preview?.format ?? "Élément"
            tiles.append(.init(name: name, picture: tilePicture(preview)))
        }
        return .init(kind: .selection, content: .mosaic(tiles: tiles, count: source.items.count))
    }

    private static func renderItem(
        _ item: ClipboardPreviewSource.Item, pixels: Int, allowFolder: Bool = true,
        media: MediaRenderer?
    ) async -> ClipboardPreview? {
        var unavailable: ClipboardPreview?
        if let file = item.fileURL {
            let preview = await renderFile(
                file, pixels: pixels, allowFolder: allowFolder, media: media)
            if let preview, preview.content != .unavailable || preview.media != nil {
                return preview
            }
            unavailable = preview
        }

        let name = item.fileURL?.lastPathComponent
        for representation in item.representations {
            guard !Task.isCancelled else { return nil }
            guard representation.url.isFileURL,
                let type = UTType(representation.type), isMedia(type),
                let values = try? representation.url.resourceValues(forKeys: fileKeys),
                isRegular(values)
            else { continue }
            let size = values.fileSize.map(Int64.init)
            let preview =
                await media?(representation.url, type.identifier, name, size)
                ?? missing(mediaKind(type), type: type, name: name, size: size)
            guard preview.content == .unavailable else { return preview }
            if unavailable == nil || (unavailable?.media == nil && preview.media != nil) {
                unavailable = preview
            }
        }
        for representation in orderedVisualRepresentations(item.representations) {
            guard !Task.isCancelled else { return nil }
            guard representation.url.isFileURL,
                let type = UTType(representation.type), isVisual(type),
                let values = try? representation.url.resourceValues(forKeys: fileKeys),
                isRegular(values)
            else { continue }
            let size = values.fileSize.map(Int64.init)
            if let format = tableFormat(type) {
                if let table = tablePreview(
                    at: representation.url, type: type, format: format, name: name, size: size)
                {
                    return table
                }
                unavailable = unavailable ?? missing(.table, type: type, name: name, size: size)
            } else if type.conforms(to: .pdf) {
                if let picture = pdfPicture(representation.url, pixels: pixels) {
                    return .init(
                        kind: .document, content: .picture(picture), name: name, format: "PDF",
                        byteCount: size)
                }
                unavailable = unavailable ?? missing(.document, type: type, name: name, size: size)
            } else if type.conforms(to: .image) {
                if let preview = imagePreview(
                    at: representation.url, pixels: pixels, name: name, size: size)
                {
                    return preview
                }
                unavailable = unavailable ?? missing(.image, type: type, name: name, size: size)
            }
        }
        return unavailable
    }

    private static func orderedVisualRepresentations(
        _ representations: [ClipboardPreviewSource.Item.Representation]
    ) -> [ClipboardPreviewSource.Item.Representation] {
        let order = [
            nativeTabularText,
            UTType.tabSeparatedText.identifier,
            UTType.commaSeparatedText.identifier,
            UTType.pdf.identifier,
            UTType.gif.identifier,
        ]
        let known = order.flatMap { id in representations.filter { $0.type == id } }
        let others = representations.filter { !order.contains($0.type) }
        return known + others
    }

    private static func renderFile(
        _ url: URL, pixels: Int, allowFolder: Bool, media: MediaRenderer?
    ) async -> ClipboardPreview? {
        guard url.isFileURL, !Task.isCancelled else { return nil }
        let name = url.lastPathComponent
        let suffix = url.pathExtension.lowercased()
        guard let values = try? url.resourceValues(forKeys: fileKeys) else {
            return missing(.document, name: name, suffix: suffix)
        }
        // A copied link and its target have independent lifetimes. Preview only the former.
        guard values.isSymbolicLink != true, values.isAliasFile != true else {
            return missing(.document, name: name, suffix: suffix)
        }
        if values.isDirectory == true, values.isPackage != true {
            guard allowFolder else { return missing(.folder, name: name) }
            return await folderPreview(url, media: media)
        }

        let type = values.contentType ?? UTType(filenameExtension: suffix)
        let size = values.fileSize.map(Int64.init)
        if values.isPackage == true {
            guard officeExtensions.contains(suffix) else {
                return missing(.document, type: type, name: name, suffix: suffix, size: size)
            }
            return await documentPreview(url, pixels: pixels, type: type, size: size)
        }
        guard isRegular(values) else {
            return missing(.document, type: type, name: name, suffix: suffix, size: size)
        }

        if let tableType = UTType(filenameExtension: suffix), let format = tableFormat(tableType) {
            return tablePreview(at: url, type: tableType, format: format, name: name, size: size)
                ?? missing(.table, type: tableType, name: name, suffix: suffix, size: size)
        }
        if type?.conforms(to: .pdf) == true || suffix == "pdf" {
            return await documentPreview(url, pixels: pixels, type: .pdf, size: size)
        }
        if let type, isMedia(type) {
            return await media?(url, nil, name, size)
                ?? missing(mediaKind(type), type: type, name: name, suffix: suffix, size: size)
        }
        if let image = imagePreview(at: url, pixels: pixels, name: name, size: size) {
            return image
        }
        if type?.conforms(to: .image) == true {
            return missing(.image, type: type, name: name, suffix: suffix, size: size)
        }
        if officeExtensions.contains(suffix)
            || type?.conforms(to: .plainText) == true
            || type?.conforms(to: .compositeContent) == true
        {
            return await documentPreview(url, pixels: pixels, type: type, size: size)
        }
        return missing(.document, type: type, name: name, suffix: suffix, size: size)
    }

    private static func isRegular(_ values: URLResourceValues) -> Bool {
        values.isRegularFile == true && values.isSymbolicLink != true && values.isAliasFile != true
    }

    private static func isMedia(_ type: UTType) -> Bool {
        type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .video)
    }

    private static func isVisual(_ type: UTType) -> Bool {
        tableFormat(type) != nil || type.conforms(to: .image) || type.conforms(to: .pdf)
    }

    private static func mediaKind(_ type: UTType) -> ClipboardPreview.Kind {
        type.conforms(to: .audio) ? .audio : .video
    }

    private static func missing(
        _ kind: ClipboardPreview.Kind, type: UTType? = nil, name: String? = nil,
        suffix: String? = nil, size: Int64? = nil
    ) -> ClipboardPreview {
        .init(
            kind: kind, content: .unavailable, name: name,
            format: formatName(suffix: suffix, type: type), byteCount: size)
    }

    private static func formatName(suffix: String? = nil, type: UTType?) -> String? {
        guard
            let value = suffix.flatMap({ $0.isEmpty ? nil : $0 })
                ?? type?.preferredFilenameExtension
        else { return nil }
        return value.uppercased()
    }

    private static func imagePreview(
        at url: URL, pixels: Int, name: String?, size: Int64?
    ) -> ClipboardPreview? {
        guard !Task.isCancelled,
            let source = CGImageSourceCreateWithURL(
                url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let identifier = CGImageSourceGetType(source) as? String,
            let type = UTType(identifier), type.conforms(to: .image),
            CGImageSourceGetCount(source) > 0
        else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, index,
                [
                    kCGImageSourceShouldCache: false,
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels,
                ] as CFDictionary)
        else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
        let width = properties?[kCGImagePropertyPixelWidth as String] as? Int
        let height = properties?[kCGImagePropertyPixelHeight as String] as? Int
        let orientation = properties?[kCGImagePropertyOrientation as String] as? Int ?? 1
        let swapsAxes = (5...8).contains(orientation)
        guard let png = pngData(image) else { return nil }
        let transparency: Bool
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            transparency = true
        default:
            transparency = false
        }
        let picture = ClipboardPreview.Picture(
            png: png, pixelWidth: swapsAxes ? height : width,
            pixelHeight: swapsAxes ? width : height, hasTransparency: transparency)
        let media: ClipboardPreview.Media? =
            type == .gif && CGImageSourceGetCount(source) > 1 ? .init(kind: .gif, url: url) : nil
        return .init(
            kind: .image, content: .picture(picture), name: name,
            format: formatName(type: type), byteCount: size, media: media)
    }

    private static func pngData(_ image: CGImage) -> Data? {
        guard !Task.isCancelled else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private static func pdfPicture(_ url: URL, pixels: Int) -> ClipboardPreview.Picture? {
        guard !Task.isCancelled,
            let document = CGPDFDocument(url as CFURL), document.isUnlocked,
            let page = document.page(at: 1)
        else { return nil }
        let trim = page.getBoxRect(.cropBox)
        let rotated = !page.rotationAngle.isMultiple(of: 180)
        let width = rotated ? trim.height : trim.width
        let height = rotated ? trim.width : trim.height
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }

        // Divide before scaling to avoid overflowing on pathologically large page dimensions.
        let maxSide = max(width, height)
        let pixelWidth = max(1, Int((width / maxSide * CGFloat(pixels)).rounded()))
        let pixelHeight = max(1, Int((height / maxSide * CGFloat(pixels)).rounded()))
        guard
            let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(bounds)
        context.concatenate(
            page.getDrawingTransform(.cropBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage(), let png = pngData(image) else { return nil }
        return .init(png: png)
    }

    private static func documentPreview(
        _ url: URL, pixels: Int, type: UTType?, size: Int64?
    ) async -> ClipboardPreview {
        let name = url.lastPathComponent
        let suffix = url.pathExtension
        let picture: ClipboardPreview.Picture?
        if type == .pdf {
            picture = pdfPicture(url, pixels: pixels)
        } else {
            picture = await quickLookPicture(url, pixels: pixels)
        }
        return .init(
            kind: .document, content: picture.map(ClipboardPreview.Content.picture) ?? .unavailable,
            name: name, format: formatName(suffix: suffix, type: type), byteCount: size)
    }

    // A request is configured once. Quick Look allows canceling it while generation is pending.
    private struct QuickLookJob: @unchecked Sendable {
        let generator: QLThumbnailGenerator
        let request: QLThumbnailGenerator.Request
    }

    private static func quickLookPicture(_ url: URL, pixels: Int) async -> ClipboardPreview.Picture?
    {
        guard !Task.isCancelled else { return nil }
        let job = QuickLookJob(
            generator: .shared,
            request: .init(
                fileAt: url, size: CGSize(width: pixels, height: pixels), scale: 1,
                representationTypes: .thumbnail))
        return await withTaskCancellationHandler(
            operation: { @Sendable in
                guard !Task.isCancelled,
                    let result = try? await job.generator.generateBestRepresentation(
                        for: job.request),
                    !Task.isCancelled, result.type == .thumbnail,
                    let png = pngData(result.cgImage)
                else { return nil }
                return .init(png: png)
            },
            onCancel: { @Sendable in job.generator.cancel(job.request) }
        )
    }

    private static func tableFormat(_ type: UTType) -> ClipboardDelimitedText.Format? {
        if type == .commaSeparatedText { return .csv }
        if type == .tabSeparatedText || type.identifier == nativeTabularText {
            return .tsv
        }
        return nil
    }

    private static func tablePreview(
        at url: URL, type: UTType, format: ClipboardDelimitedText.Format,
        name: String? = nil, size: Int64?
    ) -> ClipboardPreview? {
        guard !Task.isCancelled, let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: textBytes + 1),
            let text = ClipboardTextDecoding.text(
                from: .init(type: type.identifier, data: data), byteLimit: textBytes),
            let rows = ClipboardDelimitedText.previewRows(
                in: text, format: format, isClipped: data.count > textBytes),
            !rows.isEmpty
        else { return nil }
        return .init(
            kind: .table, content: .table(rows), name: name,
            format: format == .csv ? "CSV" : "TSV", byteCount: size)
    }

    private static func folderPreview(_ folder: URL, media: MediaRenderer?) async
        -> ClipboardPreview?
    {
        let name = folder.lastPathComponent
        guard let (selected, count) = folderChildren(folder) else {
            return Task.isCancelled ? nil : missing(.folder, name: name)
        }

        var tiles: [ClipboardPreview.Tile] = []
        for child in selected {
            guard !Task.isCancelled else { return nil }
            let preview = await renderFile(
                child, pixels: tilePixels, allowFolder: false, media: media)
            tiles.append(.init(name: child.lastPathComponent, picture: tilePicture(preview)))
        }
        return .init(kind: .folder, content: .mosaic(tiles: tiles, count: count), name: name)
    }

    private static func folderChildren(_ folder: URL) -> (selected: [URL], count: Int)? {
        var didFail = false
        guard
            let children = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants],
                errorHandler: { _, _ in
                    didFail = true
                    return false
                })
        else { return nil }

        var selected: [URL] = []
        var count = 0
        for item in children {
            guard !Task.isCancelled, let child = item as? URL else { return nil }
            count += 1
            let insertion =
                selected.firstIndex {
                    child.lastPathComponent.localizedStandardCompare($0.lastPathComponent)
                        == .orderedAscending
                } ?? selected.count
            if insertion < tileCount {
                selected.insert(child, at: insertion)
                if selected.count > tileCount { selected.removeLast() }
            }
        }
        return didFail ? nil : (selected, count)
    }

    private static func tilePicture(_ preview: ClipboardPreview?) -> ClipboardPreview.Picture? {
        switch preview?.content {
        case .picture(let picture):
            return compactPicture(picture)
        case .table(let rows):
            return tablePicture(rows)
        case .waveform(let samples):
            return waveformPicture(samples)
        default:
            return nil
        }
    }

    private static func compactPicture(_ picture: ClipboardPreview.Picture) -> ClipboardPreview
        .Picture?
    {
        guard
            let source = CGImageSourceCreateWithData(
                picture.png as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let width = properties?[kCGImagePropertyPixelWidth as String] as? Int
        let height = properties?[kCGImagePropertyPixelHeight as String] as? Int
        if let width, let height, max(width, height) <= tilePixels {
            return picture
        }
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: tilePixels,
                ] as CFDictionary),
            let png = pngData(image)
        else { return nil }
        return .init(png: png, hasTransparency: picture.hasTransparency)
    }

    private static func tablePicture(_ rows: [[String]]) -> ClipboardPreview.Picture? {
        guard !rows.isEmpty, let context = tileContext() else { return nil }
        let gutter = CGFloat(6)
        let rowHeight = CGFloat(22)
        let columnWidth = (CGFloat(tilePixels) - gutter * 2) / 3
        let ink = CGColor(gray: 0.15, alpha: 1)
        for (rowIndex, row) in rows.prefix(4).enumerated() {
            let bottom = CGFloat(tilePixels) - gutter - CGFloat(rowIndex + 1) * rowHeight
            context.setFillColor(gray: rowIndex == 0 ? 0.88 : 0.96, alpha: 1)
            context.fill(
                CGRect(
                    x: gutter, y: bottom, width: CGFloat(tilePixels) - gutter * 2,
                    height: rowHeight - 1))
            for (columnIndex, cell) in row.prefix(3).enumerated() {
                let x = gutter + CGFloat(columnIndex) * columnWidth
                context.saveGState()
                context.clip(to: CGRect(x: x, y: bottom, width: columnWidth, height: rowHeight))
                let title = String(cell.prefix(120))
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(
                        string: title,
                        attributes: [
                            .init(kCTFontAttributeName as String): CTFontCreateUIFontForLanguage(
                                .system, 9, nil) as Any,
                            .init(kCTForegroundColorAttributeName as String): ink,
                        ]))
                context.textPosition = CGPoint(x: x + 3, y: bottom + 7)
                CTLineDraw(line, context)
                context.restoreGState()
            }
        }
        guard let image = context.makeImage(), let png = pngData(image) else { return nil }
        return .init(png: png)
    }

    private static func waveformPicture(_ samples: [Float]) -> ClipboardPreview.Picture? {
        guard !samples.isEmpty, let context = tileContext() else { return nil }
        let bars = min(samples.count, 30)
        let span = CGFloat(tilePixels - 16) / CGFloat(bars)
        context.setFillColor(red: 0.12, green: 0.43, blue: 0.68, alpha: 1)
        for bar in 0..<bars {
            let sample = samples[bar * samples.count / bars]
            let amplitude = sample.isFinite ? CGFloat(min(1, max(0, sample))) : 0
            let height = max(2, amplitude * 78)
            context.fill(
                CGRect(
                    x: 8 + CGFloat(bar) * span, y: (CGFloat(tilePixels) - height) / 2,
                    width: max(1, span * 0.62), height: height))
        }
        guard let image = context.makeImage(), let png = pngData(image) else { return nil }
        return .init(png: png)
    }

    private static func tileContext() -> CGContext? {
        guard !Task.isCancelled,
            let context = CGContext(
                data: nil, width: tilePixels, height: tilePixels, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: tilePixels, height: tilePixels))
        return context
    }
}
