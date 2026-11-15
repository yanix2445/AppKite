import AppKit
import CoreGraphics
import SwiftUI

final class ClipboardPanelController: NSObject, NSWindowDelegate {
    private final class HistoryPanel: NSPanel {
        override var canBecomeKey: Bool { true }

        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
            // showHistory positions the panel inside the full display, including the Dock area.
            frameRect
        }
    }

    private var historyPanel: NSPanel?
    private var noticePanel: NSPanel?
    private var noticeTask: Task<Void, Never>?
    private var historyScreen: NSScreen?

    var isHistoryVisible: Bool {
        guard let panel = historyPanel else { return false }
        return panel.isVisible && panel.occlusionState.contains(.visible)
    }

    func showHistory(_ view: ClipboardHistoryView) {
        guard let screen = screenUnderPointer() else { return }
        historyScreen = screen
        noticePanel?.orderOut(nil)
        let area = screen.frame
        let frame = NSRect(
            x: area.minX + 12,
            y: area.minY,
            width: area.width - 24,
            height: min(ClipboardHistoryView.preferredHeight, area.height)
        )
        let panel = historyPanel ?? makeHistoryPanel(frame: frame)
        if !isHistoryVisible {
            panel.contentView = NSHostingView(rootView: ClipboardPanelEntrance(history: view))
        }
        panel.setFrame(frame, display: false)
        // This panel takes keyboard focus while the current application stays in front.
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func closeHistory() {
        guard let panel = historyPanel else { return }
        panel.orderOut(nil)
        panel.contentView = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel = notification.object as? HistoryPanel else { return }
        // A SwiftUI alert can briefly take focus from its parent panel.
        Task { @MainActor [weak self, weak panel] in
            guard let panel, panel.isVisible, !panel.isKeyWindow, panel.attachedSheet == nil
            else { return }
            self?.closeHistory()
        }
    }

    func showNotice(_ message: LocalizedStringResource) {
        guard let screen = historyScreen ?? screenUnderPointer() else { return }
        noticeTask?.cancel()
        noticePanel?.orderOut(nil)
        let frame = bottomFrame(on: screen, width: 360, height: 48)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = NSHostingView(
            rootView:
                Text(message)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassEffect(.regular, in: .capsule)
        )
        noticePanel = panel
        panel.orderFrontRegardless()
        noticeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            self?.noticePanel?.orderOut(nil)
            self?.noticePanel = nil
        }
    }

    private func makeHistoryPanel(frame: NSRect) -> NSPanel {
        let panel = HistoryPanel(
            contentRect: frame,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Historique du presse-papiers"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary,
        ]
        panel.delegate = self
        historyPanel = panel
        return panel
    }

    private func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private func bottomFrame(on screen: NSScreen, width: CGFloat, height: CGFloat) -> NSRect {
        let area = screen.visibleFrame
        let inset: CGFloat = 12
        let panelWidth = min(width, area.width - 2 * inset)
        let panelHeight = min(height, area.height - 2 * inset)
        return NSRect(
            x: area.midX - panelWidth / 2,
            y: area.minY + inset,
            width: panelWidth,
            height: panelHeight
        )
    }
}

private struct ClipboardPanelEntrance: View {
    let history: ClipboardHistoryView
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasEntered = false

    var body: some View {
        GeometryReader { geometry in
            history
                // Keep the window on this display, even when another display sits below it.
                .offset(y: hasEntered || reduceMotion ? 0 : geometry.size.height)
                .task {
                    if reduceMotion {
                        hasEntered = true
                    } else {
                        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.38)) {
                            hasEntered = true
                        }
                    }
                }
        }
    }
}
