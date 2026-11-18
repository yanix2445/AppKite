import Foundation

@testable import AppKite

nonisolated struct ArchiveWrite: Sendable {
    let text: String?
    let date: Date
}

nonisolated enum ReplayEvent: Equatable, Sendable {
    case cleanupStarted(UUID?)
    case cleanupFinished(UUID?)
    case preparationStarted(UUID)
    case preparationFinished(UUID)
    case recorded(String)
    case markedUsed
    case searched

    var startedReplayID: UUID? {
        if case .preparationStarted(let id) = self { id } else { nil }
    }
}

actor ArchiveFixture: ClipboardHistoryStore {
    private let writes: AsyncStream<ArchiveWrite>.Continuation?
    private let gate: AsyncStream<Void>?
    private let rejectFirstWrite: Bool
    private var cards: [ClipboardEntry]
    private let rejectCollections: Bool
    private let sampleThumbnails: [UUID: Data]
    private let rejectFirstThumbnailBatch: Bool
    private let deferArchiveCleanup: Bool
    private let replayDirectory: URL?
    private let replayEvents: AsyncStream<ReplayEvent>.Continuation?
    private let cleanupGate: AsyncStream<Void>?
    private let preparationGate: AsyncStream<Void>?
    private let indexNext: (@Sendable () async throws -> Bool)?
    private let previewSourceForID: (@Sendable (UUID) throws -> ClipboardPreviewSource?)?
    private var hasBlockedCleanup = false
    private var replays: [UUID: URL] = [:]
    private(set) var replayLog: [ReplayEvent] = []
    private(set) var startedCount = 0
    private(set) var thumbnailBatches: [[UUID]] = []

    init(
        writes: AsyncStream<ArchiveWrite>.Continuation? = nil, gate: AsyncStream<Void>? = nil,
        rejectFirstWrite: Bool = false, cards: [ClipboardEntry] = [],
        rejectCollections: Bool = false, sampleThumbnails: [UUID: Data] = [:],
        rejectFirstThumbnailBatch: Bool = false,
        deferArchiveCleanup: Bool = false, replayDirectory: URL? = nil,
        replayEvents: AsyncStream<ReplayEvent>.Continuation? = nil,
        cleanupGate: AsyncStream<Void>? = nil, preparationGate: AsyncStream<Void>? = nil,
        previewSourceForID: (@Sendable (UUID) throws -> ClipboardPreviewSource?)? = nil,
        indexNext: (@Sendable () async throws -> Bool)? = nil
    ) {
        self.writes = writes
        self.gate = gate
        self.rejectFirstWrite = rejectFirstWrite
        self.cards = cards
        self.rejectCollections = rejectCollections
        self.sampleThumbnails = sampleThumbnails
        self.rejectFirstThumbnailBatch = rejectFirstThumbnailBatch
        self.deferArchiveCleanup = deferArchiveCleanup
        self.replayDirectory = replayDirectory
        self.replayEvents = replayEvents
        self.cleanupGate = cleanupGate
        self.preparationGate = preparationGate
        self.previewSourceForID = previewSourceForID
        self.indexNext = indexNext
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
        noteReplayEvent(.recorded(copy.payload.plainText ?? ""))
    }

    func search(_ query: ClipboardHistoryQuery) -> ClipboardHistoryResults {
        noteReplayEvent(.searched)
        return ClipboardHistoryResults(
            entries: Array(cards.prefix(query.limit)),
            matchingUnpinnedIDs: cards.filter { !$0.isPinned }.map(\.id), sourceIdentifiers: [],
            mostRecentID: cards.first?.id, hasMoreEntries: cards.count > query.limit,
            canClearHistory: !cards.isEmpty)
    }
    func thumbnails(for ids: [UUID]) throws -> [UUID: Data] {
        thumbnailBatches.append(ids)
        if rejectFirstThumbnailBatch && thumbnailBatches.count == 1 {
            throw CocoaError(.fileReadUnknown)
        }
        return sampleThumbnails.filter { ids.contains($0.key) }
    }
    func indexNextPendingEntry() async throws -> Bool { try await indexNext?() ?? false }
    func payload(for id: UUID) throws -> ClipboardPayload {
        throw ClipboardHistoryStoreError.missingEntry
    }
    func previewSource(for id: UUID) throws -> ClipboardPreviewSource? {
        try previewSourceForID?(id)
    }
    func prepareReplay(for ids: [UUID], replayID: UUID) async throws -> ClipboardPayload {
        guard let replayDirectory else { throw ClipboardHistoryStoreError.missingEntry }
        let directory = replayDirectory.appending(path: replayID.uuidString)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "Document.txt")
        try Data("Contenu archivé".utf8).write(to: file)
        replays[replayID] = file
        noteReplayEvent(.preparationStarted(replayID))
        if let preparationGate {
            var resume = preparationGate.makeAsyncIterator()
            _ = await resume.next()
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ClipboardHistoryStoreError.missingEntry
        }
        noteReplayEvent(.preparationFinished(replayID))
        return ClipboardPayload(items: [.init(representations: [], fileURL: file)])
    }
    func removeReplays(exceptKeeping replayID: UUID?) async throws {
        guard replayDirectory != nil else { return }
        noteReplayEvent(.cleanupStarted(replayID))
        if replayID == nil, !hasBlockedCleanup, let cleanupGate {
            hasBlockedCleanup = true
            var resume = cleanupGate.makeAsyncIterator()
            _ = await resume.next()
        }
        for (id, file) in replays where id != replayID {
            try FileManager.default.removeItem(at: file.deletingLastPathComponent())
            replays.removeValue(forKey: id)
        }
        noteReplayEvent(.cleanupFinished(replayID))
    }
    func markUsed(ids: [UUID], at date: Date) { noteReplayEvent(.markedUsed) }
    func replayURL(for id: UUID) -> URL? { replays[id] }

    private func noteReplayEvent(_ event: ReplayEvent) {
        guard let replayEvents else { return }
        replayLog.append(event)
        replayEvents.yield(event)
    }
    func collections() throws -> [ClipboardCollection] {
        if rejectCollections { throw CocoaError(.fileReadUnknown) }
        return []
    }
    func setPinned(_ isPinned: Bool, for entryID: UUID) {}
    func createCollection(named name: String) {}
    func setMembership(_ isMember: Bool, for entryID: UUID, in collectionID: UUID) {}
    func deleteCollection(id: UUID) {}
    func deleteEntries(ids: Set<UUID>, confirmingProtection: Bool) {}
    func clearUnprotectedEntries() throws {
        cards.removeAll { !$0.isProtected }
        if deferArchiveCleanup {
            throw ClipboardHistoryStoreError.archiveCleanupDeferred
        }
    }
}

@MainActor
final class CollectionTestSource: ClipboardCollectionSource {
    private var pendingCopy: ClipboardCopy?
    private(set) var ignoredCount = 0
    private(set) var polls = 0
    private(set) var changeCount = 0
    var readStatus = ClipboardReadStatus.available
    var invalidFileSelectionChangeCount: Int?

    func copy(_ text: String, source: String? = nil) {
        changeCount += 1
        pendingCopy = ClipboardCopy(
            payload: .plainText(text), sourceBundleIdentifier: source,
            probableSourceBundleIdentifier: nil)
    }

    func ignoreCurrentContents() {
        ignoredCount += 1
        pendingCopy = nil
    }

    func isCurrent(changeCount: Int) -> Bool { self.changeCount == changeCount }

    func pollPayload(
        ignoringConfidentialCopies: Bool, isSourceExcluded: (String) -> Bool
    ) -> ClipboardCopy? {
        polls += 1
        defer { pendingCopy = nil }
        if let source = pendingCopy?.sourceBundleIdentifier, isSourceExcluded(source) { return nil }
        return pendingCopy
    }
}

@MainActor
final class CollectionTestPreferences {
    var pause: ClipboardCollectionPause?
    var exclusions: [ClipboardExcludedApplication] = []
    var ignoresConfidentialCopies = true

    var operations: CollectClipboardHistory.Preferences {
        .init(
            loadPause: { self.pause }, savePause: { self.pause = $0 },
            loadExclusions: { self.exclusions }, saveExclusions: { self.exclusions = $0 },
            loadIgnoresConfidentialCopies: { self.ignoresConfidentialCopies },
            saveIgnoresConfidentialCopies: { self.ignoresConfidentialCopies = $0 })
    }
}
