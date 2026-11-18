import AppKit
import Testing

@testable import AppKite

@MainActor
struct ClipboardHistoryPolicyTests {
    @Test func `Manual pause survives relaunch and resumes at the next copy`() throws {
        let fixture = try Fixture()
        let history = fixture.relaunch()
        history.pauseCollection(.manual)
        try fixture.copy("Pendant la pause")
        #expect(history.pollForCopy() == nil)

        let relaunched = fixture.relaunch()
        #expect(relaunched.collectionPause == .manual)
        try fixture.copy("Pendant la pause après relance")
        #expect(relaunched.pollForCopy() == nil)
        relaunched.resumeCollection()
        #expect(try fixture.preferences.pause == nil)
        #expect(relaunched.pollForCopy() == nil)

        try fixture.copy("Après la reprise")
        #expect(relaunched.pollForCopy()?.payload.plainText == "Après la reprise")
    }

    @Test func `Timed pause resumes at its stored deadline`() throws {
        let fixture = try Fixture()
        let deadline = Date.now.addingTimeInterval(60)
        fixture.relaunch().pauseCollection(.until(deadline))

        let relaunched = fixture.relaunch()
        #expect(relaunched.collectionPause == .until(deadline))
        try fixture.copy("Pendant la pause")
        #expect(relaunched.pollForCopy(at: deadline.addingTimeInterval(-1)) == nil)
        #expect(relaunched.isCollectionPaused)

        #expect(relaunched.pollForCopy(at: deadline) == nil)
        #expect(!relaunched.isCollectionPaused)
        #expect(try fixture.preferences.pause == nil)
        try fixture.copy("Après l’échéance")
        #expect(relaunched.pollForCopy(at: deadline)?.payload.plainText == "Après l’échéance")

        fixture.preferences.setPause(.until(Date.now.addingTimeInterval(-1)))
        try fixture.copy("Présent au lancement")
        let startedAfterDeadline = fixture.relaunch()
        #expect(!startedAfterDeadline.isCollectionPaused)
        #expect(startedAfterDeadline.pollForCopy() == nil)
        try fixture.copy("Première copie après relance")
        #expect(
            startedAfterDeadline.pollForCopy()?.payload.plainText == "Première copie après relance")
    }

    @Test func `Unreadable collection settings suspend collection until explicitly repaired`()
        throws
    {
        let fixture = try Fixture()
        let pauseKey = "clipboardHistory.pause"
        let exclusionsKey = "clipboardHistory.excludedApplications"
        let invalidExclusions = Data("{".utf8)
        fixture.defaults.set("not a data value", forKey: pauseKey)
        fixture.defaults.set(invalidExclusions, forKey: exclusionsKey)

        let history = fixture.relaunch()
        #expect(history.isCollectionPaused)
        #expect(history.invalidCollectionSettings == [.pause, .exclusions])
        try fixture.copy("À ignorer")
        history.resumeCollection()
        #expect(history.pollForCopy() == nil)
        #expect(fixture.defaults.string(forKey: pauseKey) == "not a data value")

        history.resetCollectionSetting(.pause)
        #expect(try fixture.preferences.pause == .manual)
        #expect(fixture.defaults.data(forKey: exclusionsKey) == invalidExclusions)
        #expect(fixture.relaunch().invalidCollectionSettings == [.exclusions])
        history.resumeCollection()
        #expect(history.pollForCopy() == nil)

        history.resetCollectionSetting(.exclusions)
        let relaunched = fixture.relaunch()
        #expect(relaunched.invalidCollectionSettings.isEmpty)
        #expect(relaunched.collectionPause == .manual)
        #expect(try fixture.preferences.excludedApplications.isEmpty)
        relaunched.resumeCollection()
        #expect(relaunched.pollForCopy() == nil)
        try fixture.copy("Nouvelle copie")
        #expect(relaunched.pollForCopy()?.payload.plainText == "Nouvelle copie")
    }

    @Test func `Failed thumbnails keep search results and clear their warning on retry`()
        async throws
    {
        let fixture = try Fixture()
        let history = fixture.relaunch()
        let image = ClipboardEntry(
            id: UUID(), text: "Image", sourceBundleIdentifier: nil, lastUsedAt: .now, kind: .image)
        let thumbnail = Data([0x01])
        let store = ArchiveFixture(
            cards: [image], sampleThumbnails: [image.id: thumbnail], rejectFirstThumbnailBatch: true
        )
        try await history.loadHistory(from: store)
        try #require(try await waitUntil { history.historyMessage != nil })
        #expect(history.historyMessage?.key == "Impossible de charger certaines vignettes.")
        #expect(history.visibleEntries == [image])
        #expect(!history.isSearching)

        history.showMoreEntries()
        try #require(try await waitUntil { history.thumbnails[image.id] == thumbnail })
        #expect(history.historyMessage == nil)
    }

    @Test func `A saved copy preserves the warning for deferred archive cleanup`() async throws {
        let fixture = try Fixture()
        let history = fixture.relaunch()
        let existing = ClipboardEntry(
            id: UUID(), text: "À supprimer", sourceBundleIdentifier: nil, lastUsedAt: .now)
        let store = ArchiveFixture(cards: [existing], deferArchiveCleanup: true)
        history.startCollection(opening: { store })
        try #require(try await waitUntil { history.visibleEntries == [existing] })

        history.clearUnprotectedEntries()
        try #require(
            try await waitUntil { history.historyMessage != nil && history.visibleEntries.isEmpty })
        let warning = try #require(history.historyMessage)
        #expect(
            warning.key
                == "Suppression enregistrée. Le nettoyage des fichiers sera retenté au prochain lancement."
        )

        try fixture.copy("Copie enregistrée")
        try #require(
            try await waitUntil { history.visibleEntries.first?.text == "Copie enregistrée" })
        #expect(history.historyMessage == warning)
    }

    @Test func `New copies are captured in order during a suspended archive write`() async throws {
        let fixture = try Fixture()
        let pasteboard = fixture.pasteboard
        let (polls, polled) = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (writes, written) = AsyncStream<ArchiveWrite>.makeStream()
        let (gate, releaseFirstWrite) = AsyncStream<Void>.makeStream()
        let store = ArchiveFixture(writes: written, gate: gate)
        let history = ClipboardHistoryComposition.makeHistory(
            pasteboard: PasteboardClient(
                pasteboard: pasteboard, readAccessBehavior: { .alwaysAllow },
                foregroundApplication: {
                    polled.yield(pasteboard.changeCount)
                    return nil
                }),
            preferences: fixture.preferences, startsAutomatically: false
        )
        let timeout = Task {
            try await Task.sleep(for: .seconds(5))
            polled.finish()
            written.finish()
        }
        defer {
            timeout.cancel()
            releaseFirstWrite.finish()
            polled.finish()
            written.finish()
        }

        var archiveWrites = writes.makeAsyncIterator()
        var observedPolls = polls.makeAsyncIterator()
        history.startCollection(opening: { store })
        try fixture.copy("Première copie")
        let first = try #require(await archiveWrites.next())
        #expect(first.text == "Première copie")

        for text in ["Deuxième copie", "Troisième copie"] {
            try fixture.copy(text)
            let count = pasteboard.changeCount
            var observed = await observedPolls.next()
            while let sample = observed, sample != count {
                observed = await observedPolls.next()
            }
            try #require(observed == count)
        }
        #expect(await store.startedCount == 1)
        let resumedAt = Date.now
        releaseFirstWrite.finish()

        let second = try #require(await archiveWrites.next())
        let third = try #require(await archiveWrites.next())
        #expect([second.text, third.text] == ["Deuxième copie", "Troisième copie"])
        #expect(first.date < second.date)
        #expect(second.date < third.date)
        #expect(third.date < resumedAt)
    }

    @Test func `A successful copy leaves the previous archive rejection visible`() async throws {
        let fixture = try Fixture()
        let history = fixture.relaunch()
        let store = ArchiveFixture(rejectFirstWrite: true)
        history.startCollection(opening: { store })

        try fixture.copy("Copie refusée")
        try #require(try await waitUntil { history.archiveFailure != nil })
        let message = try #require(history.archiveFailure)
        #expect(message.key == "Copie non archivée. L’espace disque disponible est insuffisant.")

        try fixture.copy("Copie enregistrée")
        try #require(
            try await waitUntil { history.visibleEntries.first?.text == "Copie enregistrée" })
        #expect(history.archiveFailure == message)

        history.dismissArchiveFailure()
        #expect(history.archiveFailure == nil)
    }

    @Test func `A paste waits for a replay cleanup that has already started`() async throws {
        let fixture = try Fixture()
        let entry = ClipboardEntry(
            id: UUID(), text: "Document archivé", sourceBundleIdentifier: nil, lastUsedAt: .now,
            kind: .files)
        let (events, observed) = AsyncStream<ReplayEvent>.makeStream()
        let (polls, polled) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (cleanup, releaseCleanup) = AsyncStream<Void>.makeStream()
        let store = ArchiveFixture(
            cards: [entry], replayDirectory: fixture.directory.appending(path: "replays"),
            replayEvents: observed, cleanupGate: cleanup)
        var pasteRequested = false
        var history: ClipboardHistoryState? = ClipboardHistoryComposition.makeHistory(
            pasteboard: PasteboardClient(
                pasteboard: fixture.pasteboard, readAccessBehavior: { .alwaysAllow },
                foregroundApplication: {
                    if pasteRequested { polled.yield(()) }
                    return nil
                }),
            preferences: fixture.preferences, startsAutomatically: false)
        weak var weakHistory = history
        let timeout = Task {
            try await Task.sleep(for: .seconds(10))
            releaseCleanup.finish()
            observed.finish()
            polled.finish()
        }
        defer {
            timeout.cancel()
            releaseCleanup.finish()
            observed.finish()
            polled.finish()
        }

        var failure: (any Error)?
        do {
            try #require(history != nil)
            var replayEvents = events.makeAsyncIterator()
            var observedPolls = polls.makeAsyncIterator()
            history?.startCollection(opening: { store })
            _ = try await nextReplayEvent(in: &replayEvents) { $0 == .searched }

            try fixture.copy("Copie qui déclenche le nettoyage")
            _ = try await nextReplayEvent(in: &replayEvents) { $0 == .cleanupStarted(nil) }
            pasteRequested = true
            history?.paste(entry)
            try #require(await observedPolls.next() != nil)
            let waitingLog = await store.replayLog
            #expect(
                !waitingLog.contains { if case .preparationStarted = $0 { true } else { false } })

            releaseCleanup.finish()
            let preparation = try await nextReplayEvent(in: &replayEvents) {
                if case .preparationStarted = $0 { true } else { false }
            }
            let replayID = try #require(preparation.startedReplayID)
            _ = try await nextReplayEvent(in: &replayEvents) { $0 == .cleanupFinished(replayID) }
            _ = try await nextReplayEvent(in: &replayEvents) { $0 == .markedUsed }
            _ = try await nextReplayEvent(in: &replayEvents) { $0 == .searched }

            let log = await store.replayLog
            let cleaned = try #require(log.firstIndex(of: .cleanupFinished(nil)))
            let prepared = try #require(log.firstIndex(of: .preparationStarted(replayID)))
            #expect(cleaned < prepared)
            let replayURL = try #require(await store.replayURL(for: replayID))
            #expect(FileManager.default.fileExists(atPath: replayURL.path))
            #expect(try Data(contentsOf: replayURL) == Data("Contenu archivé".utf8))
            #expect(fixture.pasteboard.string(forType: .fileURL) == replayURL.absoluteString)
        } catch {
            failure = error
        }

        releaseCleanup.finish()
        history = nil
        await expectReleasedHistory { weakHistory == nil }
        if let failure { throw failure }
    }

    @Test func `Collection continues while a file replay is being prepared`() async throws {
        let fixture = try Fixture()
        let entry = ClipboardEntry(
            id: UUID(), text: "Document archivé", sourceBundleIdentifier: nil, lastUsedAt: .now,
            kind: .files)
        let (events, observed) = AsyncStream<ReplayEvent>.makeStream()
        let (polls, polled) = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (preparation, releasePreparation) = AsyncStream<Void>.makeStream()
        let store = ArchiveFixture(
            cards: [entry], replayDirectory: fixture.directory.appending(path: "replays"),
            replayEvents: observed, preparationGate: preparation)
        var history: ClipboardHistoryState? = ClipboardHistoryComposition.makeHistory(
            pasteboard: PasteboardClient(
                pasteboard: fixture.pasteboard, readAccessBehavior: { .alwaysAllow },
                foregroundApplication: {
                    polled.yield(fixture.pasteboard.changeCount)
                    return nil
                }),
            preferences: fixture.preferences, startsAutomatically: false)
        weak var weakHistory = history
        let timeout = Task {
            try await Task.sleep(for: .seconds(10))
            releasePreparation.finish()
            observed.finish()
            polled.finish()
        }
        defer {
            timeout.cancel()
            releasePreparation.finish()
            observed.finish()
            polled.finish()
        }

        var failure: (any Error)?
        do {
            try #require(history != nil)
            var replayEvents = events.makeAsyncIterator()
            var observedPolls = polls.makeAsyncIterator()
            history?.startCollection(opening: { store })
            _ = try await nextReplayEvent(in: &replayEvents) { $0 == .searched }
            history?.paste(entry)
            let started = try await nextReplayEvent(in: &replayEvents) {
                if case .preparationStarted = $0 { true } else { false }
            }
            let replayID = try #require(started.startedReplayID)
            let replayURL = try #require(await store.replayURL(for: replayID))

            let newerCopy = "Nouvelle copie pendant la préparation"
            try fixture.copy(newerCopy)
            let changeCount = fixture.pasteboard.changeCount
            var sample = await observedPolls.next()
            while let count = sample, count != changeCount { sample = await observedPolls.next() }
            try #require(sample == changeCount)
            _ = try await nextReplayEvent(in: &replayEvents) { $0 == .recorded(newerCopy) }
            try #require(await observedPolls.next() == changeCount)

            let preparingLog = await store.replayLog
            #expect(!preparingLog.contains { if case .cleanupStarted = $0 { true } else { false } })
            #expect(FileManager.default.fileExists(atPath: replayURL.path))
            releasePreparation.finish()
            _ = try await nextReplayEvent(in: &replayEvents) {
                $0 == .preparationFinished(replayID)
            }
            #expect(fixture.pasteboard.changeCount == changeCount)
            #expect(fixture.pasteboard.string(forType: .string) == newerCopy)
        } catch {
            failure = error
        }

        releasePreparation.finish()
        history = nil
        await expectReleasedHistory { weakHistory == nil }
        if let failure { throw failure }
    }

    private func nextReplayEvent(
        in events: inout AsyncStream<ReplayEvent>.Iterator,
        matching predicate: (ReplayEvent) -> Bool
    ) async throws -> ReplayEvent {
        while let event = await events.next(isolation: #isolation) {
            if predicate(event) { return event }
        }
        return try #require(nil as ReplayEvent?, "Le scénario de restitution n’a pas progressé.")
    }

    private func expectReleasedHistory(_ released: () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while !released(), clock.now < deadline { await Task.yield() }
        #expect(released(), "L’état et sa tâche de collage doivent être libérés au teardown.")
    }

    @Test func selectAllIncludesLaterPagesAndClearsPinnedSelection() async throws {
        let fixture = try Fixture()
        let history = fixture.relaunch()
        let count = ClipboardHistoryQuery.pageSize + 3
        let cards = (0..<count).map { index in
            ClipboardEntry(
                id: UUID(), text: "Carte \(index)", sourceBundleIdentifier: nil, lastUsedAt: .now,
                isPinned: index == 0 || index == count - 1)
        }
        let store = ArchiveFixture(cards: cards)
        try await history.loadHistory(from: store)
        try #require(
            try await waitUntil { history.visibleEntries.count == ClipboardHistoryQuery.pageSize })

        let pinned = try #require(cards.first)
        #expect(history.selectedIDs == [pinned.id])
        history.selectAllUnpinned()
        #expect(history.selectedIDs == Set(cards.filter { !$0.isPinned }.map(\.id)))
        #expect(history.hasMoreEntries)
        #expect(history.focusedEntryID != pinned.id)

        history.showMoreEntries()
        try #require(try await waitUntil { history.visibleEntries.count == count })
        #expect(history.selectedIDs == Set(cards.filter { !$0.isPinned }.map(\.id)))
    }

    @Test func selectAllWaitsForTheCurrentFilterAndIsClearedWhenItChanges() async throws {
        let fixture = try Fixture()
        let history = fixture.relaunch()
        let pinned = ClipboardEntry(
            id: UUID(), text: "Épingle", sourceBundleIdentifier: nil, lastUsedAt: .now,
            isPinned: true)
        let unpinned = ClipboardEntry(
            id: UUID(), text: "Copie", sourceBundleIdentifier: nil, lastUsedAt: .now)
        try await history.loadHistory(from: ArchiveFixture(cards: [pinned, unpinned]))
        try #require(try await waitUntil { history.selectedIDs == [pinned.id] })

        history.showMoreEntries()
        #expect(history.isSearching)
        history.selectAllUnpinned()
        #expect(history.selectedIDs == [unpinned.id])

        history.searchText = "Co"
        #expect(history.isSearching)
        history.selectAllUnpinned()
        try #require(try await waitUntil { !history.isSearching })
        #expect(history.selectedIDs == [unpinned.id])

        history.searchText = "Cop"
        history.selectAllUnpinned()
        history.searchText = "Copie"
        try #require(try await waitUntil { !history.isSearching })
        #expect(history.selectedIDs == [pinned.id])
    }

    @Test func selectAllWaitsForTheInitialStore() async throws {
        let fixture = try Fixture()
        let history = fixture.relaunch()
        let pinned = ClipboardEntry(
            id: UUID(), text: "Épingle", sourceBundleIdentifier: nil, lastUsedAt: .now,
            isPinned: true)
        let unpinned = ClipboardEntry(
            id: UUID(), text: "Copie", sourceBundleIdentifier: nil, lastUsedAt: .now)
        let store = ArchiveFixture(cards: [pinned, unpinned])
        let (gate, open) = AsyncStream<Void>.makeStream()
        history.startCollection(opening: {
            var step = gate.makeAsyncIterator()
            _ = await step.next()
            return store
        })

        history.selectAllUnpinned()
        open.yield(())
        open.finish()
        try #require(try await waitUntil { history.visibleEntries.count == 2 })
        #expect(history.selectedIDs == [unpinned.id])
    }

    @Test func archivesRemainAccessibleWhenInitialCollectionsFail() async throws {
        let fixture = try Fixture()
        let history = fixture.relaunch()
        let entry = ClipboardEntry(
            id: UUID(), text: "Document archivé", sourceBundleIdentifier: nil, lastUsedAt: .now,
            kind: .files)
        let store = ArchiveFixture(
            cards: [entry], rejectCollections: true,
            replayDirectory: fixture.directory.appending(path: "replays"))
        history.startCollection(opening: { store })
        try #require(try await waitUntil { history.historyMessage != nil })

        history.searchText = "Document"
        try #require(try await waitUntil { history.visibleEntries == [entry] })
        #expect(history.historyMessage?.key == "Impossible de charger les collections.")

        history.paste(entry)
        try #require(try await waitUntil { fixture.pasteboard.string(forType: .fileURL) != nil })
        let urlString = try #require(fixture.pasteboard.string(forType: .fileURL))
        let replayURL = try #require(URL(string: urlString))
        #expect(try Data(contentsOf: replayURL) == Data("Contenu archivé".utf8))
    }

    @Test(arguments: [1, 3])
    func `Later images get thumbnails when earlier pages have none`(emptyPages: Int) async throws {
        let fixture = try Fixture()
        let history = fixture.relaunch()
        let pageSize = ClipboardHistoryQuery.pageSize
        let lastIndex = (emptyPages + 1) * pageSize
        let imageIndices = [emptyPages * pageSize, lastIndex]
        let cards = (0...lastIndex).map { index in
            ClipboardEntry(
                id: UUID(), text: "Carte \(index)", sourceBundleIdentifier: nil, lastUsedAt: .now,
                kind: imageIndices.contains(index) ? .image : .spreadsheet)
        }
        let firstImage = cards[imageIndices[0]]
        let lastImage = cards[lastIndex]
        let thumbnail = Data([0x01])
        let store = ArchiveFixture(
            cards: cards, sampleThumbnails: [firstImage.id: thumbnail, lastImage.id: thumbnail])
        try await history.loadHistory(from: store)
        try #require(try await waitUntil { history.visibleEntries.count == pageSize })

        // Changing the limit in quick succession leaves more than one new batch to load.
        for _ in 0..<emptyPages {
            history.showMoreEntries()
        }
        try #require(try await waitUntil { history.thumbnails[firstImage.id] == thumbnail })
        let previousBatches = await store.thumbnailBatches
        #expect(previousBatches.allSatisfy { $0.count <= pageSize })

        history.showMoreEntries()
        try #require(try await waitUntil { history.thumbnails[lastImage.id] == thumbnail })
        let batches = await store.thumbnailBatches
        #expect(Array(batches.dropFirst(previousBatches.count)) == [[lastImage.id]])
    }

    private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !condition() {
            guard clock.now < deadline else { return false }
            try await clock.sleep(for: .milliseconds(10))
        }
        return true
    }

    @Test func `Exclusions and confidential copy settings apply independently to new copies`()
        async throws
    {
        let fixture = try Fixture()
        let source = "com.example.ClipboardProducer"
        let history = fixture.relaunch()
        let store = try await SwiftDataClipboardHistoryStore.open(
            at: fixture.directory.appending(path: "history.store")
        )
        let record = RecordClipboard(store: store)

        try fixture.copy("Carte existante", source: source)
        let original = try #require(history.pollForCopy())
        try await record(original)
        let entriesBeforeExclusion = try await store.entries()

        let app = try fixture.makeApplication(bundleIdentifier: source)
        history.addExcludedApplication(at: app)
        let relaunched = fixture.relaunch()
        #expect(relaunched.excludedApplications.map(\.id) == [source.lowercased()])
        #expect(relaunched.ignoresConfidentialCopies)
        try fixture.copy("Carte existante", source: source)
        #expect(relaunched.pollForCopy() == nil)
        #expect(try await store.entries() == entriesBeforeExclusion)

        try fixture.copy("Confidentiel", confidential: true)
        #expect(relaunched.pollForCopy() == nil)
        relaunched.setIgnoresConfidentialCopies(false)
        let reconfigured = fixture.relaunch()
        #expect(!reconfigured.ignoresConfidentialCopies)
        try fixture.copy("Confidentiel et exclu", source: source, confidential: true)
        #expect(reconfigured.pollForCopy() == nil)
        try fixture.copy("Confidentiel sans origine", confidential: true)
        let accepted = try #require(reconfigured.pollForCopy())
        #expect(accepted.payload.plainText == "Confidentiel sans origine")
        #expect(accepted.sourceBundleIdentifier == nil)

        let excluded = try #require(reconfigured.excludedApplications.first)
        reconfigured.removeExcludedApplication(excluded)
        try fixture.copy("Origine de nouveau admissible", source: source)
        #expect(reconfigured.pollForCopy()?.sourceBundleIdentifier == source)
        #expect(fixture.relaunch().excludedApplications.isEmpty)
    }

    @Test func `A rejected Finder selection stays visible and can be dismissed`() throws {
        let fixture = try Fixture()
        let history = fixture.relaunch()
        let file = fixture.directory.appending(path: "Document.pdf")
        try Data().write(to: file)

        func copyInvalidSelection() throws {
            let first = NSPasteboardItem()
            let second = NSPasteboardItem()
            try #require(first.setString(file.absoluteString, forType: .fileURL))
            try #require(second.setString("https://example.org/invalide", forType: .fileURL))
            fixture.pasteboard.clearContents()
            try #require(fixture.pasteboard.writeObjects([first, second]))
        }

        try copyInvalidSelection()
        #expect(history.pollForCopy() == nil)
        let rejection = try #require(history.archiveFailure)
        try fixture.copy("Texte admissible")
        #expect(history.pollForCopy()?.payload.plainText == "Texte admissible")
        #expect(history.archiveFailure == rejection)

        try copyInvalidSelection()
        #expect(history.pollForCopy() == nil)
        history.dismissArchiveFailure()
        #expect(history.pollForCopy() == nil)
        #expect(history.archiveFailure == nil)
        try copyInvalidSelection()
        #expect(history.pollForCopy() == nil)
        #expect(history.archiveFailure == rejection)
    }

    @Test func `Probable source is saved separately from declared origin`() async throws {
        let fixture = try Fixture()
        let finder = PasteboardClient.ForegroundApplication(
            processIdentifier: 1, bundleIdentifier: "com.apple.finder")
        let safari = PasteboardClient.ForegroundApplication(
            processIdentifier: 2, bundleIdentifier: "com.apple.Safari")
        var foreground = finder
        let client = PasteboardClient(
            pasteboard: fixture.pasteboard, readAccessBehavior: { .alwaysAllow },
            foregroundApplication: { foreground })
        #expect(client.pollPayload() == nil)

        try fixture.copy("Texte de test")
        let copy = try #require(client.pollPayload(isSourceExcluded: { _ in true }))
        #expect(copy.sourceBundleIdentifier == nil)
        #expect(copy.probableSourceBundleIdentifier == finder.bundleIdentifier)

        let url = fixture.directory.appending(path: "history.store")
        let date = Date.now
        do {
            let store = try await SwiftDataClipboardHistoryStore.open(at: url)
            try await store.record(copy, at: date)
        }
        do {
            let reopened = try await SwiftDataClipboardHistoryStore.open(at: url)
            let card = try #require(try await reopened.entries().first)
            #expect(card.probableSourceBundleIdentifier == finder.bundleIdentifier)
            let matches = try await reopened.search(.init(source: finder.bundleIdentifier))
            #expect(matches.entries.isEmpty)

            foreground = safari
            try fixture.copy("Texte de test")
            let ambiguous = try #require(client.pollPayload())
            #expect(ambiguous.probableSourceBundleIdentifier == nil)
            try await reopened.record(ambiguous, at: date + 1)
            let updated = try #require(try await reopened.entries().first)
            #expect(updated.id == card.id)
            #expect(updated.probableSourceBundleIdentifier == nil)

            try fixture.copy("Source déclarée", source: finder.bundleIdentifier)
            let declared = try #require(client.pollPayload())
            #expect(declared.sourceBundleIdentifier == finder.bundleIdentifier)
            #expect(declared.probableSourceBundleIdentifier == nil)

            try fixture.copy("Copie à distance", source: safari.bundleIdentifier, remote: true)
            #expect(client.pollPayload(isSourceExcluded: { $0 == safari.bundleIdentifier }) == nil)
            try fixture.copy("Copie à distance", source: safari.bundleIdentifier, remote: true)
            let remote = try #require(client.pollPayload())
            #expect(remote.sourceBundleIdentifier == nil)
            #expect(remote.probableSourceBundleIdentifier == nil)
            #expect(remote.isRemote)
            try await reopened.record(remote, at: date + 2)
        }
        let remoteStore = try await SwiftDataClipboardHistoryStore.open(at: url)
        let remoteCard = try #require(try await remoteStore.entries().first)
        #expect(remoteCard.isRemote)
        #expect(try await remoteStore.payload(for: remoteCard.id).plainText == "Copie à distance")
    }

    @MainActor
    private final class Fixture {
        let directory: URL
        let pasteboard: NSPasteboard
        let preferences: ClipboardPreferences

        private let suiteName: String
        let defaults: UserDefaults

        init() throws {
            let id = UUID().uuidString
            let suiteName = "AppKite.ClipboardHistoryPolicyTests.\(id)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            let directory = FileManager.default.temporaryDirectory.appending(path: id)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: false)
            self.suiteName = suiteName
            self.defaults = defaults
            self.directory = directory
            pasteboard = .withUniqueName()
            preferences = ClipboardPreferences(defaults: defaults)
        }

        isolated deinit {
            pasteboard.releaseGlobally()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        func relaunch() -> ClipboardHistoryState {
            ClipboardHistoryComposition.makeHistory(
                pasteboard: PasteboardClient(
                    pasteboard: pasteboard, readAccessBehavior: { .alwaysAllow }),
                preferences: preferences,
                startsAutomatically: false
            )
        }

        func copy(
            _ text: String, source: String? = nil, confidential: Bool = false, remote: Bool = false
        ) throws {
            let item = NSPasteboardItem()
            try #require(item.setString(text, forType: .string))
            if let source {
                try #require(item.setString(source, forType: .init("org.nspasteboard.source")))
            }
            if confidential {
                try #require(item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")))
            }
            if remote {
                try #require(item.setData(Data(), forType: .init("com.apple.is-remote-clipboard")))
            }
            pasteboard.clearContents()
            try #require(pasteboard.writeObjects([item]))
        }

        func makeApplication(bundleIdentifier: String) throws -> URL {
            let app = directory.appending(path: "Producteur.app")
            let contents = app.appending(path: "Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let info = [
                "CFBundleIdentifier": bundleIdentifier,
                "CFBundleName": "Producteur",
                "CFBundlePackageType": "APPL",
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: contents.appending(path: "Info.plist"))
            return app
        }
    }
}
