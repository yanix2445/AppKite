//
//  AppKiteUITests.swift
//  AppKiteUITests
//
//  Created by Yanis HARRAT on 07/11/2026.
//

import XCTest

final class AppKiteUITests: XCTestCase {
    @MainActor
    func testMenuBarLaunchQuitAndRelaunch() {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launch()
        defer {
            if app.state != .notRunning {
                app.terminate()
            }
        }

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        XCTAssertEqual(app.statusItems.count, 1)
        XCTAssertFalse(app.windows.firstMatch.exists)
        statusItem.click()

        let quit = statusItem.menuItems["Quitter AppKite"]
        XCTAssertTrue(quit.waitForExistence(timeout: 5))
        XCTAssertEqual(statusItem.menuItems.count, 1)
        quit.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))

        app.launch()
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        XCTAssertEqual(app.statusItems.count, 1)
        statusItem.click()
        XCTAssertTrue(quit.waitForExistence(timeout: 5))
    }
}
