import Foundation
import Testing

@testable import AppKite

@MainActor
struct ClipboardPreviewRequestsTests {
    @Test func `Reset keeps cancelled work in its slots and ignores its result`() async throws {
        let (starts, started) = AsyncStream<RenderStart>.makeStream()
        let (cancellations, cancelled) = AsyncStream<Int>.makeStream()
        let renderer = SuspendedPreviewRenderer(started: started, cancelled: cancelled)
        let requests = ClipboardPreviewRequests(render: { await renderer.render($0) })
        let store = ArchiveFixture(previewSourceForID: Self.source)
        let first = card()
        let second = card()
        let removed = card()
        let next = card()
        let timeout = Task {
            try await Task.sleep(for: .seconds(10))
            started.finish()
            cancelled.finish()
            await renderer.releaseAll()
        }
        defer {
            timeout.cancel()
            requests.reset()
            started.finish()
            cancelled.finish()
            Task { await renderer.releaseAll() }
        }

        requests.show(first, store: store)
        requests.show(second, store: store)
        requests.show(removed, store: store)
        requests.hide(removed.id)
        var calls = starts.makeAsyncIterator()
        let one = try #require(await calls.next())
        let two = try #require(await calls.next())
        #expect(Set([one.id, two.id]) == Set([first.id, second.id]))

        requests.reset()
        requests.show(first, store: store)
        requests.show(next, store: store)
        var stops = cancellations.makeAsyncIterator()
        let cancelledOne = try #require(await stops.next())
        let cancelledTwo = try #require(await stops.next())
        #expect(Set([cancelledOne, cancelledTwo]) == Set([one.number, two.number]))

        let oldFirst = one.id == first.id ? one : two
        let oldSecond = one.id == second.id ? one : two
        await renderer.finish(oldSecond.number)
        let incoming = try #require(await calls.next())
        #expect(incoming.id == next.id)
        #expect(requests.results[second.id] == nil)

        await renderer.finish(oldFirst.number)
        let restarted = try #require(await calls.next())
        #expect(restarted.id == first.id)
        #expect(requests.results[first.id] == nil)

        await renderer.finish(incoming.number)
        await renderer.finish(restarted.number)
        try await waitForResult(first.id, in: requests)
        try await waitForResult(next.id, in: requests)
        if case .ready(let result) = requests.results[first.id] {
            #expect(result.name == String(restarted.number))
        } else {
            Issue.record("Le nouveau rendu doit être disponible.")
        }
        #expect(await renderer.peak == 2)
        #expect(requests.results[removed.id] == nil)
    }

    @Test(arguments: [false, true])
    func `Cache protects visible results and evicts the least recently used hidden one`(
        byWeight: Bool
    ) async throws {
        let picture = ClipboardPreview.Picture(
            png: Data(count: byWeight ? 9 * 1_024 * 1_024 : 1), pixelWidth: 1, pixelHeight: 1)
        let requests = ClipboardPreviewRequests(render: { _ in
            .init(kind: .image, content: .picture(picture))
        })
        let store = ArchiveFixture(previewSourceForID: Self.source)
        let cards = (0..<(byWeight ? 3 : 49)).map { _ in card() }
        let first = try #require(cards.first)
        let second = cards[1]
        for entry in cards.dropLast() {
            requests.show(entry, store: store)
            try await waitForResult(entry.id, in: requests)
            requests.hide(entry.id)
        }
        requests.show(first, store: store)
        #expect(requests.results[first.id] != nil)
        let last = try #require(cards.last)
        requests.show(last, store: store)
        try await waitForResult(last.id, in: requests)
        #expect(requests.results[first.id] != nil)
        #expect(requests.results[second.id] == nil)
        #expect(requests.results.count == cards.count - 1)
    }

    @Test func `Missing sources and absent renders keep summaries while read errors surface`()
        async throws
    {
        let missing = card()
        let failing = card()
        let noRender = card()
        let missingID = missing.id
        let failingID = failing.id
        let requests = ClipboardPreviewRequests(render: { _ in nil })
        let store = ArchiveFixture(previewSourceForID: { id in
            if id == missingID { return nil }
            if id == failingID { throw CocoaError(.fileReadUnknown) }
            return Self.source(id)
        })
        for entry in [missing, failing, noRender] {
            requests.show(entry, store: store)
            try await waitForResult(entry.id, in: requests)
        }
        if case .summary = requests.results[missing.id] {
        } else {
            Issue.record("Une source absente conserve le résumé.")
        }
        if case .summary = requests.results[noRender.id] {
        } else {
            Issue.record("Un rendu absent conserve le résumé.")
        }
        if case .ready(let result) = requests.results[failing.id],
            case .unavailable = result.content
        {
            #expect(result.name == failing.text)
            #expect(result.kind == .image)
        } else {
            Issue.record("Une erreur de lecture doit produire un aperçu indisponible.")
        }
    }

    private func card() -> ClipboardEntry {
        ClipboardEntry(
            id: UUID(), text: "Image", sourceBundleIdentifier: nil, lastUsedAt: .now, kind: .image)
    }

    private nonisolated static func source(_ id: UUID) -> ClipboardPreviewSource {
        .init(items: [
            .init(fileURL: URL(fileURLWithPath: "/" + id.uuidString), representations: [])
        ])
    }

    private func waitForResult(_ id: UUID, in requests: ClipboardPreviewRequests) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while requests.results[id] == nil, clock.now < deadline { await Task.yield() }
        _ = try #require(requests.results[id])
    }
}

private nonisolated struct RenderStart: Sendable {
    let number: Int
    let id: UUID
}

private actor SuspendedPreviewRenderer {
    let started: AsyncStream<RenderStart>.Continuation
    let cancelled: AsyncStream<Int>.Continuation
    private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
    private var count = 0
    private var isReleased = false
    private(set) var peak = 0

    init(
        started: AsyncStream<RenderStart>.Continuation, cancelled: AsyncStream<Int>.Continuation
    ) {
        self.started = started
        self.cancelled = cancelled
    }

    func render(_ source: ClipboardPreviewSource) async -> ClipboardPreview? {
        guard let component = source.items.first?.fileURL?.lastPathComponent,
            let id = UUID(uuidString: component)
        else { return nil }
        count += 1
        let number = count
        let cancelled = self.cancelled
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !isReleased else {
                    continuation.resume()
                    return
                }
                pending[number] = continuation
                peak = max(peak, pending.count)
                started.yield(RenderStart(number: number, id: id))
            }
        } onCancel: {
            cancelled.yield(number)
        }
        return .init(kind: .image, content: .unavailable, name: String(number))
    }

    func finish(_ number: Int) {
        pending.removeValue(forKey: number)?.resume()
    }

    func releaseAll() {
        isReleased = true
        for continuation in pending.values { continuation.resume() }
        pending.removeAll()
    }
}
