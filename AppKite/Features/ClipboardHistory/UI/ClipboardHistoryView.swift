import AppKit
import SwiftUI

private enum ClipboardHistoryFocus: Hashable {
    case cards
    case search
}

struct ClipboardHistoryView: View {
    static let preferredHeight: CGFloat = 300

    private enum Dialog {
        case createCollection
        case deleteCollection(ClipboardCollection)
        case deleteEntry(ClipboardEntry)
        case clearHistory

        var title: LocalizedStringKey {
            switch self {
            case .createCollection: "Nouvelle collection"
            case .deleteCollection: "Supprimer la collection ?"
            case .deleteEntry: "Supprimer définitivement cette carte ?"
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

    private var selectedEntry: ClipboardEntry? {
        history.visibleEntries.first { $0.id == history.selectedID }
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
        .onKeyPress("f", phases: .down) { key in
            guard dialog == nil, key.modifiers == .command else { return .ignored }
            focus = .search
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard dialog == nil, focus != .search else { return .ignored }
            history.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard dialog == nil, focus != .search else { return .ignored }
            history.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard dialog == nil, focus != .search else { return .ignored }
            pasteSelected()
            return .handled
        }
        .onKeyPress(.delete) {
            guard dialog == nil, focus != .search, let entry = selectedEntry else {
                return .ignored
            }
            delete(entry)
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

            ClipboardSearchControls(history: history, focus: $focus, onSubmit: pasteSelected)

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
            Button(action: pasteSelected) {
                commandLabel("Coller", symbol: "return", showLabel: showLabels)
            }
            .buttonStyle(.plain)
            .disabled(history.selectedID == nil)
            .help("Coller la carte sélectionnée (↩)")

            Button {
                if let selectedEntry { delete(selectedEntry) }
            } label: {
                commandLabel("Supprimer", symbol: "delete.left", showLabel: showLabels)
            }
            .buttonStyle(.plain)
            .disabled(selectedEntry == nil)
            .help("Supprimer la carte sélectionnée (⌫)")
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
        .clipboardToolbarMenu(isActive: selectedCollection != nil)
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
        .clipboardToolbarControl()
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
        if history.isCollectionPaused {
            Button(action: history.resumeCollection) {
                Label("Reprendre la collecte", systemImage: "play.fill")
                    .labelStyle(.iconOnly)
                    .clipboardToolbarControl(isActive: true)
            }
            .buttonStyle(.plain)
            .help("Reprendre la collecte")
            .accessibilityIdentifier("clipboard-history-paused")
        } else {
            Menu {
                Button("Jusqu’à la reprise manuelle") { history.pauseCollection(.manual) }
                ForEach([5, 15, 60], id: \.self) { minutes in
                    Button("\(minutes) min") {
                        history.pauseCollection(
                            .until(.now.addingTimeInterval(Double(minutes * 60))))
                    }
                }
            } label: {
                Label("Mettre la collecte en pause", systemImage: "pause.fill")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .clipboardToolbarControl()
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
                    let cardStep = ClipboardHistoryCard.width + 8
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
            .onChange(of: history.selectedID, initial: true) { _, selection in
                guard let selection, entries.contains(where: { $0.id == selection }) else { return }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                    proxy.scrollTo(selection)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card(for entry: ClipboardEntry, height: CGFloat) -> some View {
        let isSelected = entry.id == history.selectedID
        return Button {
            history.paste(entry)
        } label: {
            ClipboardHistoryCard(
                entry: entry, thumbnail: history.thumbnails[entry.id] ?? entry.thumbnail,
                height: height, isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("clipboard-card-\(entry.id.uuidString)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
}

private struct ClipboardSearchControls: View {
    @Bindable var history: ClipboardHistoryState
    let focus: FocusState<ClipboardHistoryFocus?>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            searchField
                .frame(minWidth: 150, idealWidth: 240, maxWidth: 240)

            ClipboardSourceMenu(history: history)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    filterChip(nil)
                    ForEach(ClipboardPayload.Kind.allCases, id: \.rawValue) { kind in
                        filterChip(kind)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                Menu {
                    Picker("Type de copie", selection: $history.selectedKind) {
                        Text("Tous les types").tag(nil as ClipboardPayload.Kind?)
                        ForEach(ClipboardPayload.Kind.allCases, id: \.rawValue) { kind in
                            Text(kind.title).tag(kind as ClipboardPayload.Kind?)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(
                        history.selectedKind?.filterTitle ?? "Type",
                        systemImage: "line.3.horizontal.decrease")
                }
                .clipboardToolbarMenu(isActive: history.selectedKind != nil)
                .accessibilityLabel("Type de copie")
                .accessibilityIdentifier("clipboard-kind-filter")
            }
            Spacer(minLength: 0)
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Rechercher", text: $history.searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("Rechercher dans l’historique")
                .focused(focus, equals: .search)
                .onSubmit(onSubmit)
                .onKeyPress(.downArrow) {
                    focus.wrappedValue = .cards
                    return .handled
                }
                .onKeyPress(.escape) {
                    focus.wrappedValue = .cards
                    return .handled
                }
                .accessibilityIdentifier("clipboard-history-search")

            if !history.searchText.isEmpty {
                Button {
                    history.searchText = ""
                    focus.wrappedValue = .search
                } label: {
                    Label("Effacer la recherche", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("clipboard-search-clear")
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.primary.opacity(0.09), in: .capsule)
    }

    private func filterChip(_ kind: ClipboardPayload.Kind?) -> some View {
        let active = history.selectedKind == kind
        return Button {
            history.selectedKind = kind
        } label: {
            Text(kind?.filterTitle ?? "Tout")
                .font(.system(.caption).weight(active ? .semibold : .medium))
                .foregroundStyle(active ? .white : .primary)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(
                    active ? Color(nsColor: .controlAccentColor) : .primary.opacity(0.075),
                    in: .capsule
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("clipboard-kind-\(kind?.rawValue ?? "all")")
    }
}

extension View {
    fileprivate func clipboardToolbarMenu(isActive: Bool) -> some View {
        self.menuStyle(.borderlessButton)
            .font(.caption.weight(.medium))
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                isActive ? Color.accentColor.opacity(0.14) : .primary.opacity(0.075),
                in: .capsule
            )
            .fixedSize()
    }

    fileprivate func clipboardToolbarControl(isActive: Bool = false) -> some View {
        self.font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .frame(width: 28, height: 28)
            .background(
                isActive ? Color.accentColor.opacity(0.14) : .primary.opacity(0.075),
                in: .circle
            )
    }
}

private struct ClipboardSourceMenu: View {
    @Bindable var history: ClipboardHistoryState

    var body: some View {
        Menu {
            Picker("Application d’origine", selection: $history.selectedSource) {
                Text("Toutes les applications").tag(nil as String?)
                ForEach(history.sourceIdentifiers, id: \.self) { identifier in
                    Text(verbatim: history.sourceName(identifier)).tag(identifier as String?)
                }
            }
            .pickerStyle(.inline)
        } label: {
            if let source = history.selectedSource {
                Text(verbatim: history.sourceName(source))
                    .lineLimit(1)
                    .frame(maxWidth: 120)
            } else {
                Text("Application")
            }
        }
        .clipboardToolbarMenu(isActive: history.selectedSource != nil)
        .help(history.selectedSource.map(history.sourceName) ?? "Application d’origine")
        .accessibilityLabel("Application d’origine")
        .accessibilityValue(
            history.selectedSource.map { Text(verbatim: history.sourceName($0)) }
                ?? Text("Toutes les applications")
        )
        .accessibilityIdentifier("clipboard-source-filter")
    }
}

extension ClipboardPayload.Kind {
    fileprivate var filterTitle: LocalizedStringKey {
        switch self {
        case .files: "Fichiers"
        case .spreadsheet: "Tableur"
        case .mixed: "Mixte"
        default: title
        }
    }

    fileprivate var title: LocalizedStringKey {
        switch self {
        case .text: "Texte"
        case .richText: "Texte enrichi"
        case .link: "Lien"
        case .image: "Image"
        case .files: "Fichiers et dossiers"
        case .spreadsheet: "Cellules de tableur"
        case .pdf: "PDF"
        case .color: "Couleur"
        case .mixed: "Contenu mixte"
        }
    }

    fileprivate var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .link: "link"
        case .image: "photo"
        case .files: "folder"
        case .spreadsheet: "tablecells"
        case .pdf: "doc.richtext"
        case .color: "eyedropper"
        case .mixed: "paperclip"
        }
    }

    fileprivate var cardHeaderTitle: LocalizedStringKey {
        switch self {
        case .text: "Texte brut"
        case .image: "Image copiée"
        case .files: "Fichier"
        default: filterTitle
        }
    }

    fileprivate var cardHeaderColor: Color {
        switch self {
        case .text, .richText: Color(red: 0.07, green: 0.40, blue: 0.74)
        case .link: Color(red: 0.11, green: 0.40, blue: 0.48)
        case .image: Color(red: 0.23, green: 0.70, blue: 0.85)
        case .files, .pdf: Color(red: 0.05, green: 0.34, blue: 0.65)
        case .spreadsheet: Color(red: 0.09, green: 0.42, blue: 0.30)
        case .color: Color(red: 0.12, green: 0.12, blue: 0.14)
        case .mixed: Color(red: 0.96, green: 0.73, blue: 0.10)
        }
    }

    fileprivate var cardHeaderInk: Color {
        switch self {
        case .image, .mixed: .black
        default: .white
        }
    }
}

private struct ClipboardHistoryCard: View {
    let entry: ClipboardEntry
    let thumbnail: Data?
    let height: CGFloat
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    static let width: CGFloat = 196
    private let shape = RoundedRectangle(cornerRadius: 14)
    private let headerHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            header
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            footer
        }
        .frame(width: Self.width, height: height)
        .background(
            colorScheme == .dark ? .white.opacity(0.09) : .white.opacity(0.52),
            in: shape
        )
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                lineWidth: isSelected ? 2.5 : 1
            )
            .allowsHitTesting(false)
        }
        .contentShape(shape)
    }

    private var header: some View {
        let source =
            entry.isRemote
            ? nil
            : ClipboardSourceAppearance.resolve(
                for: entry.sourceBundleIdentifier ?? entry.probableSourceBundleIdentifier)
        let isProbable = entry.sourceBundleIdentifier == nil && source != nil
        let ink = source?.headerInk ?? entry.kind.cardHeaderInk
        return HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.kind.cardHeaderTitle)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                HStack(spacing: 3) {
                    if entry.isRemote {
                        Text("Presse-papiers universel")
                        Text("·").accessibilityHidden(true)
                    } else if let source {
                        if isProbable {
                            Text("\(source.name) ?")
                                .accessibilityLabel("Origine probable : \(source.name)")
                                .help("Origine probable : \(source.name)")
                        } else {
                            Text(verbatim: source.name)
                        }
                        Text("·").accessibilityHidden(true)
                    }
                    Text(
                        entry.lastUsedAt,
                        format: .relative(presentation: .named, unitsStyle: .abbreviated)
                    )
                    .layoutPriority(1)
                }
                .font(.system(size: 10))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let source {
                Image(nsImage: source.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: headerHeight * 0.95, height: headerHeight * 0.95)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: entry.isRemote ? "iphone.and.arrow.forward" : entry.kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .background(entry.kind.cardHeaderInk.opacity(0.16), in: .rect(cornerRadius: 5))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(ink)
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .frame(height: headerHeight)
        .background(source?.headerColor ?? entry.kind.cardHeaderColor, in: .rect)
    }

    @ViewBuilder
    private var preview: some View {
        if entry.kind == .pdf, let thumbnail, let image = NSImage(data: thumbnail) {
            VStack(spacing: 5) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.primary.opacity(0.06), in: .rect(cornerRadius: 7))
                    .accessibilityHidden(true)
                if entry.text != "PDF" {
                    Text(verbatim: entry.text)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .padding(9)
        } else if let thumbnail, let image = NSImage(data: thumbnail) {
            GeometryReader { proxy in
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: entry.kind == .image ? .fill : .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .padding(entry.kind == .image ? 0 : 9)
            .accessibilityLabel(Text(verbatim: entry.text))
        } else if entry.kind == .color, let color = swatch {
            ZStack {
                color
                Text(verbatim: entry.text)
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(.black)
                    .background(.white.opacity(0.9), in: .rect(cornerRadius: 7))
            }
        } else if entry.kind == .files || entry.kind == .pdf || entry.kind == .image {
            VStack(spacing: 6) {
                Image(systemName: entry.kind.symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(verbatim: String(entry.text.prefix(400)))
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .padding(8)
        } else if entry.kind == .spreadsheet {
            tablePreview
        } else if entry.kind == .link, let url = URL(string: entry.text), let host = url.host {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: host).font(.callout.weight(.semibold))
                Text(verbatim: url.path.isEmpty ? entry.text : url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
        } else {
            Text(verbatim: String(entry.text.prefix(600)))
                .font(.system(size: 13, weight: entry.kind == .richText ? .medium : .regular))
                .lineSpacing(2)
                .lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
        }
    }

    private var tablePreview: some View {
        let rows = entry.text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .prefix(4).map {
                Array($0.split(separator: "\t", omittingEmptySubsequences: false).prefix(3))
            }
        return Grid(alignment: .leading, horizontalSpacing: 9, verticalSpacing: 5) {
            ForEach(rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(rows[row].indices, id: \.self) { column in
                        Text(verbatim: String(rows[row][column]))
                            .lineLimit(1)
                            .fontWeight(row == 0 ? .semibold : .regular)
                    }
                }
            }
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            switch entry.kind {
            case .text, .richText:
                let lines = entry.text.split(
                    omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                Text(lines.count == 1 ? "1 ligne" : "\(lines.count) lignes")
            case .link:
                Text(URL(string: entry.text)?.scheme?.uppercased() ?? "Lien")
            case .color:
                Text(swatch == nil ? "Couleur" : "sRGB")
            case .spreadsheet:
                let count = entry.text.split(whereSeparator: \.isNewline).count
                Text(count == 1 ? "1 ligne" : "\(count) lignes")
            case .image, .pdf:
                Text(verbatim: entry.text)
            case .files, .mixed:
                if !entry.collectionIDs.isEmpty {
                    Text("Dans une collection")
                }
            }
            Spacer(minLength: 0)
            if !entry.collectionIDs.isEmpty {
                Image(systemName: "folder").accessibilityLabel("Dans une collection")
            }
            if entry.isPinned {
                Image(systemName: "pin.fill").accessibilityLabel("Épinglée")
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 23)
    }

    private var swatch: Color? {
        let hex = entry.text.dropFirst()
        guard entry.text.hasPrefix("#"), hex.count == 6 || hex.count == 8,
            let value = UInt64(hex, radix: 16)
        else { return nil }
        let rgba = hex.count == 6 ? value << 8 | 255 : value
        return Color(
            .sRGB, red: Double((rgba >> 24) & 255) / 255,
            green: Double((rgba >> 16) & 255) / 255, blue: Double((rgba >> 8) & 255) / 255,
            opacity: Double(rgba & 255) / 255
        )
    }
}

#if DEBUG
    #Preview("Bandeau Liquid Glass", traits: .fixedLayout(width: 1_680, height: 300)) {
        ClipboardHistoryView(history: .preview)
            .environment(\.locale, Locale(identifier: "fr_FR"))
    }

    #Preview("Bandeau compact", traits: .fixedLayout(width: 780, height: 300)) {
        ClipboardHistoryView(history: .preview)
            .environment(\.locale, Locale(identifier: "fr_FR"))
    }

    #Preview("Bandeau sur le bureau", traits: .fixedLayout(width: 1_680, height: 496)) {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.11, blue: 0.27),
                    Color(red: 0.25, green: 0.13, blue: 0.35),
                    Color(red: 0.42, green: 0.17, blue: 0.21),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            ClipboardHistoryView(history: .preview)
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .frame(height: ClipboardHistoryView.preferredHeight)
                .padding(.horizontal, 12)
        }
        .preferredColorScheme(.dark)
    }
#endif
