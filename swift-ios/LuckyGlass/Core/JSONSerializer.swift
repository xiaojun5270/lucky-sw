import Foundation

/// `JSON.stringify` equivalent.
///
/// Output has to match JavaScript's byte for byte because the original app compares
/// serialised payloads: the Docker screen's search filter is
/// `JSON.stringify(record).toLowerCase().includes(query)`, and several editors show
/// `JSON.stringify(value, null, 2)` as the text the user edits.
enum JSONSerializer {
    static func stringify(_ value: JSONValue) -> String {
        var out = ""
        write(value, indent: nil, level: 0, into: &out)
        return out
    }

    /// `JSON.stringify(value, null, 2)`
    static func prettyStringify(_ value: JSONValue, indent: Int = 2) -> String {
        var out = ""
        write(value, indent: indent, level: 0, into: &out)
        return out
    }

    static func data(_ value: JSONValue) -> Data { Data(stringify(value).utf8) }

    /// `String(number)` in JavaScript: integral values lose the fractional part, and
    /// non-finite values become `null` inside JSON.
    static func numberString(_ value: Double) -> String {
        guard value.isFinite else { return "null" }
        if value == value.rounded(), abs(value) < 1e21 {
            if value == 0 { return value.sign == .minus ? "0" : "0" }
            if abs(value) <= 9_007_199_254_740_992 { return String(Int64(value)) }
        }
        var text = value.description
        if text.hasSuffix(".0") { text.removeLast(2) }
        return text
    }

    // MARK: - Writer

    private static func write(_ value: JSONValue, indent: Int?, level: Int, into out: inout String) {
        switch value {
        case .null:
            out += "null"
        case .bool(let flag):
            out += flag ? "true" : "false"
        case .number(let number):
            out += numberString(number)
        case .string(let text):
            writeString(text, into: &out)
        case .binary(let data):
            // A Blob has no JSON representation; JavaScript would emit `{}`.
            _ = data
            out += "{}"
        case .array(let items):
            guard !items.isEmpty else { out += "[]"; return }
            out += "["
            for (offset, item) in items.enumerated() {
                if offset > 0 { out += "," }
                newline(indent: indent, level: level + 1, into: &out)
                write(item, indent: indent, level: level + 1, into: &out)
            }
            newline(indent: indent, level: level, into: &out)
            out += "]"
        case .object(let object):
            guard !object.isEmpty else { out += "{}"; return }
            out += "{"
            for (offset, pair) in object.pairs.enumerated() {
                if offset > 0 { out += "," }
                newline(indent: indent, level: level + 1, into: &out)
                writeString(pair.key, into: &out)
                out += indent == nil ? ":" : ": "
                write(pair.value, indent: indent, level: level + 1, into: &out)
            }
            newline(indent: indent, level: level, into: &out)
            out += "}"
        }
    }

    private static func newline(indent: Int?, level: Int, into out: inout String) {
        guard let indent else { return }
        out += "\n"
        out += String(repeating: " ", count: indent * level)
    }

    private static func writeString(_ text: String, into out: inout String) {
        out += "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }
}
