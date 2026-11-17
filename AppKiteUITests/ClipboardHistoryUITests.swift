import AppKit
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
    func testArchivedAudioPlaysInsideTheCardAfterOriginalRemoval() throws {
        continueAfterFailure = false
        let fixture = try IsolatedAppKite(test: self)
        let audio = fixture.directory.appending(path: "Note vocale.wav")
        try silentWave(seconds: 20).write(to: audio)
        let app = fixture.launch()
        openHistory(in: app)

        fixture.pasteboard.clearContents()
        XCTAssertTrue(fixture.pasteboard.writeObjects([audio as NSURL]))
        let play = app.buttons["clipboard-media-playback"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 12))
        try FileManager.default.removeItem(at: audio)

        app.terminate()
        fixture.launch()
        openHistory(in: app)
        XCTAssertTrue(play.waitForExistence(timeout: 12))
        XCTAssertEqual(play.value as? String, "Arrêté")
        play.click()
        let playing = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "En cours de lecture"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 5), .completed)
        XCTAssertTrue(app.textFields["clipboard-history-search"].exists)

        app.typeKey(.escape, modifierFlags: [])
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        openHistory(in: app)
        XCTAssertTrue(play.waitForExistence(timeout: 12))
        XCTAssertEqual(play.value as? String, "Arrêté")
    }

    @MainActor
    func testArchivedGIFPlaysAfterOriginalRemovalAndRelaunch() throws {
        try verifyArchivedPlayback(of: "Animation", fileExtension: "gif")
    }

    @MainActor
    func testArchivedMoviePlaysAfterOriginalRemovalAndRelaunch() throws {
        try verifyArchivedPlayback(of: "Capture", fileExtension: "mov")
    }

    @MainActor
    private func verifyArchivedPlayback(of name: String, fileExtension: String) throws {
        continueAfterFailure = false
        let bundle = Bundle(for: Self.self)
        let media = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: fileExtension)
                ?? bundle.url(
                    forResource: name, withExtension: fileExtension, subdirectory: "PreviewFixtures"
                ))
        let fixture = try IsolatedAppKite(test: self)
        let original = fixture.directory.appending(path: media.lastPathComponent)
        try FileManager.default.copyItem(at: media, to: original)
        let app = fixture.launch()
        openHistory(in: app)

        fixture.pasteboard.clearContents()
        XCTAssertTrue(fixture.pasteboard.writeObjects([original as NSURL]))
        let play = app.buttons["clipboard-media-playback"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 12))
        try FileManager.default.removeItem(at: original)

        app.terminate()
        fixture.launch()
        openHistory(in: app)
        XCTAssertTrue(play.waitForExistence(timeout: 12))
        XCTAssertEqual(play.value as? String, "Arrêté")
        play.click()
        let playState = NSPredicate(format: "value == %@", "En cours de lecture")
        XCTAssertTrue(playState.evaluate(with: play))
        let finished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Arrêté"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 10), .completed)
        XCTAssertFalse(app.staticTexts["Lecture indisponible"].exists)
        XCTAssertTrue(app.textFields["clipboard-history-search"].exists)
    }

    private func silentWave(seconds: UInt32) -> Data {
        let sampleRate: UInt32 = 8_000
        let byteCount = sampleRate * seconds * 2
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ number: T) {
            var littleEndian = number.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        append(byteCount + 36)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(sampleRate)
        append(sampleRate * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(byteCount)
        data.append(Data(count: Int(byteCount)))
        return data
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
