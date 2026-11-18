import Foundation
import Testing

@testable import AppKite

@MainActor
struct PasteClipboardEntryTests {
    @Test func `A successful send receives the selected payload and written counter`() async {
        let payload = ClipboardPayload.plainText("Carte sélectionnée\nDeuxième ligne")
        var writes: [(ClipboardPayload, Int)] = []
        var checkedCounters: [Int] = []
        var currentCounter = 42
        let paste = PasteClipboardEntry(
            write: { payload, expected in
                writes.append((payload, expected))
                return .written(42)
            },
            isCurrent: { counter in
                checkedCounters.append(counter)
                return currentCounter == counter
            },
            send: { isCurrent in
                #expect(isCurrent())
                currentCounter = 43
                return true
            })

        let outcome = await paste(payload: payload, replacing: 41)

        #expect(outcome == .sent)
        #expect(writes.count == 1)
        #expect(writes.first?.0 == payload)
        #expect(writes.first?.1 == 41)
        #expect(checkedCounters == [42])
    }

    @Test func `An unavailable send leaves the written text available for manual paste`() async {
        var written: ClipboardPayload?
        var sent = false
        let paste = PasteClipboardEntry(
            write: { payload, _ in
                written = payload
                return .written(8)
            },
            isCurrent: { $0 == 8 },
            send: { _ in
                sent = true
                return false
            })

        let outcome = await paste(text: "Texte de repli", replacing: 7)

        #expect(outcome == .copied)
        #expect(written == .plainText("Texte de repli"))
        #expect(sent)
    }

    @Test func `A failed write prevents the send and counter check`() async {
        var operations: [String] = []
        let paste = PasteClipboardEntry(
            write: { _, _ in
                operations.append("write")
                return .failed
            },
            isCurrent: { _ in
                operations.append("check")
                return true
            },
            send: { _ in
                operations.append("send")
                return true
            })

        let outcome = await paste(text: "Carte", replacing: 10)

        #expect(outcome == .failed)
        #expect(operations == ["write"])
    }

    @Test func `A changed clipboard prevents the send and counter check`() async {
        var operations: [String] = []
        let paste = PasteClipboardEntry(
            write: { _, _ in
                operations.append("write")
                return .changed
            },
            isCurrent: { _ in
                operations.append("check")
                return true
            },
            send: { _ in
                operations.append("send")
                return true
            })

        let outcome = await paste(text: "Ancienne carte", replacing: 10)

        #expect(outcome == .clipboardChanged)
        #expect(operations == ["write"])
    }

    @Test func `A new copy during a suspended send invalidates the pending payload`() async throws {
        let (started, signalStarted) = AsyncStream<Bool>.makeStream()
        let (resumed, resumeSend) = AsyncStream<Bool>.makeStream()
        var currentCounter = 11
        var sendChecks: [Bool] = []
        let paste = PasteClipboardEntry(
            write: { _, _ in .written(11) },
            isCurrent: { currentCounter == $0 },
            send: { isCurrent in
                sendChecks.append(isCurrent())
                signalStarted.yield(true)
                var resume = resumed.makeAsyncIterator()
                _ = await resume.next()
                let canSend = isCurrent()
                sendChecks.append(canSend)
                return canSend
            })
        let operation = Task {
            defer { signalStarted.finish() }
            return await paste(text: "Carte", replacing: 10)
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(10))
            signalStarted.finish()
            resumeSend.finish()
        }
        defer {
            timeout.cancel()
            resumeSend.finish()
            operation.cancel()
        }
        var events = started.makeAsyncIterator()
        try #require(await events.next() == true)

        currentCounter = 12
        resumeSend.yield(true)
        let outcome = await operation.value

        #expect(outcome == .clipboardChanged)
        #expect(sendChecks == [true, false])
    }

    @Test func `Cancellation before the call prevents every effect`() async {
        var operations: [String] = []
        let paste = PasteClipboardEntry(
            write: { _, _ in
                operations.append("write")
                return .written(11)
            },
            isCurrent: { _ in
                operations.append("check")
                return true
            },
            send: { _ in
                operations.append("send")
                return true
            })
        let operation = Task { @MainActor in
            await paste(text: "Carte", replacing: 10)
        }
        operation.cancel()
        let outcome = await operation.value

        #expect(outcome == .failed)
        #expect(operations.isEmpty)
    }
}
