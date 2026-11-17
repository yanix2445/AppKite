import AVFoundation
import AppKit
import QuartzCore
import SwiftUI

struct ClipboardArchivedPreviewView: View {
    let preview: ClipboardPreview
    var playback: ClipboardPreviewPlayback? = nil

    var body: some View {
        if preview.media?.kind == .video, let player = playback?.player {
            ClipboardVideoView(player: player)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if let frame = playback?.frame {
            Image(decorative: frame, scale: 1)
                .resizable()
                .scaledToFit()
                .background {
                    if case .picture(let picture) = preview.content, picture.hasTransparency {
                        ClipboardPreviewCheckerboard()
                    }
                }
                .accessibilityHidden(true)
        } else {
            stillPreview
        }
    }

    @ViewBuilder
    private var stillPreview: some View {
        switch preview.content {
        case .picture(let picture):
            if preview.kind == .image {
                ClipboardPreviewPictureView(picture: picture)
            } else {
                ClipboardPreviewPictureView(picture: picture)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.primary.opacity(0.045), in: .rect(cornerRadius: 8))
                    .padding(7)
            }
        case .table(let rows):
            ClipboardTablePreviewView(rows: rows)
        case .waveform(let amplitudes):
            ClipboardWaveformView(
                amplitudes: amplitudes, progress: playback?.progress ?? 0
            )
            .padding(10)
        case .mosaic(let tiles, let count):
            if count == 0 {
                Label("Dossier vide", systemImage: "folder")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        ForEach(tiles.prefix(2).indices, id: \.self) { index in
                            ClipboardPreviewTileView(tile: tiles[index])
                        }
                    }
                    if tiles.count > 2 {
                        GridRow {
                            ForEach(tiles.dropFirst(2).indices, id: \.self) { index in
                                ClipboardPreviewTileView(tile: tiles[index])
                            }
                        }
                    }
                }
                .padding(7)
            }
        case .unavailable:
            Label("Aperçu indisponible", systemImage: "doc")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(8)
        }
    }
}

private struct ClipboardPreviewPictureView: View {
    let picture: ClipboardPreview.Picture

    var body: some View {
        if let image = NSImage(data: picture.png) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .background {
                    if picture.hasTransparency { ClipboardPreviewCheckerboard() }
                }
                .accessibilityHidden(true)
        }
    }
}

private struct ClipboardPreviewCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let side = 7.0
            let rows = Int((size.height / side).rounded(.up))
            let columns = Int((size.width / side).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns {
                    let rect = CGRect(
                        x: Double(column) * side, y: Double(row) * side,
                        width: side, height: side
                    )
                    let shade = (row + column).isMultiple(of: 2) ? 0.30 : 0.41
                    context.fill(Path(rect), with: .color(Color(white: shade)))
                }
            }
        }
    }
}

private struct ClipboardPreviewTileView: View {
    let tile: ClipboardPreview.Tile

    var body: some View {
        VStack(spacing: 3) {
            if let picture = tile.picture {
                ClipboardPreviewPictureView(picture: picture)
            } else {
                Image(systemName: "doc")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(verbatim: tile.name)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(4)
        .background(.primary.opacity(0.075), in: .rect(cornerRadius: 5))
    }
}

private struct ClipboardWaveformView: View {
    let amplitudes: [Float]
    let progress: Double

    var body: some View {
        Canvas { context, size in
            guard !amplitudes.isEmpty else { return }
            let step = size.width / Double(amplitudes.count)
            let barWidth = max(1, step * 0.58)
            for (index, amplitude) in amplitudes.enumerated() {
                let height = max(2, Double(amplitude) * size.height)
                let rect = CGRect(
                    x: Double(index) * step + (step - barWidth) / 2,
                    y: (size.height - height) / 2,
                    width: barWidth, height: height
                )
                let played = Double(index) < progress * Double(amplitudes.count)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(played ? .accentColor : .secondary.opacity(0.40))
                )
            }
        }
        .accessibilityHidden(true)
    }
}

struct ClipboardPlaybackButton: View {
    let playback: ClipboardPreviewPlayback
    let media: ClipboardPreview.Media
    let entryID: UUID
    let action: () -> Void

    private var isPlaying: Bool { playback.activeID == entryID && playback.isPlaying }
    private var failed: Bool { playback.failedID == entryID }

    var body: some View {
        Button(action: action) {
            Label(
                isPlaying ? "Mettre en pause" : "Lire",
                systemImage: isPlaying ? "pause.fill" : "play.fill"
            )
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(.black.opacity(0.68), in: .circle)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("clipboard-media-playback")
        .accessibilityValue(isPlaying ? "En cours de lecture" : "Arrêté")
        .help(failed ? "Lecture indisponible" : isPlaying ? "Mettre en pause" : "Lire")
        .overlay(alignment: .bottom) {
            if failed {
                Text("Lecture indisponible")
                    .font(.caption2)
                    .fixedSize()
                    .padding(4)
                    .background(.regularMaterial, in: .rect(cornerRadius: 4))
                    .offset(y: 22)
                    .allowsHitTesting(false)
            }
        }
        .offset(y: media.kind == .audio ? 32 : 0)
    }
}

private struct ClipboardVideoView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> Surface {
        let view = Surface()
        view.wantsLayer = true
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: Surface, context: Context) {
        view.playerLayer.player = player
    }

    static func dismantleNSView(_ view: Surface, coordinator: ()) {
        view.playerLayer.player = nil
    }

    final class Surface: NSView {
        let playerLayer = AVPlayerLayer()

        override func makeBackingLayer() -> CALayer { playerLayer }
    }
}
