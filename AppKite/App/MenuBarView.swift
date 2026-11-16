import SwiftUI

struct MenuBarView: View {
    let onOpenHistory: () -> Void
    let collectionPause: ClipboardCollectionPause?
    let requiresCollectionSettingsRepair: Bool
    let onPause: (ClipboardCollectionPause) -> Void
    let onResume: () -> Void
    let onQuit: () -> Void

    var body: some View {
        Button("Historique du presse-papiers", action: onOpenHistory)
        if requiresCollectionSettingsRepair {
            Text("Collecte suspendue. Réglages à réparer.")
        } else if let collectionPause {
            if case .until(let deadline) = collectionPause {
                Text("Collecte en pause jusqu’à \(deadline, format: .dateTime.hour().minute())")
            }
            Button("Reprendre la collecte", action: onResume)
        } else {
            Menu("Mettre la collecte en pause") {
                ClipboardPauseOptionsView(onPause: onPause)
            }
        }
        SettingsLink {
            Text("Réglages du presse-papiers…")
        }
        Divider()
        Button("Quitter AppKite", action: onQuit)
    }
}

#Preview("Action du menu") {
    MenuBarView(
        onOpenHistory: {}, collectionPause: nil, requiresCollectionSettingsRepair: false,
        onPause: { _ in }, onResume: {}, onQuit: {}
    )
}
