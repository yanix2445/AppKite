//
//  AppKiteUITests.swift
//  AppKiteUITests
//
//  Created by Yanis HARRAT on 07/11/2026.
//

import XCTest

final class AppKiteUITests: XCTestCase {
    @MainActor
    func testMenuBarLaunchQuitAndRelaunch() throws {
        continueAfterFailure = false

        let fixture = try IsolatedAppKite(test: self)
        let app = fixture.launch()

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        XCTAssertEqual(app.statusItems.count, 1)
        XCTAssertFalse(app.windows.firstMatch.exists)
        statusItem.click()

        let quit = statusItem.menuItems["Quitter AppKite"]
        XCTAssertTrue(quit.waitForExistence(timeout: 5))
        XCTAssertTrue(statusItem.menuItems["Historique du presse-papiers"].exists)
        XCTAssertTrue(statusItem.menuItems["Réglages du presse-papiers…"].exists)
        quit.click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))

        fixture.launch()
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        XCTAssertEqual(app.statusItems.count, 1)
        statusItem.click()
        XCTAssertTrue(quit.waitForExistence(timeout: 5))
    }

    @MainActor
    func testOpenHistoryFromMenu() throws {
        continueAfterFailure = false
        let fixture = try IsolatedAppKite(test: self)
        let app = fixture.launch()
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        XCTAssertFalse(app.windows.firstMatch.exists)

        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
        statusItem.click()
        let openHistory = statusItem.menuItems["Historique du presse-papiers"]
        XCTAssertTrue(openHistory.waitForExistence(timeout: 5))
        openHistory.click()

        assertHistoryReceivesKeyboardInput(in: app)
        XCTAssertEqual(app.statusItems.count, 1)

        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.textFields["clipboard-history-search"].exists)
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
    }

    @MainActor
    func testGlobalShortcutOpensHistoryFromFinder() throws {
        continueAfterFailure = false
        let fixture = try IsolatedAppKite(test: self)
        let app = fixture.launch()
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")

        XCTAssertTrue(app.statusItems.firstMatch.waitForExistence(timeout: 5))
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
        finder.typeKey("v", modifierFlags: [.shift, .option])

        assertHistoryReceivesKeyboardInput(in: app)
    }

    @MainActor
    private func assertHistoryReceivesKeyboardInput(in app: XCUIApplication) {
        let search = app.textFields["clipboard-history-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable)
        app.typeKey("f", modifierFlags: [.command])
        app.typeKey("a", modifierFlags: [])
        XCTAssertEqual(search.value as? String, "a")
    }
}
