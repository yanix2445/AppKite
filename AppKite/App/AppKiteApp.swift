//
//  AppKiteApp.swift
//  AppKite
//
//  Created by Yanis HARRAT on 07/11/2026.
//

import AppKit
import SwiftUI

@main
struct AppKiteApp: App {
    @State private var clipboardHistory = Self.makeHistory()

    private static func makeHistory() -> ClipboardHistoryState {
        #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return .preview }
            if let name = environment["APPKITE_UI_TEST_PASTEBOARD"] {
                let prefix = "AppKite.UITest."
                guard name.hasPrefix(prefix),
                    UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
                else {
                    return ClipboardHistoryState(
                        pasteboard: PasteboardClient(pasteboard: .withUniqueName()),
                        startsAutomatically: false)
                }
                return ClipboardHistoryState(
                    pasteboard: PasteboardClient(
                        pasteboard: NSPasteboard(name: .init(name)),
                        readAccessBehavior: { .alwaysAllow }))
            }
        #endif
        return ClipboardHistoryState()
    }

    var body: some Scene {
        let clipboardHistory = clipboardHistory
        MenuBarExtra("AppKite", systemImage: "paperplane") {
            MenuBarView(
                onOpenHistory: clipboardHistory.showHistory,
                collectionPause: clipboardHistory.collectionPause,
                requiresCollectionSettingsRepair: clipboardHistory.requiresCollectionSettingsRepair,
                onPause: clipboardHistory.pauseCollection,
                onResume: clipboardHistory.resumeCollection,
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        }
        .menuBarExtraStyle(.menu)

        Settings {
            ClipboardSettingsView(history: clipboardHistory)
        }
    }
}
