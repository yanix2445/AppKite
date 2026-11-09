import SwiftUI

struct MenuBarView: View {
    let onQuit: () -> Void

    var body: some View {
        Button("Quitter AppKite", action: onQuit)
    }
}

#Preview("Action du menu") {
    MenuBarView(onQuit: {})
}
