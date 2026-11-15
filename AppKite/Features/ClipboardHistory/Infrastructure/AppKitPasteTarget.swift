import AppKit
import CoreGraphics

@MainActor
final class AppKitPasteTarget {
    private var requestedPostingAccess = false

    func postPaste(
        to target: NSRunningApplication,
        whileClipboardIsCurrent: @MainActor () -> Bool
    ) async -> Bool {
        let current = NSRunningApplication.current
        let workspace = NSWorkspace.shared
        guard !target.isEqual(current), !target.isTerminated, target.processIdentifier > 0,
            let frontmost = workspace.frontmostApplication,
            frontmost.isEqual(current) || frontmost.isEqual(target),
            !Task.isCancelled, whileClipboardIsCurrent()
        else {
            return false
        }

        if !CGPreflightPostEventAccess(), !requestedPostingAccess {
            requestedPostingAccess = true
            _ = CGRequestPostEventAccess()
        }

        guard
            await restoreFocus(
                to: target, from: current, whileClipboardIsCurrent: whileClipboardIsCurrent),
            CGPreflightPostEventAccess(),
            let keyCode = ClipboardShortcut.keyCode(for: "v", modifiers: .command),
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(
                keyboardEventSource: nil, virtualKey: keyCode, keyDown: false),
            !Task.isCancelled, !target.isTerminated,
            workspace.frontmostApplication?.isEqual(target) == true,
            whileClipboardIsCurrent()
        else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(target.processIdentifier)
        keyUp.postToPid(target.processIdentifier)
        return true
    }

    private func restoreFocus(
        to target: NSRunningApplication,
        from current: NSRunningApplication,
        whileClipboardIsCurrent: @MainActor () -> Bool
    ) async -> Bool {
        let workspace = NSWorkspace.shared
        guard let frontmost = workspace.frontmostApplication, !target.isTerminated,
            !Task.isCancelled, whileClipboardIsCurrent()
        else { return false }
        if frontmost.isEqual(target) {
            return true
        }
        guard frontmost.isEqual(current) else { return false }

        NSApplication.shared.yieldActivation(to: target)
        guard target.activate(from: current) else { return false }

        let clock = ContinuousClock()
        let deadline = clock.now + .milliseconds(500)
        repeat {
            guard let frontmost = workspace.frontmostApplication, !target.isTerminated,
                !Task.isCancelled, whileClipboardIsCurrent()
            else { return false }
            if frontmost.isEqual(target) {
                return true
            }
            guard frontmost.isEqual(current) else { return false }
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                return false
            }
        } while clock.now < deadline

        return false
    }
}
