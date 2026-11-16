import Darwin
import Foundation
import Testing

@testable import AppKite

struct ClipboardArchiveTests {
    @Test func `Ordered Finder items keep names and contents after originals are deleted`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let first = try fixture.file(in: "A", named: "notes.txt", contents: "Premier")
        let second = try fixture.file(in: "B", named: "notes.txt", contents: "Deuxième")
        let nested = try fixture.file(
            in: "Dossier/Documents", named: "rapport.pdf", contents: "PDF")
        let folder = nested.deletingLastPathComponent().deletingLastPathComponent()
        let alias = folder.appending(path: "Lien")
        try FileManager.default.createSymbolicLink(
            atPath: alias.path, withDestinationPath: "Documents/rapport.pdf")
        let selection = ClipboardPayload(
            items: [first, second, folder].map {
                ClipboardPayload.Item(representations: [], fileURL: $0)
            })

        let id = UUID()
        let staged = try fixture.archive.stage(selection, id: id)
        #expect(staged.fingerprint == (try fixture.archive.fingerprint(for: selection)))
        #expect(throws: (any Error).self) { try fixture.archive.load(id: id) }
        try fixture.archive.publish(staged)
        for original in [first, second, folder] {
            try FileManager.default.removeItem(at: original)
        }

        let replayID = UUID()
        let loaded = try fixture.archive.makeReplay(from: id, replayID: replayID)
        let files = loaded.items.compactMap(\.fileURL)
        #expect(files.map(\.lastPathComponent) == ["notes.txt", "notes.txt", "Dossier"])
        try #require(files.count == 3)
        #expect(try String(contentsOf: files[0], encoding: .utf8) == "Premier")
        #expect(try String(contentsOf: files[1], encoding: .utf8) == "Deuxième")
        let replayAlias = files[2].appending(path: "Lien")
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: replayAlias.path)
                == "Documents/rapport.pdf")
        #expect(try String(contentsOf: replayAlias, encoding: .utf8) == "PDF")

        try FileManager.default.removeItem(at: files[0])
        let archive = try fixture.archive.load(id: id)
        let original = try #require(archive.items.first?.fileURL)
        #expect(try String(contentsOf: original, encoding: .utf8) == "Premier")
        try fixture.archive.removeReplays(exceptKeeping: replayID)
        #expect(FileManager.default.fileExists(atPath: files[1].path))
        try fixture.archive.removeReplays(exceptKeeping: nil)
        #expect(!FileManager.default.fileExists(atPath: files[1].path))

        try fixture.archive.remove(id: id)
        try fixture.archive.remove(id: id)
        #expect(throws: (any Error).self) { try fixture.archive.load(id: id) }
    }

    @Test func `One unavailable file rejects an entire selection`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let existing = try fixture.file(in: "A", named: "notes.txt", contents: "Premier")
        let missing = existing.deletingLastPathComponent().appending(path: "manquant.pdf")
        let id = UUID()
        let selection = ClipboardPayload(
            items: [existing, missing].map {
                ClipboardPayload.Item(representations: [], fileURL: $0)
            })

        #expect(throws: (any Error).self) { try fixture.archive.stage(selection, id: id) }
        #expect(try fixture.archive.reconcile(keeping: [id]).isEmpty)
        #expect(throws: (any Error).self) { try fixture.archive.load(id: id) }
        let staging = fixture.root.appending(path: "archive/staging")
        let pending = try FileManager.default.contentsOfDirectory(atPath: staging.path)
        #expect(pending.isEmpty)
    }

    @Test func `Locked archive copies can be deleted without changing the source`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.file(in: "Dossier", named: "notes.txt", contents: "Copie")
        let directory = file.deletingLastPathComponent()
        let id = UUID()
        let selection = ClipboardPayload(items: [.init(representations: [], fileURL: directory)])
        #expect(chmod(directory.path, 0o555) == 0)
        #expect(chflags(file.path, UInt32(UF_IMMUTABLE)) == 0)
        defer {
            _ = chflags(file.path, 0)
            _ = chmod(directory.path, 0o755)
        }

        try fixture.archive.publish(fixture.archive.stage(selection, id: id))
        try fixture.archive.remove(id: id)
        #expect(try fixture.archive.reconcile(keeping: [id]).isEmpty)
        var metadata = stat()
        #expect(lstat(file.path, &metadata) == 0)
        #expect(metadata.st_flags & UInt32(UF_IMMUTABLE) != 0)
        #expect(try String(contentsOf: file, encoding: .utf8) == "Copie")
    }

    @Test func `Reopening cleans abandoned writes and unreferenced archives`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let keptID = UUID()
        let orphanID = UUID()
        let interruptedID = UUID()
        let card = ClipboardPayload.plainText("Carte")

        let kept = try fixture.archive.stage(card, id: keptID)
        #expect(kept.fingerprint == (try fixture.archive.fingerprint(for: card)))
        try fixture.archive.publish(kept)
        try fixture.archive.publish(fixture.archive.stage(card, id: orphanID))
        let interrupted = try fixture.archive.stage(card, id: interruptedID)

        let reopened = try ClipboardArchive(root: fixture.root.appending(path: "archive"))
        #expect(try reopened.reconcile(keeping: [keptID]) == [keptID])
        #expect(try reopened.load(id: keptID) == card)
        #expect(throws: (any Error).self) { try reopened.load(id: orphanID) }
        #expect(throws: (any Error).self) { try reopened.publish(interrupted) }

        let manifest = fixture.root.appending(path: "archive/\(keptID.uuidString)/manifest.json")
        try Data().write(to: manifest)
        #expect(try reopened.reconcile(keeping: [keptID]) == [keptID])
        #expect(throws: (any Error).self) { try reopened.load(id: keptID) }
    }

    @Test func `Fingerprint includes all item bytes and archived Finder attributes`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.file(in: "A", named: "notes.txt", contents: "Même texte")
        let second = try fixture.file(in: "B", named: "notes.txt", contents: "Même texte")

        func fingerprint(_ files: [URL]) throws -> String {
            let payload = ClipboardPayload(
                items: files.map {
                    ClipboardPayload.Item(representations: [], fileURL: $0)
                })
            let staged = try fixture.archive.stage(payload, id: UUID())
            defer { try? fixture.archive.discard(staged) }
            return staged.fingerprint
        }

        try fixture.attribute("fr.example.fixture", value: "Rouge", at: first)
        try fixture.attribute("fr.example.fixture", value: "Bleu", at: second)
        try fixture.attribute(XATTR_RESOURCEFORK_NAME, value: "Une!", at: first)
        try fixture.attribute(XATTR_RESOURCEFORK_NAME, value: "Deux", at: second)
        #expect(try fingerprint([first]) != fingerprint([second]))
        #expect(try fingerprint([first, second]) != fingerprint([second, first]))

        try fixture.attribute("fr.example.fixture", value: "Rouge", at: second)
        #expect(try fingerprint([first]) != fingerprint([second]))
        try fixture.attribute(XATTR_RESOURCEFORK_NAME, value: "Une!", at: second)
        #expect(try fingerprint([first]) == fingerprint([second]))
    }

    @Test func `Clipboard representations keep their persisted fingerprint format`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let payload = ClipboardPayload(items: [
            .init(representations: [
                .init(type: "public.utf8-plain-text", data: Data("Résumé".utf8)),
                .init(type: "public.html", data: Data("<b>x</b>".utf8)),
            ]),
            .init(representations: [.init(type: "public.png", data: Data([0, 0x80, 0xff]))]),
        ])
        let persistedFingerprint = "nOVyfkjclukL3zLVg8PD8Gf3Gq81aH3V2p/TlcZVTYQ="

        #expect(try fixture.archive.fingerprint(for: payload) == persistedFingerprint)
        let staged = try fixture.archive.stage(payload, id: UUID())
        #expect(staged.fingerprint == persistedFingerprint)
    }

    private struct Fixture {
        let root: URL
        let archive: ClipboardArchive

        init() throws {
            let directory = FileManager.default.temporaryDirectory.appending(
                path: UUID().uuidString)
            root = directory
            archive = try ClipboardArchive(root: directory.appending(path: "archive"))
        }

        func file(in directory: String, named name: String, contents: String) throws -> URL {
            let directory = root.appending(path: directory)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: name)
            try Data(contents.utf8).write(to: url)
            return url
        }

        func attribute(_ name: String, value: String, at url: URL) throws {
            let value = Data(value.utf8)
            let result = value.withUnsafeBytes {
                setxattr(url.path, name, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW)
            }
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
