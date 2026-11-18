import AppKit

@MainActor
enum ClipboardHistoryComposition {
    static func makeHistory(
        pasteboard: PasteboardClient = PasteboardClient(),
        preferences: ClipboardPreferences = ClipboardPreferences(),
        startsAutomatically: Bool = true,
        renderPreview: @escaping RenderClipboardPreview = renderArchivedPreview,
        opening openStore: @escaping () async throws -> any ClipboardHistoryStore = {
            try await SwiftDataClipboardHistoryStore.open()
        }
    ) -> ClipboardHistoryState {
        let pasteTarget = AppKitPasteTarget()
        let collection = CollectClipboardHistory(
            source: pasteboard,
            preferences: .init(
                loadPause: { try preferences.pause }, savePause: preferences.setPause,
                loadExclusions: { try preferences.excludedApplications },
                saveExclusions: preferences.setExcludedApplications,
                loadIgnoresConfidentialCopies: { preferences.ignoresConfidentialCopies },
                saveIgnoresConfidentialCopies: { preferences.ignoresConfidentialCopies = $0 }),
            openStore: openStore)
        return ClipboardHistoryState(
            collection: collection,
            previewRequests: ClipboardPreviewRequests(render: renderPreview),
            shortcut: preferences.shortcut,
            saveShortcut: { preferences.shortcut = $0 },
            makePaste: { target in
                makePaste(pasteboard: pasteboard, pasteTarget: pasteTarget, target: target)
            },
            startsAutomatically: startsAutomatically)
    }

    nonisolated static func renderArchivedPreview(_ source: ClipboardPreviewSource) async
        -> ClipboardPreview?
    {
        await ClipboardPreviewRenderer.render(source, media: ClipboardMediaPreview.render)
    }

    static func makePaste(
        pasteboard: PasteboardClient,
        pasteTarget: AppKitPasteTarget = AppKitPasteTarget(),
        target: NSRunningApplication? = nil
    ) -> PasteClipboardEntry {
        PasteClipboardEntry(
            write: { payload, count in
                switch pasteboard.write(payload, replacing: count) {
                case .written(let written): .written(written)
                case .changed: .changed
                case .failed: .failed
                }
            },
            isCurrent: { pasteboard.isCurrent(changeCount: $0) },
            send: { isCurrent in
                guard let target else { return false }
                return await pasteTarget.postPaste(
                    to: target, whileClipboardIsCurrent: isCurrent)
            })
    }
    #if DEBUG
        static func makePreview() -> ClipboardHistoryState {
            let defaults = UserDefaults(suiteName: "AppKite.ClipboardHistoryPreview")!
            let board = NSPasteboard(name: .init("AppKite.ClipboardHistoryPreview"))
            let history = makeHistory(
                pasteboard: PasteboardClient(pasteboard: board),
                preferences: ClipboardPreferences(defaults: defaults),
                startsAutomatically: false, renderPreview: { _ in nil })
            history.seedPreview()
            return history
        }
    #endif
}
