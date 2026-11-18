@MainActor
protocol ClipboardCollectionSource {
    var changeCount: Int { get }
    var readStatus: ClipboardReadStatus { get }
    var invalidFileSelectionChangeCount: Int? { get }

    func ignoreCurrentContents()
    func isCurrent(changeCount: Int) -> Bool
    func pollPayload(
        ignoringConfidentialCopies: Bool, isSourceExcluded: (String) -> Bool
    ) -> ClipboardCopy?
}

enum ClipboardReadStatus {
    case available
    case denied
    case failed
    case invalidFileSelection
}
