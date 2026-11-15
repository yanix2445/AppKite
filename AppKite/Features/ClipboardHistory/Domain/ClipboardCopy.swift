nonisolated struct ClipboardCopy: Sendable {
    let payload: ClipboardPayload
    let sourceBundleIdentifier: String?
    let probableSourceBundleIdentifier: String?
    var isRemote = false
}
