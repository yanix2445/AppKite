import Foundation
import Testing

@testable import AppKite

@MainActor
struct ClipboardCollectionTests {
    @Test func `A timed pause skips the current copy and resumes without a view`() {
        let source = CollectionTestSource()
        let preferences = CollectionTestPreferences()
        let deadline = Date.now.addingTimeInterval(60)
        preferences.pause = .until(deadline)
        let collection = CollectClipboardHistory(
            source: source, preferences: preferences.operations, openStore: { ArchiveFixture() })

        source.copy("En pause")
        #expect(collection.pollForCopy(at: deadline - 1) == nil)
        #expect(source.polls == 0)
        #expect(collection.pollForCopy(at: deadline) == nil)
        #expect(source.ignoredCount == 1)
        #expect(preferences.pause == nil)
        #expect(!collection.policy.isPaused)

        source.copy("Après la reprise")
        #expect(collection.pollForCopy(at: deadline + 1)?.payload.plainText == "Après la reprise")
    }

    @Test func `Exclusions filter declared sources and persist without a view`() {
        let source = CollectionTestSource()
        let preferences = CollectionTestPreferences()
        let collection = CollectClipboardHistory(
            source: source, preferences: preferences.operations, openStore: { ArchiveFixture() })
        let application = ClipboardExcludedApplication(id: "org.example.test", name: "Test")
        collection.exclude(application)
        collection.exclude(application)
        #expect(preferences.exclusions == [application])
        source.copy("Exclue", source: "ORG.EXAMPLE.TEST")
        #expect(collection.pollForCopy() == nil)
        source.copy("Origine inconnue")
        #expect(collection.pollForCopy()?.payload.plainText == "Origine inconnue")
        collection.removeExclusion(application)
        source.copy("Autorisée", source: application.id)
        #expect(collection.pollForCopy()?.payload.plainText == "Autorisée")
        #expect(preferences.exclusions.isEmpty)
    }

    @Test func `Opening failure prevents polling and duplicate starts`() async {
        let source = CollectionTestSource()
        let preferences = CollectionTestPreferences()
        let (failures, failed) = AsyncStream<Bool>.makeStream()
        var attempts = 0
        let collection = CollectClipboardHistory(
            source: source, preferences: preferences.operations,
            openStore: {
                attempts += 1
                throw ClipboardHistoryStoreError.storageInUse
            })
        collection.onEvent = { event in
            if case .openingFailed(let inUse) = event { failed.yield(inUse) }
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(10))
            failed.finish()
        }
        defer {
            timeout.cancel()
            failed.finish()
        }

        collection.start()
        collection.start()
        var events = failures.makeAsyncIterator()
        #expect(await events.next() == true)
        await collection.stop()
        #expect(attempts == 1)
        #expect(source.polls == 0)
    }

    @Test func `An archive recorded during indexing requests another pass`() async throws {
        let source = CollectionTestSource()
        let preferences = CollectionTestPreferences()
        let (passes, started) = AsyncStream<Int>.makeStream()
        let (changes, changed) = AsyncStream<Void>.makeStream()
        let (gate, release) = AsyncStream<Void>.makeStream()
        let indexing = SuspendedIndexing(started: started, gate: gate)
        let store = ArchiveFixture(indexNext: { await indexing.next() })
        let collection = CollectClipboardHistory(
            source: source, preferences: preferences.operations, openStore: { store })
        collection.onEvent = { event in
            if case .historyChanged = event { changed.yield(()) }
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(10))
            started.finish()
            changed.finish()
            release.finish()
        }
        defer {
            collection.cancel()
            timeout.cancel()
            started.finish()
            changed.finish()
            release.finish()
        }

        collection.start()
        var pass = passes.makeAsyncIterator()
        var change = changes.makeAsyncIterator()
        try #require(await pass.next() == 1)
        source.copy("Copie à indexer")
        try #require(await change.next() != nil)
        release.finish()
        #expect(await pass.next() == 2)
        await collection.stop()
    }

    @Test func `Stopping during archival waits and suppresses late events`() async throws {
        let source = CollectionTestSource()
        let preferences = CollectionTestPreferences()
        let (writes, written) = AsyncStream<ArchiveWrite>.makeStream()
        let (gate, release) = AsyncStream<Void>.makeStream()
        let store = ArchiveFixture(writes: written, gate: gate)
        let collection = CollectClipboardHistory(
            source: source, preferences: preferences.operations, openStore: { store })
        var refreshes = 0
        collection.onEvent = { event in
            if case .historyChanged = event { refreshes += 1 }
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(10))
            written.finish()
            release.finish()
        }
        defer {
            timeout.cancel()
            written.finish()
            release.finish()
            collection.cancel()
        }

        source.copy("Copie en cours")
        collection.start()
        var events = writes.makeAsyncIterator()
        let write = await events.next()
        collection.cancel()
        release.finish()
        await collection.stop()
        try #require(write?.text == "Copie en cours")
        #expect(await store.search(.init()).entries.first?.text == "Copie en cours")
        #expect(refreshes == 0)
    }
}

private actor SuspendedIndexing {
    let started: AsyncStream<Int>.Continuation
    let gate: AsyncStream<Void>
    private var count = 0

    init(started: AsyncStream<Int>.Continuation, gate: AsyncStream<Void>) {
        self.started = started
        self.gate = gate
    }

    func next() async -> Bool {
        count += 1
        started.yield(count)
        if count == 1 {
            var step = gate.makeAsyncIterator()
            _ = await step.next()
        }
        return false
    }
}
