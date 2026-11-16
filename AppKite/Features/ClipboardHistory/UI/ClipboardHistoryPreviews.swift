import SwiftUI

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
