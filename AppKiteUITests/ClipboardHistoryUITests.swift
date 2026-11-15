import XCTest

final class ClipboardHistoryUITests: XCTestCase {
    @MainActor
    func testCreateAndDeleteCollectionFromHistory() throws {
        continueAfterFailure = false

        let fixture = try IsolatedAppKite(test: self)
        let app = fixture.launch()

        openHistory(in: app)
        let collections = app.descendants(matching: .any)["clipboard-collections-menu"]
        XCTAssertTrue(collections.waitForExistence(timeout: 5))
        collections.click()
        let create = app.menuItems["Nouvelle collection…"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.click()

        let name = app.sheets.firstMatch.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeText("Projet de test")
        app.buttons["Créer"].click()

        collections.click()
        let project = app.menuItems["Projet de test"]
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        project.click()
        XCTAssertTrue(
            app.staticTexts["Aucune carte dans cette collection"].waitForExistence(timeout: 5))

        collections.click()
        let delete = app.menuItems["Supprimer la collection…"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.click()
        let confirm = app.buttons["clipboard-collection-delete-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()

        XCTAssertTrue(app.staticTexts["Aucune copie enregistrée"].waitForExistence(timeout: 5))
        collections.click()
        XCTAssertTrue(app.menuItems["Nouvelle collection…"].waitForExistence(timeout: 5))
        XCTAssertFalse(project.exists)
    }

    @MainActor
    func testSearchAndTypeFilterShowAnEmptyResult() throws {
        continueAfterFailure = false

        let fixture = try IsolatedAppKite(test: self)
        let app = fixture.launch()

        openHistory(in: app)
        let search = app.textFields["clipboard-history-search"]
        let empty = app.staticTexts["clipboard-search-empty"]
        let historyEmpty = app.staticTexts["Aucune copie enregistrée"]
        XCTAssertTrue(historyEmpty.waitForExistence(timeout: 5))
        search.click()
        search.typeText("facture")
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertFalse(historyEmpty.exists)

        app.buttons["clipboard-search-clear"].click()
        XCTAssertTrue(historyEmpty.waitForExistence(timeout: 5))
        let imageChip = app.buttons["clipboard-kind-image"]
        if imageChip.exists {
            imageChip.click()
        } else {
            app.descendants(matching: .any)["clipboard-kind-filter"].click()
            let image = app.menuItems["Image"]
            XCTAssertTrue(image.waitForExistence(timeout: 5))
            image.click()
        }
        XCTAssertTrue(empty.waitForExistence(timeout: 5))

        let allTypesChip = app.buttons["clipboard-kind-all"]
        if allTypesChip.exists {
            allTypesChip.click()
        } else {
            app.descendants(matching: .any)["clipboard-kind-filter"].click()
            let allTypes = app.menuItems["Tous les types"]
            XCTAssertTrue(allTypes.waitForExistence(timeout: 5))
            allTypes.click()
        }
        XCTAssertTrue(historyEmpty.waitForExistence(timeout: 5))
    }

    @MainActor
    private func openHistory(in app: XCUIApplication) {
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()
        let openHistory = statusItem.menuItems["Historique du presse-papiers"]
        XCTAssertTrue(openHistory.waitForExistence(timeout: 5))
        openHistory.click()
        XCTAssertTrue(app.textFields["clipboard-history-search"].waitForExistence(timeout: 5))
    }
}
