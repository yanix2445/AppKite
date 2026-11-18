import Foundation

enum ClipboardCollectionPause: Codable, Equatable {
    case manual
    case until(Date)

    func isActive(at date: Date) -> Bool {
        switch self {
        case .manual: true
        case .until(let deadline): date < deadline
        }
    }
}

struct ClipboardExcludedApplication: Codable, Equatable, Identifiable {
    let id: String
    let name: String
}

struct ClipboardCollectionPolicy: Equatable {
    enum Setting: Hashable {
        case pause
        case exclusions
    }

    var pause: ClipboardCollectionPause?
    var exclusions: [ClipboardExcludedApplication] = []
    var ignoresConfidentialCopies: Bool
    var invalidSettings: Set<Setting> = []

    var isPaused: Bool { pause != nil || !invalidSettings.isEmpty }
}
