import AVFoundation
import AudioToolbox
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ClipboardMediaPreview {
    private static let maximumPicturePixels = 480
    private static let waveformBarCount = 48
    private static let waveformWindowCount = 8
    private static let maximumDecodedAudioSeconds = 24.0
    private static let playlistExtensions: Set<String> = [
        "asx", "cue", "m3u", "m3u8", "pls", "ram", "smil", "url", "webloc", "wax", "wvx", "xspf",
    ]

    static func supportsRepresentation(_ identifier: String) -> Bool {
        guard let type = UTType(identifier), let mimeType = type.preferredMIMEType,
            let fileExtension = type.preferredFilenameExtension,
            !playlistExtensions.contains(fileExtension)
        else { return false }
        return kind(of: type) != nil
            && (mimeType.hasPrefix("audio/") || mimeType.hasPrefix("video/"))
    }

    @concurrent
    static func render(
        _ url: URL, _ declaredType: String?, _ name: String?, _ byteCount: Int64?
    ) async -> ClipboardPreview? {
        let type =
            declaredType.flatMap { UTType($0) } ?? UTType(filenameExtension: url.pathExtension)
        guard let type, let declaredKind = kind(of: type) else { return nil }

        let mimeType = declaredType == nil ? nil : type.preferredMIMEType
        let fileExtension =
            declaredType == nil && !url.pathExtension.isEmpty
            ? url.pathExtension : type.preferredFilenameExtension
        let format = fileExtension?.uppercased()
        var unavailable = ClipboardPreview(
            kind: declaredKind, content: .unavailable, name: name, format: format,
            byteCount: byteCount)

        guard !Task.isCancelled,
            declaredType.map(supportsRepresentation) ?? true,
            let asset = localAsset(url: url, mimeType: mimeType)
        else { return Task.isCancelled ? nil : unavailable }
        let size =
            byteCount
            ?? (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map(Int64.init)
        unavailable.byteCount = size

        do {
            let (playable, protected, duration) = try await asset.load(
                .isPlayable, .hasProtectedContent, .duration)
            guard playable, !protected else { return unavailable }
            let seconds = duration.seconds
            let finiteDuration = seconds.isFinite && seconds > 0 ? seconds : nil

            if try await !asset.loadTracks(withMediaType: .video).isEmpty {
                let media = ClipboardPreview.Media(
                    kind: .video, url: url, duration: finiteDuration, mimeType: mimeType)
                let poster = try await posterImage(from: asset, seconds: finiteDuration)
                try Task.checkCancellation()
                return ClipboardPreview(
                    kind: .video, content: .picture(poster), name: name, format: format,
                    byteCount: size, media: media)
            }

            guard let track = try await asset.loadTracks(withMediaType: .audio).first
            else { return unavailable }

            let content: ClipboardPreview.Content
            if let artwork = try await artworkImage(from: asset) {
                content = .picture(artwork)
            } else if let finiteDuration,
                let samples = try await waveform(
                    for: asset, track: track, duration: finiteDuration)
            {
                content = .waveform(samples)
            } else {
                content = .unavailable
            }
            try Task.checkCancellation()

            let media = ClipboardPreview.Media(
                kind: .audio, url: url, duration: finiteDuration, mimeType: mimeType)
            return ClipboardPreview(
                kind: .audio, content: content, name: name, format: format,
                byteCount: size, media: media)
        } catch {
            return Task.isCancelled ? nil : unavailable
        }
    }

    @concurrent
    static func playbackAsset(for media: ClipboardPreview.Media) async -> AVURLAsset? {
        guard media.kind == .video || media.kind == .audio,
            !Task.isCancelled, let asset = localAsset(url: media.url, mimeType: media.mimeType),
            let (playable, protected) = try? await asset.load(.isPlayable, .hasProtectedContent),
            playable, !protected, !Task.isCancelled
        else { return nil }
        return asset
    }

    private static func kind(of type: UTType) -> ClipboardPreview.Kind? {
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return nil
    }

    private static func localAsset(url: URL, mimeType: String?) -> AVURLAsset? {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
            !playlistExtensions.contains(url.pathExtension.lowercased()),
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .isAliasFileKey,
            ]),
            values.isRegularFile == true, values.isSymbolicLink == false,
            values.isAliasFile == false,
            let type = mimeType.flatMap({ UTType(mimeType: $0) })
                ?? UTType(filenameExtension: url.pathExtension),
            kind(of: type) != nil, hasLocalMediaHeader(url)
        else { return nil }

        var options: [String: Any] = [
            AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue,
            AVURLAssetShouldSupportAliasDataReferencesKey: false,
        ]
        if let mimeType {
            options[AVURLAssetOverrideMIMETypeKey] = mimeType
        }
        return AVURLAsset(url: url, options: options)
    }

    private static func hasLocalMediaHeader(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: 4_096), !bytes.isEmpty else { return false }
        let leadingWhitespace = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "\u{feff}"))
        let prefix = String(decoding: bytes, as: UTF8.self)
            .trimmingCharacters(in: leadingWhitespace)
            .lowercased()
        return !prefix.hasPrefix("#extm3u")
            && !prefix.hasPrefix("[playlist]")
            && !prefix.hasPrefix("http:")
            && !prefix.hasPrefix("https:")
            && !prefix.hasPrefix("file:")
            && !prefix.hasPrefix("<")
    }

    private static func posterImage(from asset: AVURLAsset, seconds: Double?)
        async throws -> ClipboardPreview.Picture
    {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumPicturePixels, height: maximumPicturePixels)

        let time = CMTime(seconds: min((seconds ?? 0) * 0.15, 2), preferredTimescale: 600)
        let image: CGImage
        do {
            image = try await generator.image(at: time).image
        } catch {
            try Task.checkCancellation()
            guard time > .zero else { throw error }
            image = try await generator.image(at: .zero).image
        }
        guard let picture = picture(from: image) else { throw CocoaError(.fileReadCorruptFile) }
        return picture
    }

    private static func artworkImage(from asset: AVURLAsset) async throws -> ClipboardPreview
        .Picture?
    {
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        for item in AVMetadataItem.metadataItems(
            from: metadata, filteredByIdentifier: .commonIdentifierArtwork)
        {
            try Task.checkCancellation()
            guard let data = try? await item.load(.dataValue), data.count <= 16 * 1_024 * 1_024,
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                let image = CGImageSourceCreateThumbnailAtIndex(
                    source, 0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maximumPicturePixels,
                    ] as CFDictionary),
                let picture = picture(from: image)
            else { continue }
            return picture
        }
        return nil
    }

    private static func picture(from image: CGImage) -> ClipboardPreview.Picture? {
        let bytes = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                bytes, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return ClipboardPreview.Picture(png: bytes as Data)
    }

    private static func waveform(
        for asset: AVURLAsset, track: AVAssetTrack, duration: Double
    ) async throws -> [Float]? {
        if duration <= maximumDecodedAudioSeconds {
            return try await audioPeaks(
                in: asset, track: track, start: 0, duration: duration, bars: waveformBarCount)
        }

        // Sample short windows throughout long recordings instead of decoding the whole track.
        let barsPerWindow = waveformBarCount / waveformWindowCount
        let slice = duration / Double(waveformWindowCount)
        let windowDuration = maximumDecodedAudioSeconds / Double(waveformWindowCount)
        var peaks: [Float] = []
        var hasSamples = false
        for index in 0..<waveformWindowCount {
            try Task.checkCancellation()
            let start = Double(index) * slice + (slice - windowDuration) / 2
            if let window = try await audioPeaks(
                in: asset, track: track, start: start, duration: windowDuration, bars: barsPerWindow
            ) {
                hasSamples = true
                peaks.append(contentsOf: window)
            } else {
                peaks.append(contentsOf: repeatElement(0, count: barsPerWindow))
            }
        }
        return hasSamples ? peaks : nil
    }

    private static func audioPeaks(
        in asset: AVURLAsset, track: AVAssetTrack, start: Double, duration: Double, bars: Int
    ) async throws -> [Float]? {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
        guard reader.canAdd(output) else { return nil }
        let timescale: CMTimeScale = 48_000
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: timescale),
            duration: CMTime(seconds: duration, preferredTimescale: timescale))
        let provider = reader.outputProvider(for: output)
        try reader.start()
        defer { reader.cancelReading() }

        var peaks = Array(repeating: Float.zero, count: bars)
        var hasSamples = false
        while let buffer = try await provider.next() {
            try Task.checkCancellation()
            if buffer.withUnsafeSampleBuffer({ buffer in
                updatePeaks(
                    &peaks, with: buffer, start: start, duration: duration)
            }) {
                hasSamples = true
            }
        }
        return hasSamples ? peaks : nil
    }

    private static func updatePeaks(
        _ peaks: inout [Float], with buffer: CMSampleBuffer, start: Double, duration: Double
    ) -> Bool {
        guard let bytes = CMSampleBufferGetDataBuffer(buffer),
            let format = CMSampleBufferGetFormatDescription(buffer),
            let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else { return false }

        let channels = Int(description.mChannelsPerFrame)
        let rate = description.mSampleRate
        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        let byteCount = CMBlockBufferGetDataLength(bytes)
        guard (1...32).contains(channels), rate.isFinite, rate > 0, timestamp.isFinite,
            byteCount <= 1_024 * 1_024, byteCount.isMultiple(of: MemoryLayout<Float>.size)
        else { return false }

        let sampleCount = byteCount / MemoryLayout<Float>.size
        let frameCount = min(sampleCount / channels, CMSampleBufferGetNumSamples(buffer))
        guard frameCount > 0 else { return false }

        var samples = Array(repeating: Float.zero, count: sampleCount)
        let status = samples.withUnsafeMutableBytes { destination -> OSStatus in
            guard let address = destination.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(
                bytes, atOffset: 0, dataLength: byteCount, destination: address)
        }
        guard status == noErr else { return false }

        for frame in 0..<frameCount {
            let progress = (timestamp - start + Double(frame) / rate) / duration
            guard progress >= 0, progress <= 1 else { continue }
            let index = min(Int(progress * Double(peaks.count)), peaks.count - 1)
            let offset = frame * channels
            for channel in 0..<channels {
                let amplitude = abs(samples[offset + channel])
                if amplitude.isFinite { peaks[index] = max(peaks[index], min(1, amplitude)) }
            }
        }
        return true
    }
}
