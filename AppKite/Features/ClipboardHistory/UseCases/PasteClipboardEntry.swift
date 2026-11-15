import AppKit

@MainActor
struct PasteClipboardEntry {
    enum Outcome: Equatable {
        case sent
        case copied
        case failed
        case clipboardChanged
    }

    let pasteboard: PasteboardClient
    let pasteTarget: AppKitPasteTarget

    func callAsFunction(
        text: String, target: NSRunningApplication?, replacing expectedChangeCount: Int
    ) async -> Outcome {
        await callAsFunction(
            payload: .plainText(text), target: target, replacing: expectedChangeCount)
    }

    func callAsFunction(
        payload: ClipboardPayload, target: NSRunningApplication?, replacing expectedChangeCount: Int
    ) async -> Outcome {
        guard !Task.isCancelled else { return .failed }
        let changeCount: Int
        switch pasteboard.write(payload, replacing: expectedChangeCount) {
        case .written(let count): changeCount = count
        case .changed: return .clipboardChanged
        case .failed: return .failed
        }

        if let target,
            await pasteTarget.postPaste(
                to: target,
                whileClipboardIsCurrent: {
                    pasteboard.isCurrent(changeCount: changeCount)
                })
        {
            return .sent
        }

        return pasteboard.isCurrent(changeCount: changeCount) ? .copied : .clipboardChanged
    }
}
