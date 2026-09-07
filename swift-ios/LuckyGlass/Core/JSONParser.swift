import Foundation

enum JSONParseError: Error, LocalizedError {
    case syntax(String)

    var errorDescription: String? {
        switch self { case .syntax(let detail): return detail }
    }
}

/// Minimal RFC 8259 parser.
///
/// `JSONSerialization` is not used because it discards object key order, which the
/// structured form and query builder both surface to the user, and because it maps
/// numbers to `NSNumber` subtypes that make it hard to reproduce JavaScript's
/// `JSON.stringify` output byte for byte (needed for the Docker search filter).
struct JSONParser {
    private let bytes: [UInt8]
    private var index = 0

    private init(bytes: [UInt8]) { self.bytes = bytes }

    static func parse(_ data: Data) throws -> JSONValue {
        var parser = JSONParser(bytes: [UInt8](data))
        parser.skipWhitespace()
        let value = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw JSONParseError.syntax("尾部存在多余数据") }
        return value
    }

    static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    /// `JSON.parse` that returns `nil` instead of throwing.
    static func tryParse(_ data: Data) -> JSONValue? { try? parse(data) }
    static func tryParse(_ text: String) -> JSONValue? { try? parse(text) }

    // MARK: - Scanner

    private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

    private mutating func skipWhitespace() {
        while let byte = current, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { index += 1 }
    }

    private mutating func expect(_ byte: UInt8) throws {
        guard current == byte else {
            throw JSONParseError.syntax("位置 \(index) 处需要 '\(Character(UnicodeScalar(byte)))'")
        }
        index += 1
    }

    private mutating func match(_ literal: [UInt8]) -> Bool {
        guard index + literal.count <= bytes.count else { return false }
        for (offset, byte) in literal.enumerated() where bytes[index + offset] != byte { return false }
        index += literal.count
        return true
    }

    private mutating func parseValue() throws -> JSONValue {
        guard let byte = current else { throw JSONParseError.syntax("数据意外结束") }
        switch byte {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"):
            guard match(Array("true".utf8)) else { throw JSONParseError.syntax("位置 \(index) 处的字面量无效") }
            return .bool(true)
        case UInt8(ascii: "f"):
            guard match(Array("false".utf8)) else { throw JSONParseError.syntax("位置 \(index) 处的字面量无效") }
            return .bool(false)
        case UInt8(ascii: "n"):
            guard match(Array("null".utf8)) else { throw JSONParseError.syntax("位置 \(index) 处的字面量无效") }
            return .null
        default: return .number(try parseNumber())
        }
    }

    private mutating func parseObject() throws -> JSONValue {
        try expect(UInt8(ascii: "{"))
        var object = JSONObject()
        skipWhitespace()
        if current == UInt8(ascii: "}") { index += 1; return .object(object) }
        while true {
            skipWhitespace()
            let key = try parseString()
            skipWhitespace()
            try expect(UInt8(ascii: ":"))
            skipWhitespace()
            object[key] = try parseValue()
            skipWhitespace()
            if current == UInt8(ascii: ",") { index += 1; continue }
            try expect(UInt8(ascii: "}"))
            return .object(object)
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        try expect(UInt8(ascii: "["))
        var items: [JSONValue] = []
        skipWhitespace()
        if current == UInt8(ascii: "]") { index += 1; return .array(items) }
        while true {
            skipWhitespace()
            items.append(try parseValue())
            skipWhitespace()
            if current == UInt8(ascii: ",") { index += 1; continue }
            try expect(UInt8(ascii: "]"))
            return .array(items)
        }
    }

    private mutating func parseNumber() throws -> Double {
        let start = index
        if current == UInt8(ascii: "-") || current == UInt8(ascii: "+") { index += 1 }
        while let byte = current, (byte >= 0x30 && byte <= 0x39) || byte == UInt8(ascii: ".")
            || byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E")
            || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+") { index += 1 }
        guard index > start, let text = String(bytes: bytes[start..<index], encoding: .utf8),
              let value = Double(text) else {
            throw JSONParseError.syntax("位置 \(start) 处的数字无效")
        }
        return value
    }

    /// Literal bytes (including UTF-8 continuation bytes) are copied straight through;
    /// only `\u` escapes need code-unit handling, so surrogate pairs are folded into a
    /// single scalar before being re-encoded as UTF-8.
    private mutating func parseString() throws -> String {
        try expect(UInt8(ascii: "\""))
        var out: [UInt8] = []
        while true {
            guard let byte = current else { throw JSONParseError.syntax("字符串未闭合") }
            index += 1
            if byte == UInt8(ascii: "\"") { break }
            guard byte == UInt8(ascii: "\\") else { out.append(byte); continue }
            guard let escape = current else { throw JSONParseError.syntax("转义序列未完成") }
            index += 1
            switch escape {
            case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(escape)
            case UInt8(ascii: "b"): out.append(0x08)
            case UInt8(ascii: "f"): out.append(0x0C)
            case UInt8(ascii: "n"): out.append(0x0A)
            case UInt8(ascii: "r"): out.append(0x0D)
            case UInt8(ascii: "t"): out.append(0x09)
            case UInt8(ascii: "u"): appendUTF8(try parseEscapedScalar(), to: &out)
            default: throw JSONParseError.syntax("不支持的转义字符")
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private mutating func parseEscapedScalar() throws -> UInt32 {
        let first = UInt32(try parseHexQuad())
        guard (0xD800...0xDBFF).contains(first) else {
            return (0xDC00...0xDFFF).contains(first) ? 0xFFFD : first
        }
        let resume = index
        guard current == UInt8(ascii: "\\"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "u") else {
            return 0xFFFD
        }
        index += 2
        let low = UInt32(try parseHexQuad())
        guard (0xDC00...0xDFFF).contains(low) else {
            index = resume
            return 0xFFFD
        }
        return 0x10000 + ((first - 0xD800) << 10) + (low - 0xDC00)
    }

    private mutating func parseHexQuad() throws -> UInt16 {
        guard index + 4 <= bytes.count, let text = String(bytes: bytes[index..<(index + 4)], encoding: .utf8),
              let value = UInt16(text, radix: 16) else { throw JSONParseError.syntax("\\u 转义无效") }
        index += 4
        return value
    }

    private func appendUTF8(_ scalar: UInt32, to out: inout [UInt8]) {
        switch scalar {
        case 0..<0x80:
            out.append(UInt8(scalar))
        case 0x80..<0x800:
            out.append(UInt8(0xC0 | (scalar >> 6)))
            out.append(UInt8(0x80 | (scalar & 0x3F)))
        case 0x800..<0x10000:
            out.append(UInt8(0xE0 | (scalar >> 12)))
            out.append(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
            out.append(UInt8(0x80 | (scalar & 0x3F)))
        default:
            out.append(UInt8(0xF0 | (scalar >> 18)))
            out.append(UInt8(0x80 | ((scalar >> 12) & 0x3F)))
            out.append(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
            out.append(UInt8(0x80 | (scalar & 0x3F)))
        }
    }
}
