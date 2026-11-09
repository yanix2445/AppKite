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
    var body: some Scene {
        MenuBarExtra("AppKite", systemImage: "paperplane") {
            MenuBarView {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
