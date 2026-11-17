import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AppKite

@MainActor
struct ClipboardPlaybackTests {
    @Test func `GIF pauses on its frame and can play again after its last frame`() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeGIF(in: directory)
        let playback = ClipboardPreviewPlayback()
        defer { playback.stop() }
        let id = UUID()
        let media = ClipboardPreview.Media(kind: .gif, url: url)

        #expect(!playback.isPlaying)
        #expect(playback.frame == nil)
        playback.toggle(media, for: id)
        try await waitFor { playback.frame != nil }
        let firstFrame = try #require(playback.frame)
        #expect(firstFrame.width >= firstFrame.height)
        #expect(max(firstFrame.width, firstFrame.height) < 640)

        playback.toggle(media, for: id)
        let pausedProgress = playback.progress
        try await Task.sleep(for: .milliseconds(350))
        #expect(playback.activeID == id)
        #expect(!playback.isPlaying)
        #expect(playback.frame === firstFrame)
        #expect(playback.progress == pausedProgress)

        playback.toggle(media, for: id)
        try await waitFor { !playback.isPlaying }
        #expect(playback.progress == 1)
        #expect(playback.activeID == id)
        #expect(playback.failedID == nil)

        playback.toggle(media, for: id)
        try await waitFor { playback.isPlaying && playback.progress < 1 }
        playback.stop()
        #expect(playback.activeID == nil)
        #expect(playback.frame == nil)
        #expect(!playback.isPlaying)
    }

    @Test func `Switching and stopping discard callbacks from an older media request`() async throws
    {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let broken = directory.appending(path: "broken.gif")
        try Data("missing GIF".utf8).write(to: broken)
        let archivedGIF = try makeGIF(in: directory)
        let playback = ClipboardPreviewPlayback()
        defer { playback.stop() }
        let firstID = UUID()
        let secondID = UUID()
        let second = ClipboardPreview.Media(kind: .gif, url: archivedGIF)

        playback.toggle(ClipboardPreview.Media(kind: .gif, url: broken), for: firstID)
        playback.toggle(second, for: secondID)
        try await waitFor { playback.frame != nil }
        #expect(playback.activeID == secondID)
        #expect(playback.failedID == nil)
        #expect(playback.isPlaying)

        playback.stop()
        try await Task.sleep(for: .milliseconds(350))
        #expect(playback.activeID == nil)
        #expect(playback.frame == nil)
        #expect(!playback.isPlaying)
    }

    @Test func `Remote sources and local aliases never become an active session`() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gif = try makeGIF(in: directory)
        let link = directory.appending(path: "link.gif")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: gif)
        let remote = try #require(URL(string: "https://example.invalid/animation.gif"))
        let playback = ClipboardPreviewPlayback()
        defer { playback.stop() }

        for url in [remote, link] {
            let id = UUID()
            playback.toggle(ClipboardPreview.Media(kind: .gif, url: url), for: id)
            try await waitFor { playback.failedID == id }
            #expect(playback.activeID == nil)
            #expect(!playback.isPlaying)
            #expect(playback.frame == nil)
        }
    }

    @Test func `A local audio player reports position and releases its item on stop`() async throws
    {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeSilentWAV(in: directory)
        let playback = ClipboardPreviewPlayback()
        defer { playback.stop() }
        let id = UUID()

        let media = ClipboardPreview.Media(kind: .audio, url: url, duration: 2)
        playback.toggle(media, for: id)
        try await waitFor { playback.progress > 0 }
        let player = try #require(playback.player)
        #expect(playback.activeID == id)
        #expect(playback.progress < 1)
        #expect(playback.failedID == nil)

        playback.toggle(media, for: id)
        #expect(!playback.isPlaying)
        #expect(player.rate == 0)
        playback.stop()
        #expect(player.currentItem == nil)
        #expect(playback.player == nil)
        #expect(playback.progress == 0)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while !condition(), clock.now < deadline {
            try await clock.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }

    private func makeTestDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func makeGIF(in directory: URL) throws -> URL {
        let url = directory.appending(path: "archived.gif")
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 3, nil)
        )
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.3]
        ]
        let colors: [[CGFloat]] = [
            [1, 0, 0, 1],
            [0, 1, 0, 1],
            [0, 0, 1, 1],
        ]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        for values in colors {
            let context = try #require(
                CGContext(
                    data: nil, width: 640, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
                    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let color = try #require(CGColor(colorSpace: colorSpace, components: values))
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
            let frame = try #require(context.makeImage())
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }
        try #require(CGImageDestinationFinalize(destination))
        return url
    }

    private func makeSilentWAV(in directory: URL) throws -> URL {
        let url = directory.appending(path: "archived.wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        let channel = try #require(buffer.floatChannelData?.pointee)
        channel.update(repeating: 0, count: Int(buffer.frameLength))
        let writer = try AVAudioFile(forWriting: url, settings: format.settings)
        try writer.write(from: buffer)
        return url
    }
}
