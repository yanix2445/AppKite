import AppKit
import SwiftUI

struct ClipboardSearchControlsView: View {
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
                .modifier(ClipboardToolbarMenuStyle(isActive: history.selectedKind != nil))
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
        .modifier(ClipboardToolbarMenuStyle(isActive: history.selectedSource != nil))
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
    var filterTitle: LocalizedStringKey {
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
}
