import AppKit
import Observation

@Observable
final class ClipboardHistoryState {
    private enum CollectionWork: Sendable {
        case archive(ClipboardCopy, Date)
        case cleanReplays(changeCount: Int)
    }

    private(set) var entries: [ClipboardEntry] = []
    private(set) var selectedID: UUID?
    private(set) var collections: [ClipboardCollection] = []
    private(set) var selectedCollectionID: UUID?
    var searchText = "" { didSet { changeFilters() } }
    var selectedKind: ClipboardPayload.Kind? { didSet { changeFilters() } }
    var selectedSource: String? { didSet { changeFilters() } }
    private(set) var sourceIdentifiers: [String] = []
    private(set) var hasMoreEntries = false
    private(set) var hasUnprotectedEntries = false
    private(set) var isSearching = false
    private(set) var thumbnails: [UUID: Data] = [:]
    private(set) var previewSession = 0
    private(set) var shortcut: ClipboardShortcut
    private(set) var collectionPause: ClipboardCollectionPause?
    private(set) var excludedApplications: [ClipboardExcludedApplication] = []
    private(set) var ignoresConfidentialCopies: Bool
    private(set) var settingsMessage: LocalizedStringResource?
    private(set) var readStatus = PasteboardClient.ReadStatus.available
    private(set) var invalidCollectionSettings: Set<ClipboardPreferences.CollectionSetting> = []
    private var storageMessage: LocalizedStringResource?
    private var mutationMessage: LocalizedStringResource?
    private var cleanupMessage: LocalizedStringResource?
    private var searchMessage: LocalizedStringResource?
    private var thumbnailMessage: LocalizedStringResource?
    private var recognitionMessage: LocalizedStringResource?
    private(set) var archiveFailure: LocalizedStringResource?
    private(set) var shortcutMessage: LocalizedStringResource?

    @ObservationIgnored private let pasteboard: PasteboardClient
    @ObservationIgnored private let pasteTarget = AppKitPasteTarget()
    @ObservationIgnored private let panel = ClipboardPanelController()
    @ObservationIgnored let previewRequests = ClipboardPreviewRequests()
    @ObservationIgnored let previewPlayback = ClipboardPreviewPlayback()
    @ObservationIgnored private let preferences: ClipboardPreferences
    @ObservationIgnored private var store: (any ClipboardHistoryStore)?
    @ObservationIgnored private var collectionTask: Task<Void, Never>?
    @ObservationIgnored private var lastInvalidFileSelectionChangeCount: Int?
    @ObservationIgnored private var recognitionTask: Task<Void, Never>?
    @ObservationIgnored private var recognitionRequested = false
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var entriesWithoutThumbnails: Set<UUID> = []
    @ObservationIgnored private var pageLimit = ClipboardHistoryQuery.pageSize
    @ObservationIgnored private var mostRecentID: UUID?
    @ObservationIgnored private var target: NSRunningApplication?
    @ObservationIgnored private var isPasting = false
    @ObservationIgnored private var lastReplayChangeCount: Int
    @ObservationIgnored private var mayHaveFileReplays = true
    @ObservationIgnored private var replayCleanupRequested = false
    @ObservationIgnored private var replayCleanupTask: Task<Void, Never>?
    @ObservationIgnored private lazy var hotKey = GlobalHotKey { [weak self] in
        self?.showHistory()
    }

    init(
        pasteboard: PasteboardClient = PasteboardClient(),
        preferences: ClipboardPreferences = ClipboardPreferences(),
        startsAutomatically: Bool = true
    ) {
        self.pasteboard = pasteboard
        self.preferences = preferences
        lastReplayChangeCount = pasteboard.changeCount
        shortcut = preferences.shortcut
        ignoresConfidentialCopies = preferences.ignoresConfidentialCopies
        do {
            collectionPause = try preferences.pause
        } catch {
            invalidCollectionSettings.insert(.pause)
        }
        do {
            excludedApplications = try preferences.excludedApplications
        } catch {
            invalidCollectionSettings.insert(.exclusions)
        }
        resumeIfPauseExpired(at: .now)
        guard startsAutomatically else { return }
        do {
            try hotKey.register(shortcut)
        } catch {
            shortcutMessage =
                "Ce raccourci est indisponible. L’historique reste accessible depuis le menu."
        }
        startCollection()
    }

    isolated deinit {
        collectionTask?.cancel()
        recognitionTask?.cancel()
        searchTask?.cancel()
    }

    func showHistory() {
        guard !isPasting else { return }
        readStatus = pasteboard.readStatus
        if !panel.isHistoryVisible {
            let frontmost = NSWorkspace.shared.frontmostApplication
            target = frontmost == NSRunningApplication.current ? nil : frontmost
            if selectedCollectionID != nil { selectCollection(nil) }
        }
        selectedID = mostRecentID ?? visibleEntries.first?.id
        panel.showHistory(ClipboardHistoryView(history: self)) { [weak self] in
            self?.endPreviewSession()
        }
        refreshSearch()
    }

    func dismissHistory() {
        panel.closeHistory()
        if let target,
            !target.isTerminated,
            NSWorkspace.shared.frontmostApplication == NSRunningApplication.current
        {
            NSApp.yieldActivation(to: target)
            _ = target.activate(from: NSRunningApplication.current, options: [])
        }
        target = nil
    }

    func requestPreview(for entry: ClipboardEntry) {
        guard let store, entries.contains(where: { $0.id == entry.id }) else { return }
        previewRequests.show(entry, store: store)
    }

    func hidePreview(for id: UUID) {
        previewRequests.hide(id)
        if previewPlayback.activeID == id { previewPlayback.stop() }
    }

    func endPreviewSession() {
        previewSession += 1
        previewPlayback.stop()
        previewRequests.reset()
    }

    func isLoadingPreview(for entry: ClipboardEntry) -> Bool {
        store != nil && ClipboardPreviewRequests.needsPreview(entry)
            && previewRequests.results[entry.id] == nil
    }

    func dismissArchiveFailure() {
        archiveFailure = nil
    }

    func moveSelection(by offset: Int) {
        let entries = visibleEntries
        guard !entries.isEmpty else { return }
        let current = entries.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(current + offset, 0), entries.count - 1)
        selectedID = entries[next].id
    }

    func pasteSelected() {
        guard let entry = visibleEntries.first(where: { $0.id == selectedID }) else { return }
        paste(entry)
    }

    var visibleEntries: [ClipboardEntry] { entries }
    var isFiltering: Bool { query.isFiltering }

    var historyMessage: LocalizedStringResource? {
        storageMessage ?? mutationMessage ?? searchMessage ?? thumbnailMessage ?? recognitionMessage
            ?? cleanupMessage
    }

    func selectCollection(_ id: UUID?) {
        selectedCollectionID = id
        changeFilters()
    }

    func showMoreEntries() {
        pageLimit += ClipboardHistoryQuery.pageSize
        refreshSearch()
    }

    func sourceName(_ identifier: String) -> String {
        if identifier == ClipboardHistoryQuery.unknownSource { return "Origine inconnue" }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        else { return identifier }
        return ClipboardSourceAppearance.displayName(for: url)
    }

    func setPinned(_ isPinned: Bool, for entry: ClipboardEntry) {
        manage(.setPinned(isPinned, entryID: entry.id))
    }

    func createCollection(named name: String) {
        manage(.createCollection(name))
    }

    func setMembership(
        _ isMember: Bool, for entry: ClipboardEntry, in collection: ClipboardCollection
    ) {
        manage(.setMembership(isMember, entryID: entry.id, collectionID: collection.id))
    }

    func deleteCollection(_ collection: ClipboardCollection) {
        manage(.deleteCollection(collection.id))
    }

    func deleteEntry(_ entry: ClipboardEntry, confirmingProtection: Bool = false) {
        manage(.deleteEntry(entry.id, confirmingProtection: confirmingProtection))
    }

    func clearUnprotectedEntries() {
        manage(.clearUnprotectedEntries)
    }

    func paste(_ entry: ClipboardEntry) {
        guard !isPasting else { return }
        isPasting = true
        let expectedChangeCount = pasteboard.changeCount
        let destination = target
        target = nil
        panel.closeHistory()
        Task {
            defer { isPasting = false }
            guard let store else { return }
            await replayCleanupTask?.value
            let replayID = UUID()
            let payload: ClipboardPayload
            do {
                payload = try await store.prepareReplay(for: entry.id, replayID: replayID)
                if payload.items.contains(where: { $0.fileURL != nil }) {
                    mayHaveFileReplays = true
                }
            } catch {
                panel.showNotice("Impossible de lire le contenu archivé de cette carte.")
                return
            }
            let paste = PasteClipboardEntry(pasteboard: pasteboard, pasteTarget: pasteTarget)
            let outcome = await paste(
                payload: payload, target: destination, replacing: expectedChangeCount
            )
            switch outcome {
            case .sent, .copied:
                lastReplayChangeCount = pasteboard.changeCount
                try? await store.removeReplays(exceptKeeping: replayID)
                if outcome == .copied {
                    panel.showNotice("Copié. Colle avec ⌘V.")
                }
                do {
                    try await store.markUsed(id: entry.id, at: .now)
                    refreshSearch()
                } catch {
                    if outcome == .sent {
                        panel.showNotice("Le classement de la carte n’a pas pu être mis à jour.")
                    }
                }
            case .failed:
                panel.showNotice("Impossible de copier cette carte.")
            case .clipboardChanged:
                panel.showNotice("Le presse-papiers a changé avant le collage.")
            }
        }
    }

    func setShortcut(_ candidate: ClipboardShortcut) {
        do {
            try hotKey.register(candidate)
            shortcut = candidate
            preferences.shortcut = candidate
            shortcutMessage = nil
        } catch {
            shortcutMessage = "Ce raccourci est indisponible. Le réglage précédent est conservé."
        }
    }

    var requiresCollectionSettingsRepair: Bool { !invalidCollectionSettings.isEmpty }
    var isCollectionPaused: Bool { collectionPause != nil || requiresCollectionSettingsRepair }

    func pauseCollection(_ pause: ClipboardCollectionPause) {
        guard !requiresCollectionSettingsRepair else { return }
        setCollectionPause(pause)
    }

    private func setCollectionPause(_ pause: ClipboardCollectionPause?) {
        collectionPause = pause
        preferences.setPause(pause)
    }

    func resumeCollection() {
        guard !requiresCollectionSettingsRepair else { return }
        pasteboard.ignoreCurrentContents()
        readStatus = pasteboard.readStatus
        setCollectionPause(nil)
    }

    func resetCollectionSetting(_ setting: ClipboardPreferences.CollectionSetting) {
        guard invalidCollectionSettings.contains(setting) else { return }
        switch setting {
        case .pause:
            setCollectionPause(.manual)
        case .exclusions:
            if !invalidCollectionSettings.contains(.pause) {
                setCollectionPause(.manual)
            }
            preferences.setExcludedApplications([])
            excludedApplications = []
        }
        invalidCollectionSettings.remove(setting)
    }

    func setIgnoresConfidentialCopies(_ value: Bool) {
        ignoresConfidentialCopies = value
        preferences.ignoresConfidentialCopies = value
    }

    func addExcludedApplication(at url: URL) {
        guard !invalidCollectionSettings.contains(.exclusions) else { return }
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
            settingsMessage = "Cette application ne fournit pas d’identifiant."
            return
        }
        settingsMessage = nil
        let id = identifier.lowercased()
        guard !excludedApplications.contains(where: { $0.id == id }) else { return }
        let name =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        excludedApplications.append(ClipboardExcludedApplication(id: id, name: name))
        excludedApplications.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        preferences.setExcludedApplications(excludedApplications)
    }

    func removeExcludedApplication(_ application: ClipboardExcludedApplication) {
        guard !invalidCollectionSettings.contains(.exclusions) else { return }
        excludedApplications.removeAll { $0.id == application.id }
        preferences.setExcludedApplications(excludedApplications)
        settingsMessage = nil
    }

    func openSystemSettings() {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.systempreferences")
        {
            NSWorkspace.shared.open(url)
        }
    }

    func startCollection(
        opening openStore: @escaping () async throws -> any ClipboardHistoryStore = {
            try await SwiftDataClipboardHistoryStore.open()
        }
    ) {
        guard collectionTask == nil else { return }
        collectionTask = Task { [weak self] in
            defer { self?.collectionTask = nil }
            do {
                let store = try await openStore()
                try await self?.loadHistory(from: store)
                self?.storageMessage = nil
                self?.startRecognition(using: store)
                let record = RecordClipboard(store: store)
                let (work, pending) = AsyncStream<CollectionWork>.makeStream()
                let worker = Task { [weak self] in
                    for await request in work {
                        guard !Task.isCancelled, self != nil else { return }
                        switch request {
                        case .archive(let copy, let date):
                            do {
                                try await record(copy, at: date)
                                self?.startRecognition(using: store)
                            } catch ClipboardHistoryStoreError.insufficientArchiveCapacity {
                                self?.archiveFailure =
                                    "Copie non archivée. L’espace disque disponible est insuffisant."
                            } catch {
                                self?.archiveFailure = "La nouvelle copie n’a pas été archivée."
                            }
                            self?.refreshSearch()
                        case .cleanReplays(let changeCount):
                            await self?.removeStaleReplays(using: store, changeCount: changeCount)
                        }
                    }
                }
                defer {
                    pending.finish()
                    worker.cancel()
                }
                while !Task.isCancelled {
                    guard self != nil else { return }
                    self?.collect(into: pending)
                    try await Task.sleep(for: .milliseconds(180))
                }
            } catch is CancellationError {
                return
            } catch ClipboardHistoryStoreError.storageInUse {
                self?.storageMessage = "L’historique est utilisé par une autre instance d’AppKite."
            } catch {
                self?.storageMessage = "Impossible d’ouvrir l’historique local."
            }
        }
    }

    func loadHistory(from store: any ClipboardHistoryStore) async throws {
        self.store = store
        try await reloadCollections(from: store)
        refreshSearch()
    }

    private func collect(into pending: AsyncStream<CollectionWork>.Continuation) {
        let date = Date.now
        if let copy = pollForCopy(at: date) {
            pending.yield(.archive(copy, date))
        }
        let changeCount = pasteboard.changeCount
        if !isPasting, mayHaveFileReplays, !replayCleanupRequested,
            changeCount != lastReplayChangeCount
        {
            replayCleanupRequested = true
            pending.yield(.cleanReplays(changeCount: changeCount))
        }
    }

    private func removeStaleReplays(using store: any ClipboardHistoryStore, changeCount: Int) async
    {
        defer { replayCleanupRequested = false }
        guard !isPasting, mayHaveFileReplays, changeCount != lastReplayChangeCount,
            pasteboard.isCurrent(changeCount: changeCount)
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

    func pollForCopy(at date: Date = .now) -> ClipboardCopy? {
        resumeIfPauseExpired(at: date)
        defer { readStatus = pasteboard.readStatus }
        guard !isCollectionPaused else { return nil }
        let copy = pasteboard.pollPayload(ignoringConfidentialCopies: ignoresConfidentialCopies) {
            source in
            let id = source.lowercased()
            return excludedApplications.contains { $0.id == id }
        }
        if let changeCount = pasteboard.invalidFileSelectionChangeCount,
            changeCount != lastInvalidFileSelectionChangeCount
        {
            lastInvalidFileSelectionChangeCount = changeCount
            archiveFailure = "La sélection de fichiers n’a pas été archivée."
        }
        return copy
    }

    private func resumeIfPauseExpired(at date: Date) {
        if let collectionPause, !collectionPause.isActive(at: date) {
            resumeCollection()
        }
    }

    private func manage(_ action: ManageClipboardHistory.Action) {
        guard let store else { return }
        Task {
            defer { refreshSearch() }
            do {
                try await ManageClipboardHistory(store: store)(action)
            } catch ClipboardHistoryStoreError.archiveCleanupDeferred {
                mutationMessage = nil
                cleanupMessage =
                    "Suppression enregistrée. Le nettoyage des fichiers sera retenté au prochain lancement."
                return
            } catch {
                mutationMessage = "Impossible de modifier l’historique."
                return
            }
            do {
                try await reloadCollections(from: store)
                mutationMessage = nil
            } catch {
                mutationMessage =
                    "Modification enregistrée. Impossible d’actualiser les collections."
            }
        }
    }

    private func reloadCollections(from store: any ClipboardHistoryStore) async throws {
        collections = try await store.collections()
        if let selectedCollectionID, !collections.contains(where: { $0.id == selectedCollectionID })
        {
            selectCollection(nil)
        }
    }

    private var query: ClipboardHistoryQuery {
        ClipboardHistoryQuery(
            text: searchText, kind: selectedKind, source: selectedSource,
            collection: selectedCollectionID, limit: pageLimit
        )
    }

    private func changeFilters() {
        endPreviewSession()
        pageLimit = ClipboardHistoryQuery.pageSize
        entries = []
        thumbnails = [:]
        entriesWithoutThumbnails.removeAll()
        selectedID = nil
        mostRecentID = nil
        hasMoreEntries = false
        refreshSearch()
    }

    private func refreshSearch() {
        guard let store else { return }
        searchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        let query = query
        isSearching = true
        searchTask = Task { [weak self] in
            let result: ClipboardHistoryResults
            do {
                result = try await SearchClipboardHistory(store: store)(query)
                try Task.checkCancellation()
            } catch is CancellationError {
                return
            } catch {
                guard self?.searchGeneration == generation else { return }
                self?.isSearching = false
                self?.searchMessage = "Impossible de rechercher dans l’historique."
                return
            }
            guard self?.searchGeneration == generation else { return }
            self?.searchMessage = nil
            self?.apply(result)

            do {
                let ids = self?.pendingThumbnailIDs(in: result.entries) ?? []
                let batchSize = ClipboardHistoryQuery.pageSize
                for offset in stride(from: 0, to: ids.count, by: batchSize) {
                    let batch = Array(ids[offset..<min(offset + batchSize, ids.count)])
                    let thumbnails = try await store.thumbnails(for: batch)
                    try Task.checkCancellation()
                    guard let self, self.searchGeneration == generation else { return }
                    self.entriesWithoutThumbnails.formUnion(
                        batch.lazy.filter { thumbnails[$0] == nil })
                    if !thumbnails.isEmpty {
                        self.thumbnails.merge(thumbnails, uniquingKeysWith: { _, new in new })
                    }
                }
                self?.thumbnailMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard self?.searchGeneration == generation else { return }
                self?.thumbnailMessage = "Impossible de charger certaines vignettes."
            }
        }
    }

    private func pendingThumbnailIDs(in entries: [ClipboardEntry]) -> [UUID] {
        entries.compactMap { entry in
            switch entry.kind {
            case .image, .pdf, .mixed, .spreadsheet:
                thumbnails[entry.id] == nil && !entriesWithoutThumbnails.contains(entry.id)
                    ? entry.id : nil
            default:
                nil
            }
        }
    }

    private func apply(_ result: ClipboardHistoryResults) {
        let visibleIDs = Set(result.entries.map(\.id))
        for entry in entries where !visibleIDs.contains(entry.id) {
            previewRequests.remove(entry.id)
            if previewPlayback.activeID == entry.id { previewPlayback.stop() }
        }
        entries = result.entries
        thumbnails = thumbnails.filter { visibleIDs.contains($0.key) }
        entriesWithoutThumbnails.formIntersection(visibleIDs)
        sourceIdentifiers = result.sourceIdentifiers
        mostRecentID = result.mostRecentID
        hasMoreEntries = result.hasMoreEntries
        hasUnprotectedEntries = result.canClearHistory
        isSearching = false
        if !entries.contains(where: { $0.id == selectedID }) {
            selectedID = result.mostRecentID
        }
    }

    private func startRecognition(using store: any ClipboardHistoryStore) {
        recognitionRequested = true
        guard recognitionTask == nil else { return }
        recognitionTask = Task(priority: .utility) { [weak self] in
            defer { self?.recognitionTask = nil }
            do {
                var changed = false
                while self?.recognitionRequested == true {
                    self?.recognitionRequested = false
                    while try await store.indexNextPendingEntry() {
                        changed = true
                        try Task.checkCancellation()
                        if self?.isFiltering == true, self?.isSearching == false {
                            self?.refreshSearch()
                        }
                        guard self != nil else { return }
                    }
                }
                if changed { self?.refreshSearch() }
                self?.recognitionMessage = nil
            } catch is CancellationError {
                return
            } catch {
                self?.recognitionMessage = "Impossible de terminer l’indexation de l’historique."
            }
        }
    }
}

#if DEBUG
    extension ClipboardHistoryState {
        static var preview: ClipboardHistoryState {
            let defaults = UserDefaults(suiteName: "AppKite.ClipboardHistoryPreview")!
            let pasteboard = NSPasteboard(name: .init("AppKite.ClipboardHistoryPreview"))
            let history = ClipboardHistoryState(
                pasteboard: PasteboardClient(pasteboard: pasteboard),
                preferences: ClipboardPreferences(defaults: defaults),
                startsAutomatically: false
            )
            let collection = ClipboardCollection(id: UUID(), name: "Projet")
            let photoURL = URL(
                fileURLWithPath: "/System/Library/Desktop Pictures/.thumbnails/The Lake Light.heic")
            let photo = NSImage(contentsOf: photoURL)?.tiffRepresentation
            let recent = ClipboardEntry(
                id: UUID(), text: "Photo du lac", sourceBundleIdentifier: "com.apple.Preview",
                lastUsedAt: .now, kind: .image, thumbnail: photo
            )
            let pinned = ClipboardEntry(
                id: UUID(), text: "Notes de réunion\n• Relire la maquette\n• Envoyer les captures",
                sourceBundleIdentifier: "com.apple.TextEdit",
                lastUsedAt: .now.addingTimeInterval(-300), isPinned: true
            )
            let color = ClipboardEntry(
                id: UUID(), text: "#3B82F6", sourceBundleIdentifier: nil,
                lastUsedAt: .now.addingTimeInterval(-600), isPinned: true, kind: .color
            )
            let link = ClipboardEntry(
                id: UUID(), text: "https://developer.apple.com/design/human-interface-guidelines/",
                sourceBundleIdentifier: nil,
                lastUsedAt: .now.addingTimeInterval(-55),
                kind: .link, isRemote: true
            )
            let folder = ClipboardEntry(
                id: UUID(), text: "Dossier Projet\nBudget.csv",
                sourceBundleIdentifier: "com.apple.finder",
                lastUsedAt: .now.addingTimeInterval(-120),
                collectionIDs: [collection.id], kind: .files
            )
            let table = ClipboardEntry(
                id: UUID(), text: "Projet\tBudget\nAppKite\t240 €\nDocumentation\t60 €",
                sourceBundleIdentifier: "com.apple.Numbers",
                lastUsedAt: .now.addingTimeInterval(-160),
                kind: .spreadsheet,
                tablePreviewRows: [
                    ["Projet", "Budget"], ["AppKite", "240 €"], ["Documentation", "60 €"],
                ]
            )
            let richText = ClipboardEntry(
                id: UUID(), text: "Compte rendu\nLa nouvelle version est prête pour les essais.",
                sourceBundleIdentifier: "com.apple.TextEdit",
                lastUsedAt: .now.addingTimeInterval(-190),
                kind: .richText
            )
            history.collections = [collection]
            let mixed = ClipboardEntry(
                id: UUID(), text: "Notes de projet\nCapture.png",
                sourceBundleIdentifier: "com.apple.Notes",
                lastUsedAt: .now.addingTimeInterval(-240), kind: .mixed
            )
            let pdf = ClipboardEntry(
                id: UUID(), text: "Compte rendu.pdf",
                sourceBundleIdentifier: "com.apple.Preview",
                lastUsedAt: .now.addingTimeInterval(-300), kind: .pdf
            )
            let audio = ClipboardEntry(
                id: UUID(), text: "Note vocale.m4a", sourceBundleIdentifier: "com.apple.finder",
                lastUsedAt: .now.addingTimeInterval(-45), kind: .files
            )
            if let photo, let bitmap = NSBitmapImageRep(data: photo),
                let png = bitmap.representation(using: .png, properties: [:])
            {
                let picture = ClipboardPreview.Picture(
                    png: png, pixelWidth: bitmap.pixelsWide, pixelHeight: bitmap.pixelsHigh)
                history.previewRequests.seed(
                    .init(kind: .image, content: .picture(picture), format: "Image"), for: recent.id
                )
                history.previewRequests.seed(
                    .init(
                        kind: .folder,
                        content: .mosaic(
                            tiles: [
                                .init(name: "Lac.heic", picture: picture),
                                .init(name: "Budget.csv", picture: nil),
                            ], count: 2),
                        name: "Dossier Projet"
                    ), for: folder.id)
            }
            history.previewRequests.seed(
                .init(
                    kind: .audio,
                    content: .waveform(
                        (0..<48).map { index in
                            0.2 + 0.75 * abs(sin(Float(index) * 0.28) * cos(Float(index) * 0.11))
                        }),
                    name: "Note vocale.m4a", format: "M4A", byteCount: 612_000,
                    media: .init(kind: .audio, url: URL(fileURLWithPath: "/dev/null"), duration: 36)
                ), for: audio.id)
            history.entries = [
                pinned, color, recent, audio, folder, table, richText, link, mixed, pdf,
            ]
            history.selectedID = recent.id
            history.sourceIdentifiers = [
                ClipboardHistoryQuery.unknownSource, "com.apple.TextEdit", "com.apple.Safari",
                "com.apple.finder", "com.apple.Numbers", "com.apple.Notes", "com.apple.Preview",
            ]
            history.hasUnprotectedEntries = true
            return history
        }
    }
#endif
