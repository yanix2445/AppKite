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
        #expect(fixture.preferences.pause == nil)
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
        #expect(fixture.preferences.pause == nil)
        try fixture.copy("Après l’échéance")
        #expect(relaunched.pollForCopy(at: deadline)?.payload.plainText == "Après l’échéance")

        fixture.preferences.pause = .until(Date.now.addingTimeInterval(-1))
        try fixture.copy("Présent au lancement")
        let startedAfterDeadline = fixture.relaunch()
        #expect(!startedAfterDeadline.isCollectionPaused)
        #expect(startedAfterDeadline.pollForCopy() == nil)
        try fixture.copy("Première copie après relance")
        #expect(
            startedAfterDeadline.pollForCopy()?.payload.plainText == "Première copie après relance")
    }

    @Test func `New copies are captured in order during a suspended archive write`() async throws {
        let fixture = try Fixture()
        let pasteboard = fixture.pasteboard
        let (polls, polled) = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (writes, written) = AsyncStream<ArchiveWrite>.makeStream()
        let (gate, releaseFirstWrite) = AsyncStream<Void>.makeStream()
        let store = ArchiveFixture(writes: written, gate: gate)
        let history = ClipboardHistoryState(
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
        private let defaults: UserDefaults

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
            ClipboardHistoryState(
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

    private struct ArchiveWrite: Sendable {
        let text: String?
        let date: Date
    }

    private actor ArchiveFixture: ClipboardHistoryStore {
        private let writes: AsyncStream<ArchiveWrite>.Continuation?
        private let gate: AsyncStream<Void>?
        private let rejectFirstWrite: Bool
        private var cards: [ClipboardEntry]
        private let sampleThumbnails: [UUID: Data]
        private(set) var startedCount = 0
        private(set) var thumbnailBatches: [[UUID]] = []

        init(
            writes: AsyncStream<ArchiveWrite>.Continuation? = nil, gate: AsyncStream<Void>? = nil,
            rejectFirstWrite: Bool = false, cards: [ClipboardEntry] = [],
            sampleThumbnails: [UUID: Data] = [:]
        ) {
            self.writes = writes
            self.gate = gate
            self.rejectFirstWrite = rejectFirstWrite
            self.cards = cards
            self.sampleThumbnails = sampleThumbnails
        }

        func record(_ copy: ClipboardCopy, at date: Date) async throws {
            startedCount += 1
            writes?.yield(ArchiveWrite(text: copy.payload.plainText, date: date))
            if startedCount == 1 {
                if rejectFirstWrite {
                    throw ClipboardHistoryStoreError.insufficientArchiveCapacity
                }
                if let gate {
                    var resume = gate.makeAsyncIterator()
                    _ = await resume.next()
                }
            }
            cards.insert(
                ClipboardEntry(
                    id: UUID(), text: copy.payload.plainText ?? "", sourceBundleIdentifier: nil,
                    lastUsedAt: date), at: 0)
        }

        func entries() -> [ClipboardEntry] { cards }
        func search(_ query: ClipboardHistoryQuery) -> ClipboardHistoryResults {
            ClipboardHistoryResults(
                entries: Array(cards.prefix(query.limit)), sourceIdentifiers: [],
                mostRecentID: cards.first?.id, hasMoreEntries: cards.count > query.limit,
                canClearHistory: !cards.isEmpty)
        }
        func thumbnails(for ids: [UUID]) -> [UUID: Data] {
            thumbnailBatches.append(ids)
            return sampleThumbnails.filter { ids.contains($0.key) }
        }
        func indexNextPendingEntry() -> Bool { false }
        func record(text: String, sourceBundleIdentifier: String?, at date: Date) {}
        func record(payload: ClipboardPayload, sourceBundleIdentifier: String?, at date: Date) {}
        func payload(for id: UUID) throws -> ClipboardPayload {
            throw ClipboardHistoryStoreError.missingEntry
        }
        func prepareReplay(for id: UUID, replayID: UUID) throws -> ClipboardPayload {
            try payload(for: id)
        }
        func removeReplays(exceptKeeping replayID: UUID?) {}
        func markUsed(id: UUID, at date: Date) {}
        func collections() -> [ClipboardCollection] { [] }
        func setPinned(_ isPinned: Bool, for entryID: UUID) {}
        func createCollection(named name: String) {}
        func setMembership(_ isMember: Bool, for entryID: UUID, in collectionID: UUID) {}
        func deleteCollection(id: UUID) {}
        func deleteEntry(id: UUID, confirmingProtection: Bool) {}
        func clearUnprotectedEntries() {}
    }
}
