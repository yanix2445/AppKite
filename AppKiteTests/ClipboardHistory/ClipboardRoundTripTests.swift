import AppKit
import Foundation
import Testing

@testable import AppKite

struct ClipboardRoundTripTests {
    @MainActor
    @Test func `Restored pasteboard access starts at the next new copy`() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var accessBehavior = NSPasteboard.AccessBehavior.alwaysAllow
        let client = PasteboardClient(
            pasteboard: pasteboard, readAccessBehavior: { accessBehavior })

        accessBehavior = .alwaysDeny
        pasteboard.clearContents()
        #expect(pasteboard.setString("Copie bloquée", forType: .string))
        #expect(client.poll() == nil)
        #expect(client.readStatus == .denied)

        accessBehavior = .alwaysAllow
        #expect(client.poll() == nil)
        #expect(client.readStatus == .available)

        pasteboard.clearContents()
        #expect(pasteboard.setString("Nouvelle copie", forType: .string))
        let copy = try #require(client.poll())
        #expect(copy.text == "Nouvelle copie")
    }

    @MainActor
    @Test func `Denial during a read discards the pending copy`() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var accessChecks = 0
        var allow = false
        let client = PasteboardClient(
            pasteboard: pasteboard,
            readAccessBehavior: {
                accessChecks += 1
                return allow || accessChecks < 4 ? .alwaysAllow : .alwaysDeny
            })
        pasteboard.clearContents()
        try #require(pasteboard.setString("Copie en cours", forType: .string))
        #expect(client.pollPayload() == nil)
        #expect(client.readStatus == .denied)
        allow = true
        #expect(client.pollPayload() == nil)
        pasteboard.clearContents()
        try #require(pasteboard.setString("Copie après reprise", forType: .string))
        #expect(client.poll()?.text == "Copie après reprise")
    }

    @MainActor
    @Test func `An unavailable promised string does not indicate permission denial`() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let client = PasteboardClient(pasteboard: pasteboard, readAccessBehavior: { .ask })
        let item = NSPasteboardItem()
        #expect(item.setDataProvider(MissingTextProvider(), forTypes: [.string]))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([item]))

        #expect(client.poll() == nil)
        #expect(client.readStatus == .failed)

        pasteboard.clearContents()
        #expect(client.poll() == nil)
        #expect(client.readStatus == .available)
    }

    @MainActor
    @Test func `Pasting a card preserves an intervening copy`() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let client = PasteboardClient(pasteboard: pasteboard)
        let expectedChangeCount = client.changeCount
        let latestChangeCount = pasteboard.clearContents()
        try #require(pasteboard.setString("Nouvelle copie", forType: .string))

        let paste = ClipboardHistoryComposition.makePaste(pasteboard: client)
        let outcome = await paste(
            text: "Ancienne carte", replacing: expectedChangeCount)

        #expect(outcome == .clipboardChanged)
        #expect(pasteboard.changeCount == latestChangeCount)
        #expect(pasteboard.string(forType: .string) == "Nouvelle copie")
        #expect(client.poll()?.text == "Nouvelle copie")
    }

    @MainActor
    @Test func `Pasteboard only accepts fresh external text that is not concealed`() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("Déjà présent", forType: .string))
        let client = PasteboardClient(pasteboard: pasteboard)
        #expect(client.poll() == nil)

        let item = NSPasteboardItem()
        #expect(item.setString("Confidentiel", forType: .string))
        #expect(item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([item]))
        #expect(client.poll() == nil)

        pasteboard.clearContents()
        #expect(pasteboard.setString("Café\nDeuxième ligne", forType: .string))
        let copy = try #require(client.poll())
        #expect(copy.text == "Café\nDeuxième ligne")
        #expect(copy.sourceBundleIdentifier == nil)

        let paste = ClipboardHistoryComposition.makePaste(pasteboard: client)
        let outcome = await paste(
            text: "Texte de repli", replacing: client.changeCount)
        #expect(outcome == .copied)
        #expect(pasteboard.string(forType: .string) == "Texte de repli")
        #expect(client.poll() == nil)
    }

    @Test func `Local text history survives reopening`() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.store")
        let text = "  Café\nDeuxième ligne 👋\n"
        let copiedAt = Date(timeIntervalSince1970: 100)

        let recorded: [ClipboardEntry]
        do {
            let store = try await SwiftDataClipboardHistoryStore.open(at: url)
            try await store.record(
                text: text, sourceBundleIdentifier: "com.apple.TextEdit", at: copiedAt)
            recorded = try await store.entries()
        }

        let reopenedStore = try await SwiftDataClipboardHistoryStore.open(at: url)
        let reopened = try await reopenedStore.entries()
        let card = try #require(reopened.first)
        #expect(reopened == recorded)
        #expect(card.text.utf8.elementsEqual(text.utf8))
        #expect(card.sourceBundleIdentifier == "com.apple.TextEdit")
        #expect(card.lastUsedAt == copiedAt)
    }

    @Test func `Recopy updates origin and replay preserves it`() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await SwiftDataClipboardHistoryStore.open(
            at: directory.appending(path: "history.store"))
        let start = Date(timeIntervalSince1970: 100)

        try await store.record(text: "A", sourceBundleIdentifier: "com.apple.Safari", at: start)
        let firstEntries = try await store.entries()
        let original = try #require(firstEntries.first)
        try await store.record(text: "A", sourceBundleIdentifier: "com.apple.mail", at: start + 1)
        try await store.record(text: "B", sourceBundleIdentifier: nil, at: start + 2)
        try await store.markUsed(id: original.id, at: start + 3)

        let entries = try await store.entries()
        let replayed = try #require(entries.first)
        #expect(entries.map(\.text) == ["A", "B"])
        #expect(replayed.id == original.id)
        #expect(replayed.sourceBundleIdentifier == "com.apple.mail")
        #expect(replayed.lastUsedAt == start + 3)

        try await store.record(text: "A", sourceBundleIdentifier: nil, at: start + 4)
        let latestEntries = try await store.entries()
        #expect(latestEntries.first?.sourceBundleIdentifier == nil)
        #expect(latestEntries.first?.id == original.id)
    }

    @Test func `Different UTF-8 contents remain separate cards`() async throws {
        let directory = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try await SwiftDataClipboardHistoryStore.open(
            at: directory.appending(path: "history.store"))
        let start = Date(timeIntervalSince1970: 100)
        let composed = "\u{00E9}"
        let decomposed = "e\u{0301}"

        try await store.record(text: composed, sourceBundleIdentifier: nil, at: start)
        try await store.record(text: decomposed, sourceBundleIdentifier: nil, at: start + 1)

        let entries = try await store.entries()
        #expect(
            entries.map { Array($0.text.utf8) } == [Array(decomposed.utf8), Array(composed.utf8)])
    }

    private func makeTestDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private final class MissingTextProvider: NSObject, NSPasteboardItemDataProvider {
        func pasteboard(
            _ pasteboard: NSPasteboard?, item: NSPasteboardItem,
            provideDataForType type: NSPasteboard.PasteboardType
        ) {}
    }
}
