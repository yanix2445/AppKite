import AppKit
import Observation

@Observable
final class ClipboardHistoryState {
    private(set) var entries: [ClipboardEntry] = []
    private(set) var focusedEntryID: UUID?
    private(set) var selectedIDs: Set<UUID> = []
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
    private var collectionPolicy: ClipboardCollectionPolicy
    var collectionPause: ClipboardCollectionPause? { collectionPolicy.pause }
    var excludedApplications: [ClipboardExcludedApplication] { collectionPolicy.exclusions }
    var ignoresConfidentialCopies: Bool { collectionPolicy.ignoresConfidentialCopies }
    var invalidCollectionSettings: Set<ClipboardCollectionPolicy.Setting> {
        collectionPolicy.invalidSettings
    }
    private(set) var settingsMessage: LocalizedStringResource?
    private(set) var readStatus = ClipboardReadStatus.available
    private var storageMessage: LocalizedStringResource?
    private var mutationMessage: LocalizedStringResource?
    private var cleanupMessage: LocalizedStringResource?
    private var searchMessage: LocalizedStringResource?
    private var thumbnailMessage: LocalizedStringResource?
    private var recognitionMessage: LocalizedStringResource?
    private(set) var archiveFailure: LocalizedStringResource?
    private(set) var shortcutMessage: LocalizedStringResource?

    @ObservationIgnored private let collection: CollectClipboardHistory
    @ObservationIgnored private let makePaste:
        @MainActor (NSRunningApplication?) -> PasteClipboardEntry
    @ObservationIgnored private let panel = ClipboardPanelController()
    @ObservationIgnored let previewRequests: ClipboardPreviewRequests
    @ObservationIgnored let previewPlayback = ClipboardPreviewPlayback()
    @ObservationIgnored private let saveShortcut: (ClipboardShortcut) -> Void
    @ObservationIgnored private var store: (any ClipboardHistoryStore)?
    @ObservationIgnored private var isOpeningStore = false
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var entriesWithoutThumbnails: Set<UUID> = []
    @ObservationIgnored private var pageLimit = ClipboardHistoryQuery.pageSize
    @ObservationIgnored private var mostRecentID: UUID?
    @ObservationIgnored private var matchingUnpinnedIDs: [UUID] = []
    @ObservationIgnored private var selectsAllAfterSearch = false
    @ObservationIgnored private var selectionAnchorID: UUID?
    @ObservationIgnored private var selectionBeforeRange: Set<UUID>?
    @ObservationIgnored private var allowsEmptySelection = false
    @ObservationIgnored private var target: NSRunningApplication?
    @ObservationIgnored private lazy var hotKey = GlobalHotKey { [weak self] in
        self?.showHistory()
    }

    init(
        collection: CollectClipboardHistory,
        previewRequests: ClipboardPreviewRequests,
        shortcut: ClipboardShortcut,
        saveShortcut: @escaping (ClipboardShortcut) -> Void,
        makePaste: @escaping @MainActor (NSRunningApplication?) -> PasteClipboardEntry,
        startsAutomatically: Bool
    ) {
        self.collection = collection
        self.previewRequests = previewRequests
        self.shortcut = shortcut
        self.saveShortcut = saveShortcut
        self.makePaste = makePaste
        collectionPolicy = collection.policy
        collection.onEvent = { [weak self] event in self?.receive(event) }
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
        collection.cancel()
        searchTask?.cancel()
    }

    func showHistory() {
        guard !collection.isPasting else { return }
        readStatus = collection.readStatus
        if !panel.isHistoryVisible {
            let frontmost = NSWorkspace.shared.frontmostApplication
            target = frontmost == NSRunningApplication.current ? nil : frontmost
            if selectedCollectionID != nil { selectCollection(nil) }
        }
        selectOnly(mostRecentID ?? visibleEntries.first?.id)
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
        selectsAllAfterSearch = false
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

    func moveSelection(by offset: Int, extending: Bool = false) {
        selectsAllAfterSearch = false
        let entries = visibleEntries
        guard !entries.isEmpty else { return }
        let current = entries.firstIndex { $0.id == focusedEntryID } ?? 0
        let next = min(max(current + offset, 0), entries.count - 1)
        guard extending else {
            selectOnly(entries[next].id)
            return
        }

        let anchor = entries.firstIndex { $0.id == selectionAnchorID } ?? current
        selectionAnchorID = entries[anchor].id
        let fixedSelection = selectionBeforeRange ?? selectedIDs.subtracting([entries[anchor].id])
        selectionBeforeRange = fixedSelection
        focusedEntryID = entries[next].id
        selectedIDs = fixedSelection.union(entries[min(anchor, next)...max(anchor, next)].map(\.id))
        allowsEmptySelection = false
    }

    func toggleSelection(_ entry: ClipboardEntry) {
        selectsAllAfterSearch = false
        focusedEntryID = entry.id
        selectionAnchorID = entry.id
        selectionBeforeRange = nil
        if selectedIDs.remove(entry.id) == nil {
            selectedIDs.insert(entry.id)
        }
        allowsEmptySelection = selectedIDs.isEmpty
    }

    func selectAllUnpinned() {
        let awaitingStore = isOpeningStore
        selectsAllAfterSearch = (isSearching || awaitingStore) && visibleEntries.isEmpty
        guard !selectsAllAfterSearch else { return }
        selectedIDs = Set(matchingUnpinnedIDs)
        if focusedEntryID.map(selectedIDs.contains) != true {
            focusedEntryID = visibleEntries.first { selectedIDs.contains($0.id) }?.id
        }
        selectionAnchorID = focusedEntryID
        selectionBeforeRange = nil
        allowsEmptySelection = selectedIDs.isEmpty
    }

    private func selectOnly(_ id: UUID?) {
        selectsAllAfterSearch = false
        focusedEntryID = id
        selectionAnchorID = id
        selectionBeforeRange = nil
        selectedIDs = id.map { [$0] } ?? []
        allowsEmptySelection = false
    }

    func pasteSelected() {
        if selectedIDs.count <= 1 {
            paste(ids: Array(selectedIDs))
            return
        }
        let pinned = visibleEntries.lazy.filter(\.isPinned).map(\.id)
        paste(ids: (Array(pinned) + matchingUnpinnedIDs).filter(selectedIDs.contains))
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

    func deleteEntries(_ ids: Set<UUID>) {
        manage(.deleteEntries(ids))
    }

    func clearUnprotectedEntries() {
        manage(.clearUnprotectedEntries)
    }

    func paste(_ entry: ClipboardEntry) {
        paste(ids: [entry.id])
    }

    private func paste(ids: [UUID]) {
        guard collection.startReplay(ids: ids, paste: makePaste(target)) else { return }
        target = nil
        panel.closeHistory()
    }

    func setShortcut(_ candidate: ClipboardShortcut) {
        do {
            try hotKey.register(candidate)
            shortcut = candidate
            saveShortcut(candidate)
            shortcutMessage = nil
        } catch {
            shortcutMessage = "Ce raccourci est indisponible. Le réglage précédent est conservé."
        }
    }

    var requiresCollectionSettingsRepair: Bool { !invalidCollectionSettings.isEmpty }
    var isCollectionPaused: Bool { collectionPolicy.isPaused }

    func pauseCollection(_ pause: ClipboardCollectionPause) { collection.pause(pause) }
    func resumeCollection() { collection.resume() }

    func resetCollectionSetting(_ setting: ClipboardCollectionPolicy.Setting) {
        collection.repair(setting)
    }

    func setIgnoresConfidentialCopies(_ value: Bool) {
        collection.setIgnoresConfidentialCopies(value)
    }

    func addExcludedApplication(at url: URL) {
        guard !invalidCollectionSettings.contains(.exclusions) else { return }
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
            settingsMessage = "Cette application ne fournit pas d’identifiant."
            return
        }
        settingsMessage = nil
        let id = identifier.lowercased()
        let name =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        collection.exclude(ClipboardExcludedApplication(id: id, name: name))
    }

    func removeExcludedApplication(_ application: ClipboardExcludedApplication) {
        guard !invalidCollectionSettings.contains(.exclusions) else { return }
        collection.removeExclusion(application)
        settingsMessage = nil
    }

    func openSystemSettings() {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.systempreferences")
        {
            NSWorkspace.shared.open(url)
        }
    }

    func startCollection(opening openStore: (() async throws -> any ClipboardHistoryStore)? = nil) {
        collection.start(opening: openStore)
    }

    func pollForCopy(at date: Date = .now) -> ClipboardCopy? {
        collection.pollForCopy(at: date)
    }

    private func receive(_ event: CollectClipboardHistory.Event) {
        switch event {
        case .opening:
            isOpeningStore = true
        case .storeOpened(let store):
            self.store = store
            isSearching = true
        case .ready(let initialCollections):
            isOpeningStore = false
            applyCollections(initialCollections)
            storageMessage = nil
            refreshSearch()
        case .openingFailed(let inUse):
            isOpeningStore = false
            selectsAllAfterSearch = false
            storageMessage =
                inUse
                ? "L’historique est utilisé par une autre instance d’AppKite."
                : "Impossible d’ouvrir l’historique local."
        case .collectionsFailed:
            isOpeningStore = false
            selectsAllAfterSearch = false
            storageMessage = "Impossible de charger les collections."
            refreshSearch()
        case .policyChanged(let policy):
            collectionPolicy = policy
        case .readStatusChanged(let status):
            readStatus = status
        case .archiveRejected(let reason):
            archiveFailure =
                switch reason {
                case .invalidSelection: "La sélection de fichiers n’a pas été archivée."
                case .insufficientCapacity:
                    "Copie non archivée. L’espace disque disponible est insuffisant."
                case .failed: "La nouvelle copie n’a pas été archivée."
                }
        case .historyChanged:
            refreshSearch()
        case .indexedEntry:
            if isFiltering, !isSearching { refreshSearch() }
        case .indexingFinished(let failed):
            recognitionMessage =
                failed ? "Impossible de terminer l’indexation de l’historique." : nil
        case .replayNotice(let notice):
            showReplayNotice(notice)
        }
    }

    private func showReplayNotice(_ notice: CollectClipboardHistory.ReplayNotice) {
        let message: LocalizedStringResource =
            switch notice {
            case .selectionTooLarge:
                "Sélection trop volumineuse. Colle les cartes en plusieurs fois."
            case .insufficientCapacity: "Espace disque insuffisant pour coller cette sélection."
            case .unreadable: "Impossible de lire le contenu archivé de la sélection."
            case .copied: "Copié. Colle avec ⌘V."
            case .rankingFailed: "Le classement de la sélection n’a pas pu être mis à jour."
            case .writeFailed: "Impossible de copier la sélection."
            case .clipboardChanged: "Le presse-papiers a changé avant le collage."
            }
        panel.showNotice(message)
    }

    func loadHistory(from store: any ClipboardHistoryStore) async throws {
        self.store = store
        isSearching = true
        do {
            try await reloadCollections(from: store)
        } catch {
            isSearching = false
            selectsAllAfterSearch = false
            throw error
        }
        refreshSearch()
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
        applyCollections(try await store.collections())
    }

    private func applyCollections(_ collections: [ClipboardCollection]) {
        self.collections = collections
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
        selectOnly(nil)
        mostRecentID = nil
        matchingUnpinnedIDs = []
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
                self?.selectsAllAfterSearch = false
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
        matchingUnpinnedIDs = result.matchingUnpinnedIDs
        hasMoreEntries = result.hasMoreEntries
        hasUnprotectedEntries = result.canClearHistory
        isSearching = false
        if selectsAllAfterSearch {
            selectAllUnpinned()
            return
        }
        if !selectedIDs.isSubset(of: visibleIDs) {
            let matchingIDs = visibleIDs.union(matchingUnpinnedIDs)
            selectedIDs.formIntersection(matchingIDs)
            selectionBeforeRange?.formIntersection(matchingIDs)
        }
        if selectedIDs.isEmpty && !allowsEmptySelection {
            selectOnly(result.mostRecentID)
        } else if focusedEntryID.map(visibleIDs.contains) != true {
            focusedEntryID = entries.first { selectedIDs.contains($0.id) }?.id
        }
        if selectionAnchorID.map(visibleIDs.contains) != true {
            selectionAnchorID = focusedEntryID
            selectionBeforeRange = nil
        }
    }

}

#if DEBUG
    extension ClipboardHistoryState {
        func seedPreview() {
            let history = self
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
            history.matchingUnpinnedIDs = history.entries.filter { !$0.isPinned }.map(\.id)
            history.selectOnly(recent.id)
            history.sourceIdentifiers = [
                ClipboardHistoryQuery.unknownSource, "com.apple.TextEdit", "com.apple.Safari",
                "com.apple.finder", "com.apple.Numbers", "com.apple.Notes", "com.apple.Preview",
            ]
            history.hasUnprotectedEntries = true
        }
    }
#endif
