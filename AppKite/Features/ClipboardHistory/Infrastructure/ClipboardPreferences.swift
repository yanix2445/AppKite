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

@MainActor
struct ClipboardPreferences {
    private static let shortcutKey = "clipboardHistory.shortcut"
    private static let pauseKey = "clipboardHistory.pause"
    private static let exclusionsKey = "clipboardHistory.excludedApplications"
    private static let confidentialCopiesKey = "clipboardHistory.ignoresConfidentialCopies"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shortcut: ClipboardShortcut {
        get { decode(ClipboardShortcut.self, forKey: Self.shortcutKey) ?? .defaultShortcut }
        nonmutating set { encode(newValue, forKey: Self.shortcutKey) }
    }

    var pause: ClipboardCollectionPause? {
        get { decode(ClipboardCollectionPause.self, forKey: Self.pauseKey) }
        nonmutating set {
            if let newValue {
                encode(newValue, forKey: Self.pauseKey)
            } else {
                defaults.removeObject(forKey: Self.pauseKey)
            }
        }
    }

    var excludedApplications: [ClipboardExcludedApplication] {
        get { decode([ClipboardExcludedApplication].self, forKey: Self.exclusionsKey) ?? [] }
        nonmutating set { encode(newValue, forKey: Self.exclusionsKey) }
    }

    var ignoresConfidentialCopies: Bool {
        get {
            defaults.object(forKey: Self.confidentialCopiesKey) == nil
                || defaults.bool(forKey: Self.confidentialCopiesKey)
        }
        nonmutating set { defaults.set(newValue, forKey: Self.confidentialCopiesKey) }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
