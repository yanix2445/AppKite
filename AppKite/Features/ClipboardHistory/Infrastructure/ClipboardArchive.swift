import CryptoKit
import Darwin
import Foundation
import OSLog

nonisolated struct ClipboardArchive: Sendable {
    private static let recoveryReserveSize: Int64 = 16 * 1024 * 1024
    private static let logger = Logger(
        subsystem: "com.appkite.AppKite", category: "ClipboardArchive")

    struct StagedArchive: Sendable {
        let id: UUID
        let fingerprint: String
    }

    enum ArchiveError: Error {
        case invalidItem
        case unsupportedFile
        case sourceChanged
        case invalidArchive
    }

    private struct Manifest: Codable {
        let items: [Item]

        struct Item: Codable {
            let types: [String]
            let fileName: String?
        }
    }

    private struct FileState: Equatable {
        let identity: ino_t
        let device: dev_t
        let mode: mode_t
        let flags: UInt32
        let size: off_t
        let links: nlink_t
        let modificationSeconds: Int
        let modificationNanoseconds: Int
        let changeSeconds: Int
        let changeNanoseconds: Int

        init(url: URL) throws {
            var info = stat()
            let result = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return Int32(-1) }
                return lstat(path, &info)
            }
            guard result == 0 else { throw ClipboardArchive.fileError() }
            identity = info.st_ino
            device = info.st_dev
            mode = info.st_mode
            flags = info.st_flags
            size = info.st_size
            links = info.st_nlink
            modificationSeconds = info.st_mtimespec.tv_sec
            modificationNanoseconds = info.st_mtimespec.tv_nsec
            changeSeconds = info.st_ctimespec.tv_sec
            changeNanoseconds = info.st_ctimespec.tv_nsec
        }

        var type: mode_t { mode & mode_t(S_IFMT) }
    }

    private struct SourceFile {
        let url: URL
        let name: String
        let states: [Data: FileState]
    }

    private struct Fingerprint {
        private var hash = SHA256()

        mutating func append(_ value: UInt64) {
            var value = value.bigEndian
            withUnsafeBytes(of: &value) { hash.update(bufferPointer: $0) }
        }

        mutating func append(_ value: String) {
            append(Data(value.utf8))
        }

        mutating func append(_ data: Data) {
            append(UInt64(data.count))
            hash.update(data: data)
        }

        mutating func appendContents(of url: URL, count: UInt64) throws {
            let descriptor = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return Int32(-1) }
                return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            }
            guard descriptor >= 0 else { throw ClipboardArchive.fileError() }

            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close() }
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == S_IFREG,
                info.st_size >= 0, UInt64(info.st_size) == count
            else { throw ArchiveError.sourceChanged }

            append(count)
            var remaining = count
            while remaining > 0 {
                let limit = Int(min(remaining, 1024 * 1024))
                guard let data = try handle.read(upToCount: limit), !data.isEmpty else {
                    throw ArchiveError.sourceChanged
                }
                hash.update(data: data)
                remaining -= UInt64(data.count)
            }
        }

        mutating func appendRepresentation(_ representation: ClipboardPayload.Representation) {
            append(representation.type)
            append(representation.data)
        }

        mutating func appendExtendedAttributes(at url: URL) throws {
            try url.withUnsafeFileSystemRepresentation { path in
                guard let path else { throw ArchiveError.invalidItem }
                let size = listxattr(path, nil, 0, XATTR_NOFOLLOW)
                guard size >= 0 else { throw ClipboardArchive.fileError() }
                var names = [UInt8](repeating: 0, count: size)
                if size > 0 {
                    let actualSize = names.withUnsafeMutableBytes {
                        listxattr(path, $0.baseAddress, size, XATTR_NOFOLLOW)
                    }
                    guard actualSize == size else { throw ArchiveError.sourceChanged }
                }

                let attributes = names.split(separator: 0).map(Array.init).sorted {
                    $0.lexicographicallyPrecedes($1)
                }
                append(UInt64(attributes.count))
                for attribute in attributes {
                    append(Data(attribute))
                    let name = attribute.map { CChar(bitPattern: $0) } + [0]
                    try name.withUnsafeBufferPointer { buffer in
                        guard let name = buffer.baseAddress else { throw ArchiveError.invalidItem }
                        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
                        guard size >= 0 else { throw ClipboardArchive.fileError() }
                        append(UInt64(size))
                        if String(cString: name) == XATTR_RESOURCEFORK_NAME {
                            try appendResourceFork(at: url, size: size)
                        } else if size > 0 {
                            var data = Data(count: size)
                            let count = data.withUnsafeMutableBytes {
                                getxattr(path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW)
                            }
                            guard count == size else { throw ArchiveError.sourceChanged }
                            hash.update(data: data)
                        }
                    }
                }
            }
        }

        private mutating func appendResourceFork(at url: URL, size: Int) throws {
            guard size > 0 else { return }
            let fork = url.appending(path: "..namedfork/rsrc")
            let handle = try FileHandle(forReadingFrom: fork)
            defer { try? handle.close() }
            var remaining = size
            while remaining > 0 {
                guard let data = try handle.read(upToCount: min(remaining, 1024 * 1024)),
                    !data.isEmpty
                else { throw ArchiveError.sourceChanged }
                hash.update(data: data)
                remaining -= data.count
            }
        }

        var value: String { Data(hash.finalize()).base64EncodedString() }
    }

    private let root: URL
    private let staging: URL
    private let replays: URL
    private var recoveryReserve: URL { root.appending(path: ".recovery-reserve") }

    init(root: URL) throws {
        self.root = root
        staging = root.appending(path: "staging", directoryHint: .isDirectory)
        replays = root.appending(path: "replays", directoryHint: .isDirectory)
        for directory in [root, staging, replays] {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            guard try FileState(url: directory).type == S_IFDIR else {
                throw ArchiveError.invalidArchive
            }
        }
    }

    func fingerprint(for payload: ClipboardPayload) throws -> String {
        let sources = try payload.items.map { try $0.fileURL.map(sourceFile) }
        var hash = Fingerprint()
        hash.append(UInt64(payload.items.count))
        for (item, source) in zip(payload.items, sources) {
            hash.append(UInt64(item.representations.count))
            for representation in item.representations {
                hash.appendRepresentation(representation)
            }
            if let source {
                hash.append(UInt64(1))
                try hashFile(at: source.url, named: source.name, into: &hash)
            } else {
                hash.append(UInt64(0))
            }
        }
        try verifyUnchanged(sources)
        return hash.value
    }

    func stage(_ payload: ClipboardPayload, id: UUID) throws -> StagedArchive {
        guard !payload.items.isEmpty else { throw ArchiveError.invalidItem }
        let sources = try payload.items.map { try $0.fileURL.map(sourceFile) }
        let directory = itemDirectory(in: staging, id: id)
        try createDirectory(directory)

        do {
            var hash = Fingerprint()
            hash.append(UInt64(payload.items.count))
            var items: [Manifest.Item] = []

            for (index, item) in payload.items.enumerated() {
                guard !item.representations.isEmpty || item.fileURL != nil else {
                    throw ArchiveError.invalidItem
                }
                let container = itemContainer(in: directory, index: index)
                try createDirectory(container)

                hash.append(UInt64(item.representations.count))
                for (index, representation) in item.representations.enumerated() {
                    hash.appendRepresentation(representation)
                    try representation.data.write(
                        to: representationURL(in: container, index: index))
                }

                var fileName: String?
                if let source = sources[index] {
                    let destination = fileURL(in: container, named: source.name)
                    try createDirectory(destination.deletingLastPathComponent())
                    try FileManager.default.copyItem(at: source.url, to: destination)
                    hash.append(UInt64(1))
                    try hashFile(at: destination, named: source.name, into: &hash)
                    fileName = source.name
                } else {
                    hash.append(UInt64(0))
                }
                items.append(.init(types: item.representations.map(\.type), fileName: fileName))
            }

            try verifyUnchanged(sources)

            let manifest = try JSONEncoder().encode(Manifest(items: items))
            try manifest.write(to: manifestURL(in: directory))
            return StagedArchive(id: id, fingerprint: hash.value)
        } catch {
            try? removeIfPresent(directory)
            throw error
        }
    }

    func publish(_ staged: StagedArchive) throws {
        try FileManager.default.moveItem(
            at: itemDirectory(in: staging, id: staged.id),
            to: itemDirectory(in: root, id: staged.id)
        )
    }

    func discard(_ staged: StagedArchive) throws {
        try removeIfPresent(itemDirectory(in: staging, id: staged.id))
    }

    func remove(id: UUID) throws {
        try removeIfPresent(itemDirectory(in: root, id: id))
    }

    func prepareRecoveryReserve() throws {
        guard !FileManager.default.fileExists(atPath: recoveryReserve.path) else { return }
        let volume = try volumeInfo()
        let fileSystem = withUnsafeBytes(of: volume.f_fstypename) { name in
            String(decoding: name.prefix { $0 != 0 }, as: UTF8.self)
        }
        let available = Int64(volume.f_bavail) * Int64(volume.f_bsize)
        guard fileSystem == "apfs", available > Self.recoveryReserveSize else { return }
        let bytes = min(Self.recoveryReserveSize, available / 2)

        let prepared = staging.appending(path: UUID().uuidString)
        defer { try? removeIfPresent(prepared) }
        try allocateRecoveryReserve(at: prepared, bytes: bytes)
        try FileManager.default.moveItem(at: prepared, to: recoveryReserve)
    }

    private func allocateRecoveryReserve(at url: URL, bytes: Int64) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        }
        guard descriptor >= 0 else { throw Self.fileError() }
        defer { Darwin.close(descriptor) }
        var allocation = fstore_t()
        allocation.fst_flags = UInt32(F_ALLOCATEALL | F_ALLOCATEPERSIST)
        allocation.fst_posmode = F_PEOFPOSMODE
        allocation.fst_length = bytes
        guard fcntl(descriptor, F_PREALLOCATE, &allocation) == 0,
            ftruncate(descriptor, bytes) == 0
        else { throw Self.fileError() }
    }

    func releaseRecoveryReserve() throws -> Int64 {
        guard FileManager.default.fileExists(atPath: recoveryReserve.path) else { return 0 }
        let reserved = try reclaimableBytes(at: recoveryReserve)
        guard reserved > 0 else { return 0 }
        let available = try availableBytes()
        try removeIfPresent(recoveryReserve)
        return min(reserved, max(0, try availableBytes() - available))
    }

    func availableBytes() throws -> Int64 {
        let volume = try volumeInfo()
        return Int64(volume.f_bavail) * Int64(volume.f_bsize)
    }

    func reclaimableBytes(for id: UUID) throws -> Int64 {
        let directory = itemDirectory(in: root, id: id)
        return try children(of: directory).filter { $0.lastPathComponent != "manifest.json" }
            .reduce(0) { try $0 + reclaimableBytes(at: $1) }
    }

    func reconcile(keeping ids: Set<UUID>) throws -> Set<UUID> {
        for directory in try children(of: staging) {
            removeAbandonedItem(directory)
        }
        var present: Set<UUID> = []
        for directory in try children(of: root) {
            guard let id = UUID(uuidString: directory.lastPathComponent) else { continue }
            if ids.contains(id) {
                present.insert(id)
            } else {
                removeAbandonedItem(directory)
            }
        }
        return present
    }

    private func removeAbandonedItem(_ url: URL) {
        do {
            try removeIfPresent(url)
        } catch {
            Self.logger.warning(
                "Could not clean up a clipboard archive: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    func load(id: UUID) throws -> ClipboardPayload {
        try load(from: itemDirectory(in: root, id: id), copyingFilesTo: nil)
    }

    func makeReplay(from id: UUID, replayID: UUID) throws -> ClipboardPayload {
        let directory = itemDirectory(in: replays, id: replayID)
        do {
            return try load(from: itemDirectory(in: root, id: id), copyingFilesTo: directory)
        } catch {
            try? removeIfPresent(directory)
            throw error
        }
    }

    func removeReplays(exceptKeeping id: UUID?) throws {
        for directory in try children(of: replays)
        where UUID(uuidString: directory.lastPathComponent) != id {
            try removeIfPresent(directory)
        }
    }

    private func readManifest(in directory: URL) throws -> Manifest {
        guard try FileState(url: directory).type == S_IFDIR,
            try FileState(url: manifestURL(in: directory)).type == S_IFREG
        else { throw ArchiveError.invalidArchive }
        let data = try Data(contentsOf: manifestURL(in: directory))
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard !manifest.items.isEmpty else { throw ArchiveError.invalidArchive }
        for (index, item) in manifest.items.enumerated() {
            guard !item.types.isEmpty || item.fileName != nil else {
                throw ArchiveError.invalidArchive
            }
            let container = itemContainer(in: directory, index: index)
            guard try FileState(url: container).type == S_IFDIR else {
                throw ArchiveError.invalidArchive
            }
            for index in item.types.indices {
                guard
                    try FileState(url: representationURL(in: container, index: index)).type
                        == S_IFREG
                else { throw ArchiveError.invalidArchive }
            }
            if let name = item.fileName {
                let file = fileURL(in: container, named: name)
                guard isFileName(name),
                    try FileState(url: file.deletingLastPathComponent()).type == S_IFDIR
                else { throw ArchiveError.invalidArchive }
                try validate(file: FileState(url: file))
            }
        }
        return manifest
    }

    private func load(from directory: URL, copyingFilesTo replay: URL?) throws -> ClipboardPayload {
        let manifest = try readManifest(in: directory)
        let items = try manifest.items.enumerated().map { index, item in
            let container = itemContainer(in: directory, index: index)
            let representations = try item.types.enumerated().map { index, type in
                let data = try Data(
                    contentsOf: representationURL(in: container, index: index),
                    options: .mappedIfSafe
                )
                return ClipboardPayload.Representation(type: type, data: data)
            }
            let file = try item.fileName.map { name in
                let archived = fileURL(in: container, named: name)
                guard let replay else { return archived }
                let destination = fileURL(in: itemContainer(in: replay, index: index), named: name)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                try FileManager.default.copyItem(at: archived, to: destination)
                return destination
            }
            return ClipboardPayload.Item(representations: representations, fileURL: file)
        }
        return ClipboardPayload(items: items)
    }

    private func sourceFile(_ source: URL) throws -> SourceFile {
        let name = source.lastPathComponent
        let host = source.host(percentEncoded: false)
        guard isFileName(name), source.isFileURL, host == nil || host == "" || host == "localhost"
        else { throw ArchiveError.invalidItem }

        let parent = source.deletingLastPathComponent().resolvingSymlinksInPath()
        let url = parent.appending(path: name, directoryHint: .notDirectory)
        let sourceState = try FileState(url: url)
        if sourceState.type == S_IFDIR {
            var ancestor = root.resolvingSymlinksInPath()
            while true {
                let state = try FileState(url: ancestor)
                guard state.identity != sourceState.identity || state.device != sourceState.device
                else { throw ArchiveError.invalidItem }
                let parent = ancestor.deletingLastPathComponent()
                if ancestor.path == "/" || parent.path.isEmpty || parent.path == ancestor.path {
                    break
                }
                ancestor = parent
            }
        }
        return SourceFile(url: url, name: name, states: try snapshot(of: url))
    }

    private func verifyUnchanged(_ sources: [SourceFile?]) throws {
        for case let source? in sources {
            guard try snapshot(of: source.url) == source.states else {
                throw ArchiveError.sourceChanged
            }
        }
    }

    private func snapshot(of url: URL) throws -> [Data: FileState] {
        var states: [Data: FileState] = [:]
        try visit(url, at: Data(), addingTo: &states)
        return states
    }

    private func volumeInfo() throws -> statfs {
        var volume = statfs()
        let result = root.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return statfs(path, &volume)
        }
        guard result == 0 else { throw Self.fileError() }
        return volume
    }

    private func reclaimableBytes(at url: URL) throws -> Int64 {
        let file = try FileState(url: url)
        if file.type == S_IFDIR {
            return try children(of: url).reduce(0) { try $0 + reclaimableBytes(at: $1) }
        }
        guard file.type == S_IFREG, file.links == 1 else { return 0 }

        // Use only allocated bytes that APFS reports as exclusive to this file.
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = UInt32(ATTR_CMN_RETURNED_ATTRS)
        attributes.forkattr = UInt32(ATTR_CMNEXT_PRIVATESIZE)
        let valueOffset = MemoryLayout<UInt32>.size + MemoryLayout<attribute_set_t>.size
        var response = [UInt8](repeating: 0, count: valueOffset + MemoryLayout<off_t>.size)
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return getattrlist(
                path, &attributes, &response, response.count,
                UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW))
        }
        guard result == 0 else { return 0 }
        return response.withUnsafeBytes { bytes in
            let length = bytes.loadUnaligned(as: UInt32.self)
            let returned = bytes.loadUnaligned(
                fromByteOffset: MemoryLayout<UInt32>.size, as: attribute_set_t.self)
            guard length >= bytes.count, returned.forkattr & UInt32(ATTR_CMNEXT_PRIVATESIZE) != 0
            else { return 0 }
            return max(0, bytes.loadUnaligned(fromByteOffset: valueOffset, as: off_t.self))
        }
    }

    private func visit(
        _ url: URL, at relativePath: Data, addingTo states: inout [Data: FileState]
    )
        throws
    {
        let file = try FileState(url: url)
        try validate(file: file)
        states[relativePath] = file
        guard file.type == S_IFDIR else { return }
        for child in try children(of: url) {
            let path = relativePath + Data("/".utf8) + Data(child.lastPathComponent.utf8)
            try visit(child, at: path, addingTo: &states)
        }
    }

    private func hashFile(at url: URL, named name: String, into hash: inout Fingerprint) throws {
        let file = try FileState(url: url)
        try validate(file: file)
        hash.append(name)
        hash.append(UInt64(file.type))
        hash.append(UInt64(file.mode & 0o777))
        try hash.appendExtendedAttributes(at: url)
        switch file.type {
        case mode_t(S_IFDIR):
            let children = try children(of: url).sorted {
                $0.lastPathComponent.utf8.lexicographicallyPrecedes($1.lastPathComponent.utf8)
            }
            hash.append(UInt64(children.count))
            for child in children {
                try hashFile(at: child, named: child.lastPathComponent, into: &hash)
            }
        case mode_t(S_IFLNK):
            hash.append(try FileManager.default.destinationOfSymbolicLink(atPath: url.path))
        default:
            try hash.appendContents(of: url, count: UInt64(file.size))
        }
    }

    private func validate(file: FileState) throws {
        guard file.type == S_IFREG || file.type == S_IFDIR || file.type == S_IFLNK else {
            throw ArchiveError.unsupportedFile
        }
    }

    private func isFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
            && !name.utf8.contains(0)
    }

    private func children(of url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil, options: [])
    }

    private func createDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func removeIfPresent(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            // The copy may have inherited a Finder lock, read-only mode or ACL.
            // Change permissions only when deleting AppKite's own copy.
            try makeRemovable(url)
            try FileManager.default.removeItem(at: url)
        }
    }

    private func makeRemovable(_ url: URL) throws {
        let file = try FileState(url: url)
        let lockFlags = UInt32(UF_IMMUTABLE | UF_APPEND)
        if file.flags & lockFlags != 0 {
            let result = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return Int32(-1) }
                return lchflags(path, file.flags & ~lockFlags)
            }
            guard result == 0 else { throw Self.fileError() }
        }
        if file.type == S_IFDIR || file.type == S_IFREG {
            try clearAccessControlList(at: url)
        }
        guard file.type == S_IFDIR else { return }
        if file.mode & 0o700 != 0o700 {
            let result = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return Int32(-1) }
                return fchmodat(AT_FDCWD, path, file.mode | 0o700, AT_SYMLINK_NOFOLLOW)
            }
            guard result == 0 else { throw Self.fileError() }
        }
        for child in try children(of: url) {
            try makeRemovable(child)
        }
    }

    private func clearAccessControlList(at url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw ArchiveError.invalidItem }
            guard let current = acl_get_link_np(path, ACL_TYPE_EXTENDED) else {
                guard errno == ENOENT || errno == EOPNOTSUPP || errno == ENOTSUP else {
                    throw Self.fileError()
                }
                return
            }
            acl_free(UnsafeMutableRawPointer(current))
            guard let empty = acl_init(0) else { throw Self.fileError() }
            defer { acl_free(UnsafeMutableRawPointer(empty)) }
            guard acl_set_link_np(path, ACL_TYPE_EXTENDED, empty) == 0 else {
                throw Self.fileError()
            }
        }
    }

    private func itemDirectory(in directory: URL, id: UUID) -> URL {
        directory.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    private func itemContainer(in directory: URL, index: Int) -> URL {
        directory.appending(path: "item-\(index)", directoryHint: .isDirectory)
    }

    private func manifestURL(in directory: URL) -> URL {
        directory.appending(path: "manifest.json", directoryHint: .notDirectory)
    }

    private func representationURL(in container: URL, index: Int) -> URL {
        container.appending(path: "representation-\(index)", directoryHint: .notDirectory)
    }

    private func fileURL(in container: URL, named name: String) -> URL {
        container.appending(path: "file", directoryHint: .isDirectory).appending(path: name)
    }

    private static func fileError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
