import Foundation

@MainActor
struct PasteClipboardEntry {
    enum Outcome: Equatable {
        case sent
        case copied
        case failed
        case clipboardChanged
    }

    enum WriteResult {
        case written(Int)
        case changed
        case failed
    }

    let write: @MainActor (ClipboardPayload, Int) -> WriteResult
    let isCurrent: @MainActor (Int) -> Bool
    let send: @MainActor (@escaping @MainActor () -> Bool) async -> Bool

    func callAsFunction(
        text: String, replacing expectedChangeCount: Int
    ) async -> Outcome {
        await callAsFunction(payload: .plainText(text), replacing: expectedChangeCount)
    }

    func callAsFunction(
        payload: ClipboardPayload, replacing expectedChangeCount: Int
    ) async -> Outcome {
        guard !Task.isCancelled else { return .failed }
        let changeCount: Int
        switch write(payload, expectedChangeCount) {
        case .written(let count): changeCount = count
        case .changed: return .clipboardChanged
        case .failed: return .failed
        }

        if await send({ self.isCurrent(changeCount) }) {
            return .sent
        }

        return isCurrent(changeCount) ? .copied : .clipboardChanged
    }
}
