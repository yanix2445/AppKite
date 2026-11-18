import Foundation

@MainActor
final class CollectClipboardHistory {
    struct Preferences {
        let loadPause: () throws -> ClipboardCollectionPause?
        let savePause: (ClipboardCollectionPause?) -> Void
        let loadExclusions: () throws -> [ClipboardExcludedApplication]
        let saveExclusions: ([ClipboardExcludedApplication]) -> Void
        let loadIgnoresConfidentialCopies: () -> Bool
        let saveIgnoresConfidentialCopies: (Bool) -> Void
    }

    enum Event {
        case opening
        case storeOpened(any ClipboardHistoryStore)
        case ready([ClipboardCollection])
        case openingFailed(inUse: Bool)
        case collectionsFailed
        case policyChanged(ClipboardCollectionPolicy)
        case readStatusChanged(ClipboardReadStatus)
        case archiveRejected(ArchiveRejection)
        case historyChanged
        case indexedEntry
        case indexingFinished(failed: Bool)
        case replayNotice(ReplayNotice)
    }

    enum ArchiveRejection {
        case invalidSelection, insufficientCapacity, failed
    }

    enum ReplayNotice {
        case selectionTooLarge, insufficientCapacity, unreadable, copied, rankingFailed
        case writeFailed, clipboardChanged
    }

    private enum Work: Sendable {
        case archive(ClipboardCopy, Date)
        case cleanReplays(Int)
    }

    private let source: any ClipboardCollectionSource
    private let preferences: Preferences
    private let openStore: () async throws -> any ClipboardHistoryStore
    private let waitForNextPoll: () async throws -> Void
    private var store: (any ClipboardHistoryStore)?
    private var collectionTask: Task<Void, Never>?
    private var recognitionTask: Task<Void, Never>?
    private var recognitionRequested = false
    private var replayTask: Task<Void, Never>?
    private var replayCleanupTask: Task<Void, Never>?
    private var replayCleanupRequested = false
    private var lastReplayChangeCount: Int
    private var mayHaveFileReplays = true
    private var lastInvalidFileSelectionChangeCount: Int?
    private var stopping = false

    var onEvent: ((Event) -> Void)?
    private(set) var policy: ClipboardCollectionPolicy
    var readStatus: ClipboardReadStatus { source.readStatus }
    var isPasting: Bool { replayTask != nil }

    init(
        source: any ClipboardCollectionSource, preferences: Preferences,
        openStore: @escaping () async throws -> any ClipboardHistoryStore,
        waitForNextPoll: @escaping () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(180))
        }
    ) {
        self.source = source
        self.preferences = preferences
        self.openStore = openStore
        self.waitForNextPoll = waitForNextPoll
        lastReplayChangeCount = source.changeCount
        policy = ClipboardCollectionPolicy(
            ignoresConfidentialCopies: preferences.loadIgnoresConfidentialCopies())
        do {
            policy.pause = try preferences.loadPause()
        } catch {
            policy.invalidSettings.insert(.pause)
        }
        do {
            policy.exclusions = try preferences.loadExclusions()
        } catch {
            policy.invalidSettings.insert(.exclusions)
        }
        resumeIfPauseExpired(at: .now)
    }

    isolated deinit {
        collectionTask?.cancel()
        recognitionTask?.cancel()
        replayCleanupTask?.cancel()
        replayTask?.cancel()
    }

    func start(opening override: (() async throws -> any ClipboardHistoryStore)? = nil) {
        guard !stopping, collectionTask == nil else { return }
        let open = override ?? openStore
        let wait = waitForNextPoll
        collectionTask = Task { [weak self] in
            defer { self?.collectionTask = nil }
            do {
                let store = try await open()
                try Task.checkCancellation()
                self?.store = store
                self?.emit(.storeOpened(store))

                let collections: [ClipboardCollection]
                do {
                    collections = try await store.collections()
                } catch {
                    self?.emit(.collectionsFailed)
                    return
                }
                try Task.checkCancellation()
                self?.emit(.ready(collections))
                self?.requestRecognition(using: store)

                let (work, pending) = AsyncStream<Work>.makeStream()
                let worker = Task { [weak self] in
                    for await request in work {
                        guard !Task.isCancelled else { break }
                        await self?.process(request, using: store)
                    }
                }
                do {
                    while self != nil, !Task.isCancelled {
                        self?.enqueueWork(into: pending)
                        try await wait()
                    }
                } catch {
                    // Stopping the poll loop also stops the serial worker.
                }
                pending.finish()
                worker.cancel()
                await worker.value
            } catch is CancellationError {
                return
            } catch ClipboardHistoryStoreError.storageInUse {
                self?.emit(.openingFailed(inUse: true))
            } catch {
                self?.emit(.openingFailed(inUse: false))
            }
        }
        emit(.opening)
    }

    func cancel() {
        stopping = true
        collectionTask?.cancel()
        recognitionTask?.cancel()
        replayCleanupTask?.cancel()
        replayTask?.cancel()
    }

    func stop() async {
        cancel()
        await collectionTask?.value
        await recognitionTask?.value
        await replayCleanupTask?.value
        await replayTask?.value
        store = nil
    }

    func pause(_ pause: ClipboardCollectionPause) {
        guard policy.invalidSettings.isEmpty else { return }
        setPause(pause)
        emit(.policyChanged(policy))
    }

    func resume() {
        guard policy.invalidSettings.isEmpty else { return }
        source.ignoreCurrentContents()
        emit(.readStatusChanged(source.readStatus))
        setPause(nil)
        emit(.policyChanged(policy))
    }

    func repair(_ setting: ClipboardCollectionPolicy.Setting) {
        guard policy.invalidSettings.contains(setting) else { return }
        switch setting {
        case .pause:
            setPause(.manual)
        case .exclusions:
            if !policy.invalidSettings.contains(.pause) { setPause(.manual) }
            policy.exclusions = []
            preferences.saveExclusions([])
        }
        policy.invalidSettings.remove(setting)
        emit(.policyChanged(policy))
    }

    func setIgnoresConfidentialCopies(_ value: Bool) {
        policy.ignoresConfidentialCopies = value
        preferences.saveIgnoresConfidentialCopies(value)
        emit(.policyChanged(policy))
    }

    func exclude(_ application: ClipboardExcludedApplication) {
        guard !policy.invalidSettings.contains(.exclusions),
            !policy.exclusions.contains(where: { $0.id == application.id })
        else { return }
        policy.exclusions.append(application)
        policy.exclusions.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        saveExclusions()
    }

    func removeExclusion(_ application: ClipboardExcludedApplication) {
        guard !policy.invalidSettings.contains(.exclusions) else { return }
        policy.exclusions.removeAll { $0.id == application.id }
        saveExclusions()
    }

    private func saveExclusions() {
        preferences.saveExclusions(policy.exclusions)
        emit(.policyChanged(policy))
    }

    private func setPause(_ pause: ClipboardCollectionPause?) {
        policy.pause = pause
        preferences.savePause(pause)
    }

    private func resumeIfPauseExpired(at date: Date) {
        if let pause = policy.pause, !pause.isActive(at: date) { resume() }
    }

    func pollForCopy(at date: Date = .now) -> ClipboardCopy? {
        resumeIfPauseExpired(at: date)
        defer { emit(.readStatusChanged(source.readStatus)) }
        guard !policy.isPaused else { return nil }
        let copy = source.pollPayload(
            ignoringConfidentialCopies: policy.ignoresConfidentialCopies
        ) { identifier in
            let id = identifier.lowercased()
            return policy.exclusions.contains { $0.id == id }
        }
        if let changeCount = source.invalidFileSelectionChangeCount,
            changeCount != lastInvalidFileSelectionChangeCount
        {
            lastInvalidFileSelectionChangeCount = changeCount
            emit(.archiveRejected(.invalidSelection))
        }
        return copy
    }

    private func enqueueWork(into pending: AsyncStream<Work>.Continuation) {
        let date = Date.now
        if let copy = pollForCopy(at: date) { pending.yield(.archive(copy, date)) }
        let count = source.changeCount
        if !isPasting, mayHaveFileReplays, !replayCleanupRequested, count != lastReplayChangeCount {
            replayCleanupRequested = true
            pending.yield(.cleanReplays(count))
        }
    }

    private func process(_ work: Work, using store: any ClipboardHistoryStore) async {
        guard !stopping else { return }
        switch work {
        case .archive(let copy, let date):
            do {
                try await RecordClipboard(store: store)(copy, at: date)
                requestRecognition(using: store)
            } catch ClipboardHistoryStoreError.insufficientArchiveCapacity {
                emit(.archiveRejected(.insufficientCapacity))
            } catch {
                emit(.archiveRejected(.failed))
            }
            emit(.historyChanged)
        case .cleanReplays(let count):
            await cleanReplays(using: store, changeCount: count)
        }
    }

    private func cleanReplays(using store: any ClipboardHistoryStore, changeCount: Int) async {
        defer { replayCleanupRequested = false }
        guard !isPasting, mayHaveFileReplays, changeCount != lastReplayChangeCount,
            source.isCurrent(changeCount: changeCount)
        else { return }

        lastReplayChangeCount = changeCount
        let task = Task { [weak self] in
            do {
                try await store.removeReplays(exceptKeeping: nil)
                self?.mayHaveFileReplays = false
            } catch {
                // Retry after the next change without interrupting clipboard collection.
            }
        }
        replayCleanupTask = task
        await task.value
        replayCleanupTask = nil
    }

    private func requestRecognition(using store: any ClipboardHistoryStore) {
        guard !stopping else { return }
        recognitionRequested = true
        guard recognitionTask == nil else { return }
        recognitionTask = Task(priority: .utility) { [weak self] in
            defer { self?.recognitionTask = nil }
            do {
                var changed = false
                while self?.recognitionRequested == true, !Task.isCancelled {
                    self?.recognitionRequested = false
                    while try await store.indexNextPendingEntry() {
                        try Task.checkCancellation()
                        guard self != nil else { return }
                        changed = true
                        self?.emit(.indexedEntry)
                    }
                }
                if changed { self?.emit(.historyChanged) }
                self?.emit(.indexingFinished(failed: false))
            } catch is CancellationError {
                return
            } catch {
                self?.emit(.indexingFinished(failed: true))
            }
        }
    }

    @discardableResult
    func startReplay(ids: [UUID], paste: PasteClipboardEntry) -> Bool {
        guard !stopping, !isPasting, !ids.isEmpty else { return false }
        let expectedChangeCount = source.changeCount
        replayTask = Task { [weak self] in
            await self?.replay(ids: ids, paste: paste, replacing: expectedChangeCount)
        }
        return true
    }

    private func replay(ids: [UUID], paste: PasteClipboardEntry, replacing changeCount: Int) async {
        defer { replayTask = nil }
        guard let store else { return }
        await replayCleanupTask?.value
        guard !Task.isCancelled else { return }
        let replayID = UUID()
        let payload: ClipboardPayload
        do {
            payload = try await store.prepareReplay(for: ids, replayID: replayID)
            if payload.items.contains(where: { $0.fileURL != nil }) { mayHaveFileReplays = true }
        } catch ClipboardHistoryStoreError.groupedReplayTooLarge {
            emit(.replayNotice(.selectionTooLarge))
            return
        } catch ClipboardHistoryStoreError.insufficientReplayCapacity {
            emit(.replayNotice(.insufficientCapacity))
            return
        } catch {
            emit(.replayNotice(.unreadable))
            return
        }
        let outcome = await paste(payload: payload, replacing: changeCount)
        switch outcome {
        case .sent, .copied:
            lastReplayChangeCount = source.changeCount
            try? await store.removeReplays(exceptKeeping: replayID)
            if outcome == .copied { emit(.replayNotice(.copied)) }
            do {
                try await store.markUsed(ids: ids, at: .now)
                emit(.historyChanged)
            } catch {
                if outcome == .sent { emit(.replayNotice(.rankingFailed)) }
            }
        case .failed:
            emit(.replayNotice(.writeFailed))
        case .clipboardChanged:
            emit(.replayNotice(.clipboardChanged))
        }
    }

    private func emit(_ event: Event) {
        if !stopping { onEvent?(event) }
    }
}
