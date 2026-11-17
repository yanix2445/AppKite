import AppKit
import SwiftUI

struct ClipboardHistoryCardView: View {
    let entry: ClipboardEntry
    let thumbnail: Data?
    let height: CGFloat
    let isSelected: Bool
    var archivedPreview: ClipboardPreview? = nil
    var isLoadingPreview = false
    var playback: ClipboardPreviewPlayback? = nil
    @Environment(\.colorScheme) private var colorScheme

    static let width: CGFloat = 196
    private let shape = RoundedRectangle(cornerRadius: 14)
    private let headerHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            header
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            footer
        }
        .frame(width: Self.width, height: height)
        .background(
            colorScheme == .dark ? .white.opacity(0.09) : .white.opacity(0.52),
            in: shape
        )
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                lineWidth: isSelected ? 2.5 : 1
            )
            .allowsHitTesting(false)
        }
        .contentShape(shape)
    }

    private var header: some View {
        let source =
            entry.isRemote
            ? nil
            : ClipboardSourceAppearance.resolve(
                for: entry.sourceBundleIdentifier ?? entry.probableSourceBundleIdentifier)
        let isProbable = entry.sourceBundleIdentifier == nil && source != nil
        let ink = source?.headerInk ?? entry.kind.cardHeaderInk
        return HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 0) {
                Text(headerTitle)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 3) {
                    if entry.isRemote {
                        Text("Presse-papiers universel")
                        Text("·").accessibilityHidden(true)
                    } else if let source {
                        if isProbable {
                            Text("\(source.name) ?")
                                .accessibilityLabel("Origine probable : \(source.name)")
                                .help("Origine probable : \(source.name)")
                        } else {
                            Text(verbatim: source.name)
                        }
                        Text("·").accessibilityHidden(true)
                    }
                    Text(
                        entry.lastUsedAt,
                        format: .relative(presentation: .named, unitsStyle: .abbreviated)
                    )
                    .layoutPriority(1)
                }
                .font(.system(size: 10))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let source {
                Image(nsImage: source.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: headerHeight * 0.95, height: headerHeight * 0.95)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: entry.isRemote ? "iphone.and.arrow.forward" : entry.kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .background(entry.kind.cardHeaderInk.opacity(0.16), in: .rect(cornerRadius: 5))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(ink)
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .frame(height: headerHeight)
        .background(source?.headerColor ?? entry.kind.cardHeaderColor, in: .rect)
    }

    private var headerTitle: LocalizedStringKey {
        switch archivedPreview?.kind {
        case .image: entry.kind == .image ? "Image copiée" : "Image"
        case .document: entry.kind == .pdf ? "PDF" : "Document"
        case .table: "Tableur"
        case .folder: "Dossier"
        case .selection: entry.kind == .files ? "Fichier" : "Sélection"
        case .audio: "Audio"
        case .video: "Vidéo"
        case nil: entry.kind.cardHeaderTitle
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let archivedPreview {
            let active = playback?.activeID == entry.id ? playback : nil
            ClipboardArchivedPreviewView(preview: archivedPreview, playback: active)
                .accessibilityIdentifier("clipboard-archive-preview")
        } else if isLoadingPreview && thumbnail == nil && entry.tablePreviewRows.isEmpty {
            ProgressView("Chargement de l’aperçu")
                .controlSize(.small)
                .labelStyle(.iconOnly)
        } else if entry.kind == .pdf, let thumbnail, let image = NSImage(data: thumbnail) {
            VStack(spacing: 5) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.primary.opacity(0.06), in: .rect(cornerRadius: 7))
                    .accessibilityHidden(true)
                if entry.text != "PDF" {
                    Text(verbatim: entry.text)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .padding(9)
        } else if let thumbnail, let image = NSImage(data: thumbnail) {
            GeometryReader { proxy in
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .padding(entry.kind == .image ? 0 : 9)
            .accessibilityLabel(Text(verbatim: entry.text))
        } else if entry.kind == .color, let color = swatch {
            ZStack {
                color
                Text(verbatim: entry.text)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(.black)
                    .background(.white.opacity(0.9), in: .rect(cornerRadius: 7))
            }
        } else if entry.kind == .files || entry.kind == .pdf || entry.kind == .image {
            VStack(spacing: 6) {
                Image(systemName: entry.kind.symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(verbatim: String(entry.text.prefix(400)))
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(8)
        } else if entry.kind == .spreadsheet, !entry.tablePreviewRows.isEmpty {
            ClipboardTablePreviewView(rows: entry.tablePreviewRows)
        } else if entry.kind == .link, let url = URL(string: entry.text), let host = url.host {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: host).font(.callout.weight(.semibold))
                Text(verbatim: url.path.isEmpty ? entry.text : url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
        } else {
            Text(verbatim: String(entry.text.prefix(600)))
                .font(.system(size: 13, weight: entry.kind == .richText ? .medium : .regular))
                .lineSpacing(2)
                .lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let archivedPreview {
            archivedFooter(archivedPreview)
        } else {
            summaryFooter
        }
    }

    private func archivedFooter(_ preview: ClipboardPreview) -> some View {
        let details = previewDetails(preview)
        return HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 3) {
                if let name = preview.name, !name.isEmpty {
                    Text(verbatim: name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                        .help(name)
                }
                if !details.isEmpty {
                    Text(verbatim: details)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if !entry.collectionIDs.isEmpty {
                Image(systemName: "folder").accessibilityLabel("Dans une collection")
            }
            if entry.isPinned {
                Image(systemName: "pin.fill").accessibilityLabel("Épinglée")
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: preview.name == nil ? 23 : 40)
    }

    private func previewDetails(_ preview: ClipboardPreview) -> String {
        var parts = [preview.format].compactMap { $0 }
        if case .picture(let picture) = preview.content,
            let width = picture.pixelWidth, let height = picture.pixelHeight
        {
            parts.append("\(width.formatted()) × \(height.formatted()) px")
        }
        if case .mosaic(_, let count) = preview.content {
            parts.append(count == 1 ? "1 élément" : "\(count.formatted()) éléments")
        }
        if let bytes = preview.byteCount {
            parts.append(bytes.formatted(.byteCount(style: .file)))
        }
        if let duration = preview.media?.duration, duration.isFinite, duration >= 0,
            duration <= Double(Int32.max)
        {
            parts.append(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
        }
        return parts.joined(separator: " · ")
    }

    private var summaryFooter: some View {
        HStack(spacing: 7) {
            switch entry.kind {
            case .text, .richText:
                let lines = entry.text.split(
                    omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                Text(lines.count == 1 ? "1 ligne" : "\(lines.count) lignes")
            case .link:
                Text(URL(string: entry.text)?.scheme?.uppercased() ?? "Lien")
            case .color:
                Text(swatch == nil ? "Couleur" : "sRGB")
            case .spreadsheet:
                let count = entry.text.split(whereSeparator: \.isNewline).count
                Text(count == 1 ? "1 ligne" : "\(count) lignes")
            case .image, .pdf:
                Text(verbatim: entry.text)
            case .files, .mixed:
                if !entry.collectionIDs.isEmpty {
                    Text("Dans une collection")
                }
            }
            Spacer(minLength: 0)
            if !entry.collectionIDs.isEmpty {
                Image(systemName: "folder").accessibilityLabel("Dans une collection")
            }
            if entry.isPinned {
                Image(systemName: "pin.fill").accessibilityLabel("Épinglée")
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 23)
    }

    private var swatch: Color? {
        let hex = entry.text.dropFirst()
        guard entry.text.hasPrefix("#"), hex.count == 6 || hex.count == 8,
            let value = UInt64(hex, radix: 16)
        else { return nil }
        let rgba = hex.count == 6 ? value << 8 | 255 : value
        return Color(
            .sRGB, red: Double((rgba >> 24) & 255) / 255,
            green: Double((rgba >> 16) & 255) / 255, blue: Double((rgba >> 8) & 255) / 255,
            opacity: Double(rgba & 255) / 255
        )
    }
}

struct ClipboardTablePreviewView: View {
    let rows: [[String]]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 9, verticalSpacing: 5) {
            ForEach(rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(rows[row].indices, id: \.self) { column in
                        Text(verbatim: rows[row][column])
                            .lineLimit(1)
                            .fontWeight(row == 0 ? .semibold : .regular)
                    }
                }
            }
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
    }
}

extension ClipboardPayload.Kind {
    fileprivate var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .link: "link"
        case .image: "photo"
        case .files: "folder"
        case .spreadsheet: "tablecells"
        case .pdf: "doc.richtext"
        case .color: "eyedropper"
        case .mixed: "paperclip"
        }
    }

    fileprivate var cardHeaderTitle: LocalizedStringKey {
        switch self {
        case .text: "Texte brut"
        case .image: "Image copiée"
        case .files: "Fichier"
        default: filterTitle
        }
    }

    fileprivate var cardHeaderColor: Color {
        switch self {
        case .text, .richText: Color(red: 0.07, green: 0.40, blue: 0.74)
        case .link: Color(red: 0.11, green: 0.40, blue: 0.48)
        case .image: Color(red: 0.23, green: 0.70, blue: 0.85)
        case .files, .pdf: Color(red: 0.05, green: 0.34, blue: 0.65)
        case .spreadsheet: Color(red: 0.09, green: 0.42, blue: 0.30)
        case .color: Color(red: 0.12, green: 0.12, blue: 0.14)
        case .mixed: Color(red: 0.96, green: 0.73, blue: 0.10)
        }
    }

    fileprivate var cardHeaderInk: Color {
        switch self {
        case .image, .mixed: .black
        default: .white
        }
    }
}
