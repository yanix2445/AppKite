import CoreData
import CryptoKit
import Darwin
import Foundation
import SQLite3
import SwiftData

actor SwiftDataClipboardHistoryStore: ModelActor, ClipboardHistoryStore {
    private nonisolated struct PreparedEntry: Sendable {
        let indexedText: String?
        let recognizedText: String?
        let preview: (summary: String, tablePreviewRows: [[String]])?
    }

    nonisolated let modelExecutor: any ModelExecutor
    nonisolated let modelContainer: ModelContainer
    private let archive: ClipboardArchive
    private nonisolated let searchIndex = ClipboardSearchIndex()
    private var recognition: (id: UUID, task: Task<PreparedEntry, any Error>)?
    private var failedRecognition: Set<UUID> = []
    private let storageLock: FileHandle
    private let removeArchive: @Sendable (ClipboardArchive, UUID) throws -> Void

    private init(
        modelContainer: ModelContainer, archive: ClipboardArchive, storageLock: FileHandle,
        removeArchive: @escaping @Sendable (ClipboardArchive, UUID) throws -> Void
    ) {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = modelContainer
        self.archive = archive
        self.storageLock = storageLock
        self.removeArchive = removeArchive
    }

    static func open(
        at url: URL? = nil,
        removeArchive: @escaping @Sendable (ClipboardArchive, UUID) throws -> Void = {
            try $0.remove(id: $1)
        }
    ) async throws -> SwiftDataClipboardHistoryStore {
        try await Task.detached {
            let storeURL = try url ?? Self.defaultStoreURL()
            let directory = storeURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let storageLock = try lockStorage(in: directory)
            let schema = Schema([StoredClipboardEntry.self, StoredClipboardCollection.self])
            let configuration = ModelConfiguration(
                schema: schema, url: storeURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let archive = try ClipboardArchive(root: directory.appending(path: "archives"))
            let store = Self(
                modelContainer: container, archive: archive, storageLock: storageLock,
                removeArchive: removeArchive
            )
            try await store.reconcileArchives()
            try await store.loadSearchIndex()
            return store
        }.value
    }

    private static func lockStorage(in directory: URL) throws -> FileHandle {
        // Keep this inode and hold its lock until the actor goes away. Opening another
        // store would otherwise reconcile archives that are being staged or published here.
        let lockURL = directory.appending(path: ".history.lock")
        let descriptor = try lockURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw POSIXError(.EINVAL) }
            return Darwin.open(path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        }
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            if code == EWOULDBLOCK { throw ClipboardHistoryStoreError.storageInUse }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return handle
    }

    func entries() throws -> [ClipboardEntry] {
        let descriptor = FetchDescriptor<StoredClipboardEntry>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse), SortDescriptor(\.id)]
        )
        return try modelContext.fetch(descriptor).map(\.entry)
    }

    nonisolated func search(_ query: ClipboardHistoryQuery) async throws -> ClipboardHistoryResults
    {
        let task = Task.detached(priority: .userInitiated) {
            try self.searchIndex.search(query)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func thumbnails(for ids: [UUID]) throws -> [UUID: Data] {
        guard !ids.isEmpty else { return [:] }
        let descriptor = FetchDescriptor<StoredClipboardEntry>(
            predicate: #Predicate { ids.contains($0.id) && $0.thumbnail != nil }
        )
        var thumbnails: [UUID: Data] = [:]
        for entry in try modelContext.fetch(descriptor) {
            thumbnails[entry.id] = entry.thumbnail
        }
        return thumbnails
    }

    func indexNextPendingEntry() async throws -> Bool {
        guard recognition == nil else { return false }
        let failed = Array(failedRecognition)
        var descriptor = FetchDescriptor<StoredClipboardEntry>(
            predicate: #Predicate {
                ($0.needsRecognition || ($0.hasArchive && $0.indexedText == nil))
                    && !failed.contains($0.id)
            },
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard
            let entry = try modelContext.fetch(descriptor).first
                ?? nextLegacyPreview(skipping: failed)
        else { return false }
        let id = entry.id
        let needsIndexing = entry.needsRecognition || entry.indexedText == nil
        let previewKind: ClipboardPayload.Kind? =
            entry.previewRowsData == nil
            ? entry.kindIdentifier.flatMap(ClipboardPayload.Kind.init(rawValue:)) : nil
        let archive = archive
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let payload = try archive.load(id: id)
            return PreparedEntry(
                indexedText: needsIndexing
                    ? ClipboardTextExtractor.immediateText(in: payload) : nil,
                recognizedText: needsIndexing
                    ? try ClipboardTextExtractor.recognizedText(in: payload) : nil,
                preview: previewKind.map {
                    ClipboardFormatCodec.textPreview(for: payload, kind: $0)
                }
            )
        }
        recognition = (id, task)
        defer { recognition = nil }
        do {
            let prepared = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard let entry = try self.entry(id: id) else { return true }
            if let indexedText = prepared.indexedText {
                entry.indexedText = indexedText
            }
            if let recognizedText = prepared.recognizedText {
                entry.recognizedText = recognizedText
                entry.needsRecognition = false
            }
            if let preview = prepared.preview {
                entry.text = preview.summary
                try entry.setPreviewRows(preview.tablePreviewRows)
            }
            try save()
            refreshIndex(for: entry)
        } catch is CancellationError {
            try Task.checkCancellation()
        } catch {
            // Keep unfinished work persisted for another launch and continue with the next card.
            failedRecognition.insert(id)
        }
        return true
    }

    private func nextLegacyPreview(skipping failed: [UUID]) throws -> StoredClipboardEntry? {
        let spreadsheet: String? = ClipboardPayload.Kind.spreadsheet.rawValue
        let text: String? = ClipboardPayload.Kind.text.rawValue
        let unprepared = #Predicate<StoredClipboardEntry> {
            $0.hasArchive && $0.previewRowsData == nil && !failed.contains($0.id)
        }
        var descriptor = FetchDescriptor<StoredClipboardEntry>(
            predicate: #Predicate {
                unprepared.evaluate($0)
                    && ($0.kindIdentifier == spreadsheet
                        || ($0.kindIdentifier == text && $0.text == "Texte"))
            },
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func loadSearchIndex() throws {
        var descriptor = FetchDescriptor<StoredClipboardEntry>()
        descriptor.relationshipKeyPathsForPrefetching = [\.collections]
        for entry in try modelContext.fetch(descriptor) {
            refreshIndex(for: entry)
        }
    }

    private func refreshIndex(for entry: StoredClipboardEntry) {
        let text = (entry.indexedText ?? entry.text) + "\n" + (entry.recognizedText ?? "")
        searchIndex.update(entry.card(includingThumbnail: false), text: text)
    }

    func record(text: String, sourceBundleIdentifier: String?, at date: Date) throws {
        try record(
            payload: .plainText(text), sourceBundleIdentifier: sourceBundleIdentifier, at: date)
    }

    func record(payload: ClipboardPayload, sourceBundleIdentifier: String?, at date: Date) throws {
        try record(
            ClipboardCopy(
                payload: payload, sourceBundleIdentifier: sourceBundleIdentifier,
                probableSourceBundleIdentifier: nil),
            at: date)
    }

    func record(_ copy: ClipboardCopy, at date: Date) throws {
        do {
            try archivePayload(copy, at: date)
        } catch {
            guard Self.isOutOfSpace(error) else { throw error }
            defer { try? archive.prepareRecoveryReserve() }
            let released = try archive.releaseRecoveryReserve()
            guard released > 0 else {
                throw ClipboardHistoryStoreError.insufficientArchiveCapacity
            }
            do {
                try archivePayload(copy, at: date, releasedReserve: released)
            } catch {
                if Self.isOutOfSpace(error) {
                    throw ClipboardHistoryStoreError.insufficientArchiveCapacity
                }
                throw error
            }
            return
        }
        try? archive.prepareRecoveryReserve()
    }

    private func archivePayload(_ copy: ClipboardCopy, at date: Date, releasedReserve: Int64 = 0)
        throws
    {
        let payload = copy.payload
        let plainText = payload.plainText
        let legacyFingerprint = plainText.map {
            Data(SHA256.hash(data: Data($0.utf8))).base64EncodedString()
        }
        let fingerprint = try legacyFingerprint ?? archive.fingerprint(for: payload)
        if let existing = try entries(fingerprint: fingerprint).first(where: { entry in
            entry.hasArchive || plainText.map { entry.text.utf8.elementsEqual($0.utf8) } == true
        }) {
            update(existing, from: copy, at: date)
            try save()
            refreshIndex(for: existing)
            return
        }

        let entry = StoredClipboardEntry(
            text: "", fingerprint: "", sourceBundleIdentifier: copy.sourceBundleIdentifier,
            copiedAt: date
        )
        entry.probableSourceBundleIdentifier = copy.probableSourceBundleIdentifier
        entry.isRemote = copy.isRemote
        let staged = try archive.stage(payload, id: entry.id)
        defer { try? archive.discard(staged) }
        if let existing = try entries(fingerprint: staged.fingerprint).first(where: \.hasArchive) {
            update(existing, from: copy, at: date)
            try save()
            refreshIndex(for: existing)
            return
        }

        let presentation = ClipboardFormatCodec.presentation(for: payload)
        entry.text = presentation.summary
        entry.kindIdentifier = presentation.kind.rawValue
        entry.thumbnail = presentation.thumbnail
        try entry.setPreviewRows(presentation.tablePreviewRows)
        entry.fingerprint = legacyFingerprint ?? staged.fingerprint
        entry.hasArchive = true
        entry.indexedText = ClipboardTextExtractor.immediateText(in: payload)
        entry.needsRecognition = ClipboardTextExtractor.requiresRecognition(payload)
        try archive.publish(staged)

        let evictedIDs: [UUID]
        do {
            // Keep the previous files until the replacement and all evictions commit together.
            let evictions = try evictionCandidates(releasedReserve: releasedReserve)
            evictedIDs = evictions.map(\.id)
            modelContext.insert(entry)
            for candidate in evictions {
                modelContext.delete(candidate)
            }
            try save()
        } catch {
            try? archive.remove(id: staged.id)
            throw error
        }

        forgetEntries(evictedIDs)
        refreshIndex(for: entry)
        // If cleanup is interrupted, reconciliation removes these unreferenced archives.
        for id in evictedIDs {
            try? archive.remove(id: id)
        }
    }

    private func evictionCandidates(releasedReserve: Int64) throws -> [StoredClipboardEntry] {
        guard releasedReserve > 0 else { return [] }
        var remaining = releasedReserve - (try archive.availableBytes())
        guard remaining > 0 else { return [] }

        let descriptor = FetchDescriptor<StoredClipboardEntry>(
            predicate: #Predicate { !$0.isPinned && $0.hasArchive },
            sortBy: [SortDescriptor(\.lastUsedAt), SortDescriptor(\.id)]
        )
        var candidates: [StoredClipboardEntry] = []
        for entry in try modelContext.fetch(descriptor)
        where !entry.isProtected && recognition?.id != entry.id {
            let bytes = try archive.reclaimableBytes(for: entry.id)
            guard bytes > 0 else { continue }
            candidates.append(entry)
            remaining -= bytes
            if remaining <= 0 { return candidates }
        }
        throw ClipboardHistoryStoreError.insufficientArchiveCapacity
    }

    func payload(for id: UUID) throws -> ClipboardPayload {
        guard let entry = try entry(id: id) else {
            throw ClipboardHistoryStoreError.missingEntry
        }
        return try entry.hasArchive ? archive.load(id: id) : .plainText(entry.text)
    }

    func previewSource(for id: UUID) async throws -> ClipboardPreviewSource? {
        guard let entry = try entry(id: id), entry.hasArchive else { return nil }
        let archive = archive
        let task = Task.detached(priority: .utility) {
            try archive.previewSource(for: id)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func prepareReplay(for id: UUID, replayID: UUID) throws -> ClipboardPayload {
        try prepareReplay(for: [id], replayID: replayID)
    }

    func prepareReplay(for ids: [UUID], replayID: UUID) throws -> ClipboardPayload {
        guard ids.count <= ClipboardArchive.groupedReplayItemLimit else {
            throw ClipboardHistoryStoreError.groupedReplayTooLarge
        }
        let entries = try ids.map { id in
            guard let entry = try entry(id: id) else {
                throw ClipboardHistoryStoreError.missingEntry
            }
            return entry
        }
        let archivedIDs = entries.filter(\.hasArchive).map(\.id)
        if ids.count > 1 {
            let legacyTexts = entries.filter { !$0.hasArchive }.map(\.text)
            try archive.checkGroupedReplay(from: archivedIDs, legacyTexts: legacyTexts)
        }
        let archived = try archive.makeReplays(from: archivedIDs, replayID: replayID)
        return try ClipboardFormatCodec.groupedReplay(
            entries.map { archived[$0.id] ?? .plainText($0.text) })
    }

    func removeReplays(exceptKeeping replayID: UUID?) throws {
        try archive.removeReplays(exceptKeeping: replayID)
    }

    func markUsed(id: UUID, at date: Date) throws {
        try markUsed(ids: [id], at: date)
    }

    func markUsed(ids: [UUID], at date: Date) throws {
        let entries = try ids.compactMap { try entry(id: $0) }
        var changed: [StoredClipboardEntry] = []
        for (index, entry) in entries.enumerated() {
            let time = date.addingTimeInterval(-Double(index) / 1_000_000)
            guard time > entry.lastUsedAt else { continue }
            entry.lastUsedAt = time
            changed.append(entry)
        }
        guard !changed.isEmpty else { return }
        try save()
        for entry in changed { refreshIndex(for: entry) }
    }

    func collections() throws -> [ClipboardCollection] {
        let descriptor = FetchDescriptor<StoredClipboardCollection>(
            sortBy: [SortDescriptor(\.name), SortDescriptor(\.id)]
        )
        return try modelContext.fetch(descriptor).map(\.collection)
    }

    func setPinned(_ isPinned: Bool, for entryID: UUID) throws {
        guard let entry = try entry(id: entryID), entry.isPinned != isPinned else { return }
        entry.isPinned = isPinned
        try save()
        refreshIndex(for: entry)
    }

    func createCollection(named name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ClipboardHistoryStoreError.invalidCollectionName }
        modelContext.insert(StoredClipboardCollection(name: name))
        try save()
    }

    func setMembership(_ isMember: Bool, for entryID: UUID, in collectionID: UUID) throws {
        guard let entry = try entry(id: entryID) else { return }
        var memberships = entry.collections ?? []
        let index = memberships.firstIndex { $0.id == collectionID }
        if isMember {
            guard index == nil, let collection = try collection(id: collectionID) else { return }
            memberships.append(collection)
        } else {
            guard let index else { return }
            memberships.remove(at: index)
        }
        entry.collections = memberships
        try save()
        refreshIndex(for: entry)
    }

    func deleteCollection(id: UUID) throws {
        guard let collection = try collection(id: id) else { return }
        let affected = collection.entries ?? []
        modelContext.delete(collection)
        try save()
        for entry in affected { refreshIndex(for: entry) }
    }

    func deleteEntry(id: UUID, confirmingProtection: Bool) throws {
        try deleteEntries(ids: [id], confirmingProtection: confirmingProtection)
    }

    func deleteEntries(ids: Set<UUID>, confirmingProtection: Bool) throws {
        let entries = try ids.compactMap { try entry(id: $0) }
        guard confirmingProtection || entries.allSatisfy({ !$0.isProtected }) else {
            throw ClipboardHistoryStoreError.protectedEntry
        }
        guard !entries.isEmpty else { return }
        try delete(entries)
    }

    func clearUnprotectedEntries() throws {
        let descriptor = FetchDescriptor<StoredClipboardEntry>(
            predicate: #Predicate { !$0.isPinned }
        )
        try delete(modelContext.fetch(descriptor).filter { !$0.isProtected })
    }

    private func delete(_ entries: [StoredClipboardEntry]) throws {
        let ids = entries.map(\.id)
        let archivedIDs = entries.filter(\.hasArchive).map(\.id)
        for entry in entries {
            modelContext.delete(entry)
        }
        try save()
        forgetEntries(ids)

        // Reopening retries any failed cleanup. The database no longer points at these files.
        var deferred = false
        for id in archivedIDs {
            do {
                try removeArchive(archive, id)
            } catch {
                deferred = true
            }
        }
        if deferred { throw ClipboardHistoryStoreError.archiveCleanupDeferred }
    }

    private func forgetEntries(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        searchIndex.remove(ids)
        failedRecognition.subtract(ids)
        if let recognition, ids.contains(recognition.id) {
            recognition.task.cancel()
        }
    }

    private func reconcileArchives() throws {
        let descriptor = FetchDescriptor<StoredClipboardEntry>(
            predicate: #Predicate { $0.hasArchive }
        )
        let archived = try modelContext.fetch(descriptor)
        let present = try archive.reconcile(keeping: Set(archived.map(\.id)))
        if !present.isEmpty { try? archive.prepareRecoveryReserve() }
        let missing = archived.filter { !present.contains($0.id) }
        guard !missing.isEmpty else { return }
        for entry in missing {
            modelContext.delete(entry)
        }
        try save()
    }

    private func entries(fingerprint: String) throws -> [StoredClipboardEntry] {
        try modelContext.fetch(
            FetchDescriptor(predicate: #Predicate { $0.fingerprint == fingerprint })
        )
    }

    private func update(
        _ entry: StoredClipboardEntry, from copy: ClipboardCopy, at date: Date
    ) {
        if date >= entry.lastCopiedAt {
            entry.lastCopiedAt = date
            entry.sourceBundleIdentifier = copy.sourceBundleIdentifier
            entry.probableSourceBundleIdentifier = copy.probableSourceBundleIdentifier
            entry.isRemote = copy.isRemote
        }
        entry.lastUsedAt = max(entry.lastUsedAt, date)
    }

    private func entry(id: UUID) throws -> StoredClipboardEntry? {
        var descriptor = FetchDescriptor<StoredClipboardEntry>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func collection(id: UUID) throws -> StoredClipboardCollection? {
        var descriptor = FetchDescriptor<StoredClipboardCollection>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func isOutOfSpace(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain
            && error.code == CocoaError.fileWriteOutOfSpace.rawValue
        {
            return true
        }
        if error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC) {
            return true
        }
        if error.domain == NSSQLiteErrorDomain && error.code == Int(SQLITE_FULL) {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, underlying !== error {
            return isOutOfSpace(underlying)
        }
        return false
    }

    private static func defaultStoreURL() throws -> URL {
        let files = FileManager.default
        let support = try files.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appending(
            path: "AppKite/ClipboardHistory", directoryHint: .isDirectory)
        return directory.appending(path: "history.store", directoryHint: .notDirectory)
    }
}
