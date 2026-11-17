import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ClipboardPreviewPlayback {
    private(set) var activeID: UUID?
    private(set) var isPlaying = false
    private(set) var progress = 0.0
    private(set) var player: AVPlayer?
    private(set) var frame: CGImage?
    private(set) var failedID: UUID?

    @ObservationIgnored private var media: ClipboardPreview.Media?
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var gifRunID: UUID?
    @ObservationIgnored private var gifIndex = 0
    @ObservationIgnored private var reachedEnd = false
    @ObservationIgnored private var seekID: UUID?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObserver: NSKeyValueObservation?
    @ObservationIgnored private var itemObservers: [any NSObjectProtocol] = []

    isolated deinit {
        stop()
    }

    func toggle(_ media: ClipboardPreview.Media, for id: UUID) {
        if activeID == id, self.media == media {
            if isPlaying {
                pause()
            } else {
                isPlaying = true
                resume()
            }
            return
        }

        stop()
        guard Self.isLocalFileURL(media.url) else {
            failedID = id
            return
        }

        let session = UUID()
        activeID = id
        sessionID = session
        self.media = media
        isPlaying = true

        switch media.kind {
        case .gif:
            playGIF(url: media.url, session: session)
        case .audio, .video:
            preparePlayer(for: media, session: session)
        }
    }

    func stop() {
        sessionID = nil
        seekID = nil
        gifRunID = nil
        work?.cancel()
        work = nil

        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        itemObservers.forEach(NotificationCenter.default.removeObserver)
        itemObservers.removeAll()

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        frame = nil
        activeID = nil
        failedID = nil
        isPlaying = false
        progress = 0
        reachedEnd = false
        gifIndex = 0
        media = nil
    }

    private func pause() {
        isPlaying = false
        seekID = nil
        if media?.kind == .gif {
            gifRunID = nil
            work?.cancel()
            work = nil
        }
        player?.pause()
    }

    private func resume() {
        guard let media, let sessionID else { return }
        if media.kind == .gif {
            playGIF(url: media.url, session: sessionID)
        } else {
            playFromCurrentPosition(session: sessionID)
        }
    }

    private func preparePlayer(for media: ClipboardPreview.Media, session: UUID) {
        work = Task { @MainActor [weak self] in
            let asset = await ClipboardMediaPreview.playbackAsset(for: media)
            guard let self, !Task.isCancelled, sessionID == session else { return }
            work = nil
            guard let asset else {
                fail(session: session)
                return
            }

            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .pause
            self.player = player
            observe(player, item: item, session: session)
            if isPlaying {
                player.play()
            }
        }
    }

    private func playFromCurrentPosition(session: UUID) {
        guard let player else { return }
        guard reachedEnd else {
            player.play()
            return
        }

        let seek = UUID()
        seekID = seek
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) {
            [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, sessionID == session, seekID == seek else { return }
                seekID = nil
                guard finished else {
                    fail(session: session)
                    return
                }
                reachedEnd = false
                progress = 0
                if isPlaying {
                    self.player?.play()
                }
            }
        }
    }

    private func observe(_ player: AVPlayer, item: AVPlayerItem, session: UUID) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10), queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, sessionID == session, !reachedEnd else { return }
                let duration = self.player?.currentItem?.duration.seconds
                let total =
                    duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
                    ?? media?.duration
                let position = time.seconds
                guard let total, total.isFinite, total > 0, position.isFinite else { return }
                progress = min(1, max(0, position / total))
            }
        }

        let center = NotificationCenter.default
        itemObservers = [
            center.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) {
                [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, sessionID == session else { return }
                    reachedEnd = true
                    progress = 1
                    isPlaying = false
                }
            },
            center.addObserver(
                forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
            ) {
                [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.fail(session: session)
                }
            },
        ]
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                self?.fail(session: session)
            }
        }
    }

    private func playGIF(url: URL, session: UUID) {
        let run = UUID()
        gifRunID = run
        let decoder = ClipboardGIFFrames(url: url)
        let first = gifIndex
        work = Task { @MainActor [weak self] in
            do {
                var index = first
                while !Task.isCancelled {
                    let sample = try await decoder.read(at: index)
                    guard self?.gifRunID == run, !Task.isCancelled else { return }
                    self?.frame = sample.image
                    self?.progress = Double(index) / Double(sample.count)
                    self?.gifIndex = index

                    try await Task.sleep(for: .seconds(sample.delay))
                    guard self?.gifRunID == run, !Task.isCancelled else { return }
                    index += 1
                    if index == sample.count {
                        self?.gifRunID = nil
                        self?.gifIndex = 0
                        self?.progress = 1
                        self?.isPlaying = false
                        self?.work = nil
                        return
                    }
                }
            } catch {
                guard !Task.isCancelled, self?.gifRunID == run else { return }
                self?.fail(session: session)
            }
        }
    }

    private func fail(session: UUID) {
        guard sessionID == session else { return }
        let failed = activeID
        stop()
        failedID = failed
    }

    private static func isLocalFileURL(_ url: URL) -> Bool {
        url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost")
    }
}

private actor ClipboardGIFFrames {
    struct Sample: Sendable {
        let image: CGImage
        let delay: Double
        let count: Int
    }

    private enum Failure: Error {
        case unreadable
    }

    private let url: URL
    private var source: CGImageSource?

    init(url: URL) {
        self.url = url
    }

    func read(at index: Int) throws -> Sample {
        try Task.checkCancellation()
        let source = try makeSource()
        let count = CGImageSourceGetCount(source)
        guard count > 1, (0..<count).contains(index) else { throw Failure.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceShouldCache: false,
        ]
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
        else { throw Failure.unreadable }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let animation = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay =
            (animation?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (animation?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        let safeDelay = delay.isFinite && delay > 0 ? min(655.35, max(0.02, delay)) : 0.1
        try Task.checkCancellation()
        return Sample(image: image, delay: safeDelay, count: count)
    }

    private func makeSource() throws -> CGImageSource {
        if let source { return source }
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
            values.isAliasFile != true,
            let source = CGImageSourceCreateWithURL(
                url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            CGImageSourceGetType(source) == UTType.gif.identifier as CFString
        else { throw Failure.unreadable }
        self.source = source
        return source
    }
}
