import Foundation

nonisolated enum ClipboardDelimitedText {
    enum Format: UInt8 {
        case csv = 0x2C
        case tsv = 0x09
    }

    static func previewRows(in text: String, format: Format, isClipped: Bool) -> [[String]]? {
        var text = text
        return text.withUTF8 { bytes in
            var scanner = Scanner(bytes: bytes, format: format)
            var rows: [[String]] = []
            var row: [String] = []
            do {
                while rows.count < 4, let field = try scanner.next() {
                    if row.count < 3 {
                        let raw = String(decoding: bytes[field.content], as: UTF8.self)
                        let text =
                            field.hasEscapedQuotes
                            ? raw.replacingOccurrences(of: "\"\"", with: "\"") : raw
                        row.append(String(text.prefix(120)))
                    }
                    if field.separator == .row || (field.separator == .end && !isClipped) {
                        rows.append(row)
                        row = []
                    }
                }
                return rows
            } catch {
                return isClipped ? rows : nil
            }
        }
    }

    static func tabSeparatedCSV(_ data: Data) -> Data? {
        let hasUTF16BOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
        guard var csv = String(data: data, encoding: hasUTF16BOM ? .utf16 : .utf8)
        else { return nil }

        return csv.withUTF8 { bytes in
            var scanner = Scanner(bytes: bytes, format: .csv)
            guard !scanner.isAtEnd else { return nil }
            var output = Data()
            output.reserveCapacity(bytes.count)
            do {
                while let field = try scanner.next() {
                    if field.needsTSVQuotes { output.append(quote) }
                    output.append(contentsOf: bytes[field.content])
                    if field.needsTSVQuotes { output.append(quote) }
                    switch field.separator {
                    case .column: output.append(Format.tsv.rawValue)
                    case .row where !scanner.isAtEnd: output.append(lineFeed)
                    case .row, .end: break
                    }
                }
                // Encode a final empty row explicitly so it is not read as a record terminator.
                if output.isEmpty || output.last == lineFeed {
                    output.append(quote)
                    output.append(quote)
                }
                return output
            } catch {
                return nil
            }
        }
    }

    private static let quote: UInt8 = 0x22
    private static let lineFeed: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D

    private enum Separator { case column, row, end }

    private struct Field {
        var content: Range<Int>
        var separator: Separator = .end
        var hasEscapedQuotes = false
        var needsTSVQuotes = false
    }

    private enum ParseError: Error { case invalidField }

    // Use bytes so CRLF and other delimiters are independent of Unicode grapheme boundaries.
    private struct Scanner {
        let bytes: UnsafeBufferPointer<UInt8>
        let format: Format
        private var index: Int
        private var hasTrailingEmptyCell = false

        init(bytes: UnsafeBufferPointer<UInt8>, format: Format) {
            self.bytes = bytes
            self.format = format
            index = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        }

        var isAtEnd: Bool { index == bytes.count }

        mutating func next() throws -> Field? {
            if isAtEnd {
                guard hasTrailingEmptyCell else { return nil }
                hasTrailingEmptyCell = false
                return Field(content: index..<index)
            }

            var field = try bytes[index] == quote ? quotedField() : unquotedField()
            guard !isAtEnd else { return field }
            let delimiter = bytes[index]
            index += 1
            switch delimiter {
            case format.rawValue:
                field.separator = .column
                hasTrailingEmptyCell = isAtEnd
            case carriageReturn, lineFeed:
                field.separator = .row
                if delimiter == carriageReturn, !isAtEnd, bytes[index] == lineFeed {
                    index += 1
                }
            default:
                throw ParseError.invalidField
            }
            return field
        }

        private mutating func quotedField() throws -> Field {
            index += 1
            let start = index
            var hasEscapedQuotes = false
            var hasTSVDelimiter = false
            while !isAtEnd {
                let byte = bytes[index]
                index += 1
                if byte == quote {
                    if isAtEnd || bytes[index] != quote {
                        return Field(
                            content: start..<(index - 1), hasEscapedQuotes: hasEscapedQuotes,
                            needsTSVQuotes: hasEscapedQuotes || hasTSVDelimiter)
                    }
                    index += 1
                    hasEscapedQuotes = true
                } else if byte == Format.tsv.rawValue || byte == lineFeed || byte == carriageReturn
                {
                    hasTSVDelimiter = true
                }
            }
            throw ParseError.invalidField
        }

        private mutating func unquotedField() throws -> Field {
            let start = index
            var hasTab = false
            while !isAtEnd {
                let byte = bytes[index]
                if byte == format.rawValue || byte == lineFeed || byte == carriageReturn { break }
                if format == .csv, byte == quote { throw ParseError.invalidField }
                hasTab = hasTab || byte == Format.tsv.rawValue
                index += 1
            }
            return Field(content: start..<index, needsTSVQuotes: hasTab)
        }
    }
}
