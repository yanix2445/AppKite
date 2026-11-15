import SwiftUI

struct MenuBarView: View {
    let onOpenHistory: () -> Void
    let collectionPause: ClipboardCollectionPause?
    let onPause: (ClipboardCollectionPause) -> Void
    let onResume: () -> Void
    let onQuit: () -> Void

    var body: some View {
        Button("Historique du presse-papiers", action: onOpenHistory)
        if let collectionPause {
            if case .until(let deadline) = collectionPause {
                Text("Collecte en pause jusqu’à \(deadline, format: .dateTime.hour().minute())")
            }
            Button("Reprendre la collecte", action: onResume)
        } else {
            Menu("Mettre la collecte en pause") {
                Button("Jusqu’à la reprise manuelle") { onPause(.manual) }
                Button("5 minutes") { pause(forMinutes: 5) }
                Button("15 minutes") { pause(forMinutes: 15) }
                Button("1 heure") { pause(forMinutes: 60) }
            }
        }
        SettingsLink {
            Text("Réglages du presse-papiers…")
        }
        Divider()
        Button("Quitter AppKite", action: onQuit)
    }

    private func pause(forMinutes minutes: TimeInterval) {
        onPause(.until(Date.now.addingTimeInterval(minutes * 60)))
    }
}

#Preview("Action du menu") {
    MenuBarView(
        onOpenHistory: {}, collectionPause: nil, onPause: { _ in }, onResume: {}, onQuit: {}
    )
}
