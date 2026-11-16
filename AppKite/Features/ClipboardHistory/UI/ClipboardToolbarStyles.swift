import SwiftUI

struct ClipboardToolbarMenuStyle: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content.menuStyle(.borderlessButton)
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
}

struct ClipboardToolbarControlStyle: ViewModifier {
    var isActive = false

    func body(content: Content) -> some View {
        content.font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .frame(width: 28, height: 28)
            .background(
                isActive ? Color.accentColor.opacity(0.14) : .primary.opacity(0.075),
                in: .circle
            )
    }
}
