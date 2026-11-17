import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AppKite

@MainActor
struct ClipboardMediaPreviewTests {
    @Test func `Archived WAV and extensionless bytes produce the same measured waveform`()
        async throws
    {
        try await withFolder { folder in
            let file = folder.appending(path: "Voix.wav")
            let raw = folder.appending(path: "representation")
            let wave = makeWave()
            try wave.write(to: file)
            try wave.write(to: raw)

            let archived = try #require(
                await ClipboardMediaPreview.render(file, nil, file.lastPathComponent, nil))
            let direct = try #require(
                await ClipboardMediaPreview.render(raw, UTType.wav.identifier, nil, nil))
            #expect(archived.kind == .audio)
            #expect(archived.name == "Voix.wav")
            #expect(archived.format == "WAV")
            #expect(archived.byteCount == Int64(wave.count))
            #expect(direct.name == nil)
            #expect(direct.content == archived.content)
            guard case .waveform(let peaks) = direct.content else {
                Issue.record("Expected measured peaks in the audio preview.")
                return
            }
            #expect(peaks.count == 48)
            #expect((peaks.prefix(24).max() ?? 1) < 0.2)
            #expect((peaks.suffix(24).max() ?? 0) > 0.65)
            let media = try #require(direct.media)
            #expect(media.duration == 2)
            #expect(media.mimeType != nil)
            let asset = try #require(await ClipboardMediaPreview.playbackAsset(for: media))
            #expect(asset.url == raw)
            #expect(asset.referenceRestrictions == .forbidAll)
        }
    }

    @Test func `Embedded M4A artwork is shown in place of a waveform`() async throws {
        try await withFolder { folder in
            let source = folder.appending(path: "Source.wav")
            try makeWave().write(to: source)
            let file = folder.appending(path: "Avec pochette.m4a")
            let artwork = AVMutableMetadataItem()
            artwork.identifier = .commonIdentifierArtwork
            artwork.value = try coverPNG() as NSData
            artwork.dataType = kCMMetadataBaseDataType_PNG as String
            let export = try #require(
                AVAssetExportSession(
                    asset: AVURLAsset(url: source), presetName: AVAssetExportPresetAppleM4A))
            export.metadata = [artwork]
            try await export.export(to: file, as: .m4a)

            let preview = try #require(
                await ClipboardMediaPreview.render(file, nil, file.lastPathComponent, nil))
            #expect(preview.format == "M4A")
            #expect(preview.media?.duration == 2)
            guard case .picture(let picture) = preview.content else {
                Issue.record("Expected embedded artwork in the M4A preview.")
                return
            }
            let image = try decodePNG(picture.png)
            #expect(image.width == 24 && image.height == 16)
        }
    }

    @Test func `Archived and direct MOV produce an oriented video poster`() async throws {
        try await withFolder { folder in
            let movie = folder.appending(path: "Capture.mov")
            try await makeMovie(at: movie)
            let raw = folder.appending(path: "representation")
            try FileManager.default.copyItem(at: movie, to: raw)
            let file = try #require(
                await ClipboardMediaPreview.render(movie, nil, movie.lastPathComponent, nil))
            let direct = try #require(
                await ClipboardMediaPreview.render(raw, UTType.quickTimeMovie.identifier, nil, nil))
            #expect(file.kind == .video)
            #expect(file.format == "MOV")
            #expect(file.media?.duration == 1)
            #expect(direct.content == file.content)
            guard case .picture(let picture) = file.content else {
                Issue.record("Expected a poster decoded from the MOV.")
                return
            }
            let image = try decodePNG(picture.png)
            #expect(image.width == 32 && image.height == 64)
        }
    }

    @Test func `Playlists aliases and reference movies cannot open a media source`() async throws {
        try await withFolder { folder in
            let playlist = folder.appending(path: "Flux.m3u8")
            try Data("#EXTM3U\n#EXTINF:2,\nhttps://example.invalid/segment.ts\n".utf8)
                .write(to: playlist)
            #expect(await ClipboardMediaPreview.render(playlist, nil, nil, nil) == nil)
            #expect(!ClipboardMediaPreview.supportsRepresentation("public.m3u-playlist"))

            let disguised = folder.appending(path: "Flux.mov")
            try FileManager.default.copyItem(at: playlist, to: disguised)
            let unavailable = try #require(
                await ClipboardMediaPreview.render(disguised, nil, "Flux.mov", nil))
            #expect(unavailable.kind == .video)
            #expect(unavailable.content == .unavailable)
            #expect(unavailable.media == nil)

            let target = folder.appending(path: "Lecture.wav")
            try makeWave().write(to: target)
            let link = folder.appending(path: "Lien.wav")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let unsafe = ClipboardPreview.Media(kind: .audio, url: link)
            #expect(await ClipboardMediaPreview.playbackAsset(for: unsafe) == nil)

            let movie = folder.appending(path: "Autonome.mov")
            try await makeMovie(at: movie)
            let reference = folder.appending(path: "Référence.mov")
            let mutable = AVMutableMovie(url: movie, options: nil)
            try mutable.writeHeader(
                to: reference, fileType: .mov, options: .truncateDestinationToMovieHeaderOnly)
            let external = try #require(
                await ClipboardMediaPreview.render(reference, nil, reference.lastPathComponent, nil)
            )
            #expect(external.content == .unavailable)
            #expect(external.media == nil)
        }
    }

    private func withFolder(_ body: (URL) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await body(folder)
    }

    private func makeWave() -> Data {
        let sampleRate: UInt32 = 8_000
        let frameCount = sampleRate * 2
        let sampleBytes = frameCount * 2
        var wave = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { wave.append(contentsOf: $0) }
        }
        append(sampleBytes + 36)
        wave.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(sampleRate)
        append(sampleRate * 2)
        append(UInt16(2))
        append(UInt16(16))
        wave.append(contentsOf: "data".utf8)
        append(sampleBytes)
        for number in 0..<frameCount {
            let amplitude = number < sampleRate ? 0.125 : 0.75
            let angle = 2 * Double.pi * 500 * Double(number) / Double(sampleRate)
            append(Int16(sin(angle) * amplitude * Double(Int16.max)))
        }
        return wave
    }

    private func coverPNG() throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: 24, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let writer = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, nil)
        try #require(CGImageDestinationFinalize(writer))
        return data as Data
    }

    private func decodePNG(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func makeMovie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 32,
            ])
        input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 32, ty: 0)
        try #require(writer.canAdd(input))
        let attributes = CVPixelBufferCreationAttributes(
            pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA),
            size: .init(width: 64, height: 32))
        let receiver = writer.inputPixelBufferReceiver(
            for: input, pixelBufferAttributes: attributes)
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        for index in 0..<4 {
            var buffer = try CVMutablePixelBuffer(attributes)
            buffer.accessUnsafeMutableRawPlaneBytes { planes in
                for plane in planes {
                    let value = UInt8(index * 53)
                    for byteIndex in plane.bytes.indices {
                        plane.bytes[byteIndex] = value
                    }
                }
            }
            try await receiver.append(
                CVReadOnlyPixelBuffer(buffer),
                with: CMTime(value: Int64(index), timescale: 4))
        }
        writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
        receiver.finish()
        await writer.finishWriting()
        try #require(writer.status == .completed)
    }
}
