import Foundation

@MainActor
struct ClipboardPreferences {
    private enum ReadError: Error {
        case invalidData
    }

    private static let shortcutKey = "clipboardHistory.shortcut"
    private static let pauseKey = "clipboardHistory.pause"
    private static let exclusionsKey = "clipboardHistory.excludedApplications"
    private static let confidentialCopiesKey = "clipboardHistory.ignoresConfidentialCopies"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shortcut: ClipboardShortcut {
        get { (try? decode(ClipboardShortcut.self, forKey: Self.shortcutKey)) ?? .defaultShortcut }
        nonmutating set { encode(newValue, forKey: Self.shortcutKey) }
    }

    var pause: ClipboardCollectionPause? {
        get throws { try decode(ClipboardCollectionPause.self, forKey: Self.pauseKey) }
    }

    func setPause(_ pause: ClipboardCollectionPause?) {
        if let pause {
            encode(pause, forKey: Self.pauseKey)
        } else {
            defaults.removeObject(forKey: Self.pauseKey)
        }
    }

    var excludedApplications: [ClipboardExcludedApplication] {
        get throws {
            try decode([ClipboardExcludedApplication].self, forKey: Self.exclusionsKey) ?? []
        }
    }

    func setExcludedApplications(_ applications: [ClipboardExcludedApplication]) {
        encode(applications, forKey: Self.exclusionsKey)
    }

    var ignoresConfidentialCopies: Bool {
        get {
            defaults.object(forKey: Self.confidentialCopiesKey) == nil
                || defaults.bool(forKey: Self.confidentialCopiesKey)
        }
        nonmutating set { defaults.set(newValue, forKey: Self.confidentialCopiesKey) }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, forKey key: String) throws -> Value? {
        guard let stored = defaults.object(forKey: key) else { return nil }
        guard let data = stored as? Data else { throw ReadError.invalidData }
        return try JSONDecoder().decode(type, from: data)
    }

    private func encode<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
