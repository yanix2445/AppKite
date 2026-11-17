import AppKit
import SwiftUI

enum ClipboardHistoryFocus: Hashable {
    case cards
    case search
}

struct ClipboardHistoryView: View {
    static let preferredHeight: CGFloat = 300
    // AppKit can report the physical backspace key as ASCII DEL.
    private static let backspace = KeyEquivalent("\u{7f}")

    private enum Dialog {
        case createCollection
        case deleteCollection(ClipboardCollection)
        case deleteEntry(ClipboardEntry)
        case deleteEntries(Set<UUID>)
        case clearHistory

        var title: LocalizedStringKey {
            switch self {
            case .createCollection: "Nouvelle collection"
            case .deleteCollection: "Supprimer la collection ?"
            case .deleteEntry: "Supprimer définitivement cette carte ?"
            case .deleteEntries(let ids):
                ids.count == 1
                    ? "Supprimer définitivement cette carte ?"
                    : "Supprimer définitivement ces \(ids.count) cartes ?"
            case .clearHistory: "Vider l’historique ?"
            }
        }
    }

    let history: ClipboardHistoryState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: ClipboardHistoryFocus?
    @State private var dialog: Dialog?
    @State private var collectionName = ""

    private var selectedCollection: ClipboardCollection? {
        history.collections.first { $0.id == history.selectedCollectionID }
    }

    private var isDialogPresented: Binding<Bool> {
        Binding(
            get: { dialog != nil },
            set: { if !$0 { dialog = nil } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar

            if let accessMessage {
                HStack(spacing: 8) {
                    Label {
                        Text(accessMessage)
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                    }
                    .lineLimit(2)
                    Button("Ouvrir les Réglages Système", action: history.openSystemSettings)
                        .controlSize(.small)
                }
                .font(.callout)
            }

            if let message = history.historyMessage {
                Label {
                    Text(message)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }

            if let failure = history.archiveFailure {
                HStack(spacing: 8) {
                    Label {
                        Text(failure)
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                    }
                    .lineLimit(2)
                    Button(
                        "Masquer le message d’archivage", systemImage: "xmark",
                        action: history.dismissArchiveFailure
                    )
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                }
                .font(.callout)
            }

            let visibleEntries = history.visibleEntries
            if visibleEntries.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cardSections(visibleEntries)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(
            .regular.tint(colorScheme == .dark ? .black.opacity(0.28) : nil),
            in: .rect(cornerRadius: 28)
        )
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .cards)
        .onAppear { focus = .cards }
        .onDisappear { history.endPreviewSession() }
        .onKeyPress("f", phases: .down) { key in
            guard dialog == nil, key.modifiers == .command else { return .ignored }
            focus = .search
            return .handled
        }
        .onKeyPress("a", phases: .down) { key in
            guard dialog == nil, focus != .search, key.modifiers == .command else {
                return .ignored
            }
            history.selectAllUnpinned()
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { key in
            guard dialog == nil, focus != .search else { return .ignored }
            history.moveSelection(
                by: key.key == .leftArrow ? -1 : 1, extending: key.modifiers.contains(.command))
            return .handled
        }
        .onKeyPress(.return) {
            guard dialog == nil, focus != .search else { return .ignored }
            pasteSelected()
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward, Self.backspace], phases: .down) { _ in
            guard dialog == nil, focus != .search, !history.selectedIDs.isEmpty else {
                return .ignored
            }
            deleteSelected()
            return .handled
        }
        .onKeyPress(.escape) {
            guard dialog == nil else { return .ignored }
            if focus == .search {
                focus = .cards
            } else {
                history.dismissHistory()
            }
            return .handled
        }
        .alert(dialog?.title ?? "", isPresented: isDialogPresented, presenting: dialog) { dialog in
            dialogActions(dialog)
        } message: { dialog in
            dialogMessage(dialog)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            collectionsMenu
            toolbarDivider

            ClipboardSearchControlsView(history: history, focus: $focus, onSubmit: pasteSelected)

            ViewThatFits(in: .horizontal) {
                commands(showLabels: true)
                commands(showLabels: false)
            }

            toolbarDivider
            pauseControl
            actionsMenu
        }
        .controlSize(.small)
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 16)
            .accessibilityHidden(true)
    }

    private func commands(showLabels: Bool) -> some View {
        HStack(spacing: 6) {
            let selectedCount = history.selectedIDs.count
            if selectedCount > 1 || (selectedCount == 1 && history.focusedEntryID == nil) {
                Text(
                    selectedCount == 1
                        ? "1 carte sélectionnée" : "\(selectedCount) cartes sélectionnées"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("clipboard-selection-count")
            }

            Button(action: pasteSelected) {
                commandLabel("Coller", symbol: "return", showLabel: showLabels)
            }
            .buttonStyle(.plain)
            .disabled(history.selectedIDs.isEmpty)
            .help("Coller la sélection (↩)")

            Button(action: deleteSelected) {
                commandLabel("Supprimer", symbol: "delete.left", showLabel: showLabels)
            }
            .buttonStyle(.plain)
            .disabled(history.selectedIDs.isEmpty)
            .help("Supprimer la sélection (⌫)")
        }
        .fixedSize()
    }

    private var collectionsMenu: some View {
        Menu {
            Picker(
                "Collections",
                selection: Binding(
                    get: { history.selectedCollectionID },
                    set: history.selectCollection
                )
            ) {
                Text("Toutes les cartes").tag(nil as UUID?)
                    .accessibilityIdentifier("clipboard-collection-all")
                ForEach(history.collections) { collection in
                    Text(verbatim: collection.name)
                        .tag(collection.id as UUID?)
                        .accessibilityIdentifier(
                            "clipboard-collection-\(collection.id.uuidString)"
                        )
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Nouvelle collection…") {
                collectionName = ""
                dialog = .createCollection
            }
            .accessibilityIdentifier("clipboard-collection-create")
            if let selectedCollection {
                Button("Supprimer la collection…", role: .destructive) {
                    dialog = .deleteCollection(selectedCollection)
                }
                .accessibilityIdentifier("clipboard-collection-delete")
            }
        } label: {
            if let selectedCollection {
                Label {
                    Text(verbatim: selectedCollection.name)
                        .lineLimit(1)
                        .frame(maxWidth: 120)
                } icon: {
                    Image(systemName: "folder")
                }
            } else {
                Label("Collections", systemImage: "folder")
            }
        }
        .modifier(ClipboardToolbarMenuStyle(isActive: selectedCollection != nil))
        .accessibilityLabel("Collections")
        .help(selectedCollection?.name ?? "Collections")
        .accessibilityValue(
            selectedCollection.map { Text(verbatim: $0.name) } ?? Text("Toutes les cartes")
        )
        .accessibilityIdentifier("clipboard-collections-menu")
    }

    private var actionsMenu: some View {
        Menu {
            Button("Vider l’historique…", role: .destructive) {
                dialog = .clearHistory
            }
            .disabled(!history.hasUnprotectedEntries)
            .accessibilityIdentifier("clipboard-history-clear")
        } label: {
            Label("Actions de l’historique", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .modifier(ClipboardToolbarControlStyle())
        .help("Actions de l’historique")
        .accessibilityIdentifier("clipboard-history-actions-menu")
    }

    private func commandLabel(
        _ title: LocalizedStringKey, symbol: String, showLabel: Bool
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 17)
                .background(.primary.opacity(0.10), in: .rect(cornerRadius: 4))
                .accessibilityHidden(true)
            if showLabel {
                Text(title)
                    .font(.caption)
            }
        }
        .frame(minHeight: 28)
        .contentShape(.rect)
        .accessibilityLabel(Text(title))
    }

    @ViewBuilder
    private var pauseControl: some View {
        if history.requiresCollectionSettingsRepair {
            SettingsLink {
                Label(
                    "Collecte suspendue. Ouvrir les réglages à réparer.",
                    systemImage: "exclamationmark.triangle"
                )
                .labelStyle(.iconOnly)
                .modifier(ClipboardToolbarControlStyle(isActive: true))
            }
            .buttonStyle(.plain)
            .help("Collecte suspendue. Ouvrir les réglages à réparer.")
            .accessibilityIdentifier("clipboard-collection-settings-repair")
        } else if history.isCollectionPaused {
            Button(action: history.resumeCollection) {
                Label("Reprendre la collecte", systemImage: "play.fill")
                    .labelStyle(.iconOnly)
                    .modifier(ClipboardToolbarControlStyle(isActive: true))
            }
            .buttonStyle(.plain)
            .help("Reprendre la collecte")
            .accessibilityIdentifier("clipboard-history-paused")
        } else {
            Menu {
                ClipboardPauseOptionsView(compactLabels: true, onPause: history.pauseCollection)
            } label: {
                Label("Mettre la collecte en pause", systemImage: "pause.fill")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .modifier(ClipboardToolbarControlStyle())
            .help("Mettre la collecte en pause")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if history.isSearching {
            ProgressView("Recherche…")
                .controlSize(.small)
                .accessibilityIdentifier("clipboard-search-progress")
        } else if history.isFiltering {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.title2).accessibilityHidden(true)
                Text("Aucune carte ne correspond")
                    .accessibilityIdentifier("clipboard-search-empty")
            }
            .foregroundStyle(.secondary)
        } else {
            let message: LocalizedStringKey =
                selectedCollection == nil
                ? "Aucune copie enregistrée" : "Aucune carte dans cette collection"
            VStack(spacing: 8) {
                Image(systemName: "clipboard").font(.title2).accessibilityHidden(true)
                Text(message)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func pasteSelected() {
        guard dialog == nil else { return }
        history.pasteSelected()
    }

    private func delete(_ entry: ClipboardEntry) {
        if entry.isProtected {
            dialog = .deleteEntry(entry)
        } else {
            history.deleteEntry(entry)
        }
    }

    private func deleteSelected() {
        let ids = history.selectedIDs
        guard !ids.isEmpty else { return }
        if ids.count == 1, let entry = history.visibleEntries.first(where: { ids.contains($0.id) })
        {
            delete(entry)
        } else {
            dialog = .deleteEntries(ids)
        }
    }

    @ViewBuilder
    private func dialogActions(_ dialog: Dialog) -> some View {
        Button("Annuler", role: .cancel) {}
        switch dialog {
        case .createCollection:
            TextField("Nom", text: $collectionName)
                .accessibilityIdentifier("clipboard-collection-name")
            Button("Créer") {
                history.createCollection(named: collectionName)
            }
            .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("clipboard-collection-create-confirm")
        case .deleteCollection(let collection):
            Button("Supprimer", role: .destructive) {
                history.deleteCollection(collection)
            }
            .accessibilityIdentifier("clipboard-collection-delete-confirm")
        case .deleteEntry(let entry):
            Button("Supprimer", role: .destructive) {
                history.deleteEntry(entry, confirmingProtection: true)
            }
            .accessibilityIdentifier("clipboard-card-delete-confirm")
        case .deleteEntries(let ids):
            Button("Supprimer", role: .destructive) {
                history.deleteEntries(ids)
            }
            .accessibilityIdentifier("clipboard-cards-delete-confirm")
        case .clearHistory:
            Button("Vider l’historique", role: .destructive) {
                history.clearUnprotectedEntries()
            }
            .accessibilityIdentifier("clipboard-history-clear-confirm")
        }
    }

    @ViewBuilder
    private func dialogMessage(_ dialog: Dialog) -> some View {
        switch dialog {
        case .createCollection:
            EmptyView()
        case .deleteCollection:
            Text("Les cartes restent dans l’historique et dans leurs autres collections.")
        case .deleteEntry:
            Text("La carte sera retirée de l’historique et de ses collections.")
        case .deleteEntries:
            Text("La sélection sera retirée de l’historique et des collections.")
        case .clearHistory:
            Text("Les cartes épinglées ou classées dans une collection sont conservées.")
        }
    }

    private var accessMessage: LocalizedStringResource? {
        switch history.readStatus {
        case .available, .invalidFileSelection: nil
        case .denied: "Autorise l’accès au presse-papiers pour reprendre l’enregistrement"
        case .failed: "Impossible de lire la dernière copie. Vérifie l’accès au presse-papiers."
        }
    }

    private func cardSections(_ entries: [ClipboardEntry]) -> some View {
        let pinned = entries.filter(\.isPinned)
        let other = entries.filter { !$0.isPinned }
        return GeometryReader { geometry in
            let cardHeight = max(0, geometry.size.height - 10)
            HStack(alignment: .center, spacing: 8) {
                if !pinned.isEmpty {
                    let cardStep = ClipboardHistoryCardView.width + 8
                    let availableWidth =
                        other.isEmpty ? geometry.size.width : geometry.size.width * 0.4
                    let fittingCards = max(1, Int((availableWidth - 2) / cardStep))
                    let pinnedWidth = min(
                        geometry.size.width, CGFloat(min(pinned.count, fittingCards)) * cardStep + 2
                    )
                    cards(pinned, height: cardHeight, showsMore: other.isEmpty, inset: 5)
                        .frame(width: pinnedWidth)
                        .background(.primary.opacity(0.075), in: .rect(cornerRadius: 19))
                        .overlay {
                            RoundedRectangle(cornerRadius: 19)
                                .strokeBorder(.primary.opacity(0.10))
                                .allowsHitTesting(false)
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Épingles")
                }
                if !other.isEmpty {
                    cards(other, height: cardHeight, showsMore: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func cards(
        _ entries: [ClipboardEntry], height: CGFloat, showsMore: Bool, inset: CGFloat = 0
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(entries) { entry in
                        card(for: entry, height: height)
                            .id(entry.id)
                    }
                    if showsMore && history.hasMoreEntries {
                        Button(action: history.showMoreEntries) {
                            Label("Afficher plus", systemImage: "plus.circle")
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("clipboard-history-show-more")
                    }
                }
                .padding(inset)
            }
            .scrollIndicators(.never)
            .onChange(of: history.focusedEntryID, initial: true) { _, entryID in
                guard let entryID, entries.contains(where: { $0.id == entryID }) else { return }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                    proxy.scrollTo(entryID)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card(for entry: ClipboardEntry, height: CGFloat) -> some View {
        let isSelected = history.selectedIDs.contains(entry.id)
        let preview: ClipboardPreview? =
            switch history.previewRequests.results[entry.id] {
            case .ready(let preview): preview
            default: nil
            }
        return ZStack {
            Button {
                activateCard(entry) {
                    history.paste(entry)
                }
            } label: {
                ClipboardHistoryCardView(
                    entry: entry, thumbnail: history.thumbnails[entry.id] ?? entry.thumbnail,
                    height: height, isSelected: isSelected, archivedPreview: preview,
                    isLoadingPreview: history.isLoadingPreview(for: entry),
                    playback: history.previewPlayback
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("clipboard-card-\(entry.id.uuidString)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAction(named: isSelected ? Text("Désélectionner") : Text("Sélectionner"))
            {
                toggleSelection(entry)
            }
            if let media = preview?.media {
                ClipboardPlaybackButton(
                    playback: history.previewPlayback, media: media, entryID: entry.id
                ) {
                    activateCard(entry) {
                        history.previewPlayback.toggle(media, for: entry.id)
                    }
                }
            }
        }
        .task(id: history.previewSession) { history.requestPreview(for: entry) }
        .onDisappear { history.hidePreview(for: entry.id) }
        .contextMenu {
            let pinTitle: LocalizedStringKey = entry.isPinned ? "Désépingler" : "Épingler"
            Button(pinTitle) {
                history.setPinned(!entry.isPinned, for: entry)
            }
            .accessibilityIdentifier("clipboard-card-pin")

            if !history.collections.isEmpty {
                Menu("Collections") {
                    ForEach(history.collections) { collection in
                        Toggle(
                            isOn: Binding(
                                get: { entry.collectionIDs.contains(collection.id) },
                                set: { history.setMembership($0, for: entry, in: collection) }
                            )
                        ) {
                            Text(verbatim: collection.name)
                        }
                        .accessibilityIdentifier(
                            "clipboard-card-membership-\(collection.id.uuidString)"
                        )
                    }
                }
            }

            Divider()
            let deleteTitle: LocalizedStringKey = entry.isProtected ? "Supprimer…" : "Supprimer"
            Button(deleteTitle, role: .destructive) { delete(entry) }
                .accessibilityIdentifier("clipboard-card-delete")
        }
    }

    private func activateCard(_ entry: ClipboardEntry, action: () -> Void) {
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            toggleSelection(entry)
        } else {
            action()
        }
    }

    private func toggleSelection(_ entry: ClipboardEntry) {
        history.toggleSelection(entry)
        focus = .cards
    }
}
