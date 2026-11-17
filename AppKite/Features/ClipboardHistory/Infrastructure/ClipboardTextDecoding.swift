import AppKit
import UniformTypeIdentifiers

nonisolated enum ClipboardTextDecoding {
    static func text(from representation: ClipboardPayload.Representation, byteLimit: Int? = nil)
        -> String?
    {
        let data = representation.data
        let prefix = byteLimit.map { data.prefix($0) } ?? data
        let isClipped = prefix.count < data.count
        switch representation.type {
        case UTType.utf16PlainText.identifier, UTType.utf16ExternalPlainText.identifier:
            return decode(prefix, as: .utf16, isClipped: isClipped)
        case ClipboardPayload.utf8TextType, UTType.plainText.identifier,
            NSPasteboard.PasteboardType.URL.rawValue, "public.url-name",
            NSPasteboard.PasteboardType.tabularText.rawValue,
            UTType.tabSeparatedText.identifier, UTType.commaSeparatedText.identifier:
            if prefix.starts(with: [0xFF, 0xFE]) || prefix.starts(with: [0xFE, 0xFF]) {
                return decode(prefix, as: .utf16, isClipped: isClipped)
            }
            return decode(prefix, as: .utf8, isClipped: isClipped)
                ?? decode(prefix, as: .utf16, isClipped: isClipped)
        default:
            return nil
        }
    }

    private static func decode(_ data: Data, as encoding: String.Encoding, isClipped: Bool)
        -> String?
    {
        if !isClipped { return String(data: data, encoding: encoding) }
        for trailingBytes in 0...min(3, data.count) {
            if let value = String(data: data.dropLast(trailingBytes), encoding: encoding) {
                // A complete scalar at the limit may still be part of an unfinished grapheme.
                // Keep a complete row terminator even when the next row is clipped.
                return value.last?.isNewline == true ? value : String(value.dropLast())
            }
        }
        return nil
    }
}
