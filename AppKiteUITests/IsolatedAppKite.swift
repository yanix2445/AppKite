import AppKit
import XCTest

@MainActor
struct IsolatedAppKite {
    private let app: XCUIApplication
    private let historyPath: String
    let directory: URL
    let pasteboard: NSPasteboard

    init(test: XCTestCase) throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])

        let app = XCUIApplication()
        let boardName = "AppKite.UITest.\(UUID().uuidString)"
        let pasteboard = NSPasteboard(name: .init(boardName))
        app.launchEnvironment["CFFIXED_USER_HOME"] = home.path
        app.launchEnvironment["APPKITE_UI_TEST_PASTEBOARD"] = boardName
        test.addTeardownBlock {
            if app.state != .notRunning {
                app.terminate()
            }
            pasteboard.releaseGlobally()
            do {
                try FileManager.default.removeItem(at: home)
            } catch {
                XCTFail("Impossible de supprimer le dossier temporaire de test : \(error)")
            }
        }
        self.app = app
        directory = home
        self.pasteboard = pasteboard
        historyPath =
            home.appending(
                path: "Library/Application Support/AppKite/ClipboardHistory/history.store"
            ).path
    }

    @discardableResult
    func launch(file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        app.launch()
        let storeExists = XCTNSPredicateExpectation(
            predicate: NSPredicate { [historyPath] _, _ in
                FileManager.default.fileExists(atPath: historyPath)
            }, object: nil)
        XCTAssertEqual(
            XCTWaiter.wait(for: [storeExists], timeout: 5), .completed,
            "L’historique doit être créé dans le dossier temporaire de test.", file: file,
            line: line)
        return app
    }
}
