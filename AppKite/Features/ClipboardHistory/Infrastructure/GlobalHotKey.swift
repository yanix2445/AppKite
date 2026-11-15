import AppKit
import Carbon
import CoreGraphics

nonisolated struct ClipboardShortcut: Codable, Equatable, Sendable {
    fileprivate let keyCode: UInt32
    fileprivate let modifiers: UInt32
    private let keyLabel: String

    @MainActor
    static var defaultShortcut: Self {
        let keyCode = Self.keyCode(for: "v", modifiers: []) ?? CGKeyCode(kVK_ANSI_V)
        return Self(
            keyCode: UInt32(keyCode), modifiers: UInt32(shiftKey | optionKey), keyLabel: "V")
    }

    @MainActor
    static func keyCode(for character: String, modifiers: NSEvent.ModifierFlags) -> CGKeyCode? {
        for key in 0..<128 {
            let keyCode = CGKeyCode(key)
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
                NSEvent(cgEvent: event)?.characters(byApplyingModifiers: modifiers) == character
            else { continue }
            return keyCode
        }
        return nil
    }

    var label: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel
    }

    @MainActor
    init?(event: NSEvent) {
        guard event.type == .keyDown, !event.isARepeat else { return nil }
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers != 0, let characters = event.charactersIgnoringModifiers,
            let scalar = characters.unicodeScalars.first, characters.unicodeScalars.count == 1,
            let keyLabel = Self.label(for: scalar)
        else { return nil }

        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: keyLabel)
    }

    private init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    private static func label(for scalar: Unicode.Scalar) -> String? {
        switch scalar.value {
        case 0x09: "⇥"
        case 0x0D: "↩"
        case 0x20: "Espace"
        case 0x7F: "⌫"
        case 0xF700: "↑"
        case 0xF701: "↓"
        case 0xF702: "←"
        case 0xF703: "→"
        case 0xF704...0xF726: "F\(scalar.value - 0xF703)"
        case 0xF700...0xF8FF: nil
        default: CharacterSet.controlCharacters.contains(scalar) ? nil : String(scalar).uppercased()
        }
    }
}

@MainActor
final class GlobalHotKey {
    private struct RegistrationError: LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            if status == eventHotKeyExistsErr {
                return "Ce raccourci est déjà utilisé."
            }
            return "Impossible d’enregistrer ce raccourci (\(status))."
        }
    }

    private static let signature: OSType = 0x414B_4348
    private let onPressed: @MainActor () -> Void
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var registeredShortcut: ClipboardShortcut?
    private var registrationID: UInt32 = 0

    init(onPressed: @escaping @MainActor () -> Void) {
        self.onPressed = onPressed
    }

    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    func register(_ shortcut: ClipboardShortcut) throws {
        if registeredShortcut?.keyCode == shortcut.keyCode,
            registeredShortcut?.modifiers == shortcut.modifiers
        {
            return
        }
        try installHandler()

        let nextID = registrationID &+ 1
        let identifier = EventHotKeyID(signature: Self.signature, id: nextID)
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &replacement
        )
        guard status == noErr, let replacement else {
            throw RegistrationError(status: status)
        }

        if let hotKey {
            let status = UnregisterEventHotKey(hotKey)
            guard status == noErr else {
                UnregisterEventHotKey(replacement)
                throw RegistrationError(status: status)
            }
        }

        hotKey = replacement
        registeredShortcut = shortcut
        registrationID = nextID
    }

    private func installHandler() throws {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr else { return status }

                // The application event target dispatches through AppKit's main event loop.
                return MainActor.assumeIsolated {
                    let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                    guard identifier.signature == GlobalHotKey.signature,
                        identifier.id == owner.registrationID
                    else {
                        return OSStatus(eventNotHandledErr)
                    }
                    owner.onPressed()
                    return OSStatus(noErr)
                }
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else { throw RegistrationError(status: status) }
    }
}
