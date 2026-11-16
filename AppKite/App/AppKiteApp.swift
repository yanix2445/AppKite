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
    @State private var clipboardHistory = ClipboardHistoryState()

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
