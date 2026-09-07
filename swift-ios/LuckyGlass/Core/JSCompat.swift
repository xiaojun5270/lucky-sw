import Foundation

/// JavaScript string / number semantics the port depends on.
///
/// These are deliberately faithful rather than idiomatic: `encodeURIComponent` escapes
/// `/` and `:` (Swift's `.urlQueryAllowed` does not), `toFixed` rounds half away from
/// zero like JavaScript, and log splitting must accept both `\n` and `\r\n`.
enum JSCompat {
    /// The ASCII letters and digits both escape tables start from.
    static let alphanumeric = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

    /// `encodeURIComponent` — everything except `A-Z a-z 0-9 - _ . ! ~ * ' ( )` is escaped.
    static let unreserved: CharacterSet = {
        var set = CharacterSet(charactersIn: alphanumeric)
        set.insert(charactersIn: "-_.!~*'()")
        return set
    }()

    static func encodeURIComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    static func decodeURIComponent(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }

    /// `Number(value).toFixed(digits)`
    static func toFixed(_ value: Double, _ digits: Int) -> String {
        guard value.isFinite else {
            if value.isNaN { return "NaN" }
            return value > 0 ? "Infinity" : "-Infinity"
        }
        return String(format: "%.\(max(0, digits))f", value)
    }

    /// `Number(text)` — **NaN for junk**, unlike `JSONValue.asNumber`, which mirrors
    /// `Number(v) || 0`. The log helpers need the distinction: `Number('')` is 0 and counts
    /// as a valid count, while `Number('abc')` is NaN and must be skipped.
    static func number(_ text: String) -> Double {
        let trimmed = text.jsTrimmed
        if trimmed.isEmpty { return 0 }
        // Swift accepts `inf`, `infinity` and `nan` in any case; JavaScript only accepts
        // `Infinity` with an optional sign.
        let lowered = trimmed.lowercased()
        if lowered.hasSuffix("inf") || lowered.hasSuffix("infinity") || lowered.hasSuffix("nan") {
            switch trimmed {
            case "Infinity", "+Infinity": return .infinity
            case "-Infinity": return -.infinity
            default: return .nan
            }
        }
        return Double(trimmed) ?? .nan
    }

    /// `Number.parseInt(text, 10)` — an optional sign and then as many digits as it finds, stopping
    /// at the first character that is not one, so `3x` is 3 while `x3` is NaN.
    ///
    /// The accumulation is in `Double` on purpose: a run of digits too long for the type overflows
    /// to infinity, which is what `parseInt` also answers, and callers test with `isFinite` exactly
    /// as the original tests with `Number.isInteger`.
    static func parseInt(_ text: String) -> Double {
        var rest = Substring(text.jsTrimmed)
        var sign = 1.0
        if rest.first == "+" || rest.first == "-" {
            if rest.first == "-" { sign = -1 }
            rest = rest.dropFirst()
        }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return .nan }
        var value = 0.0
        for digit in digits { value = value * 10 + Double(digit.wholeNumberValue ?? 0) }
        return sign * value
    }

    /// `new URLSearchParams(...).toString()` — form encoding, which differs from
    /// `encodeURIComponent`: a space becomes `+` and `!'()~` are escaped. Only the tunnel
    /// service builds query strings this way.
    static func formURLEncoded(_ pairs: [(String, String)]) -> String {
        pairs.map { "\(formEscape($0.0))=\(formEscape($0.1))" }.joined(separator: "&")
    }

    private static let formUnreserved: CharacterSet = {
        var set = CharacterSet(charactersIn: alphanumeric)
        set.insert(charactersIn: "*-._")
        return set
    }()

    private static func formEscape(_ value: String) -> String {
        let escaped = value.addingPercentEncoding(withAllowedCharacters: formUnreserved) ?? value
        return escaped.replacingOccurrences(of: "%20", with: "+")
    }
}

enum JSRegex {
    /// `/-?\d+(?:\.\d+)?/` — the first number embedded in a string.
    static func firstNumber(in text: String) -> Double? {
        var digits = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isNumber, character.isASCII {
                var start = index
                if start > text.startIndex {
                    let previous = text.index(before: start)
                    if text[previous] == "-" { start = previous }
                }
                var end = index
                var sawDot = false
                while end < text.endIndex {
                    let scan = text[end]
                    if scan.isNumber, scan.isASCII {
                        end = text.index(after: end)
                    } else if scan == ".", !sawDot,
                              text.index(after: end) < text.endIndex,
                              text[text.index(after: end)].isNumber {
                        sawDot = true
                        end = text.index(after: end)
                    } else {
                        break
                    }
                }
                digits = String(text[start..<end])
                break
            }
            index = text.index(after: index)
        }
        return digits.isEmpty ? nil : Double(digits)
    }

    /// Case-insensitive substring test, standing in for `/pattern/i.test(value)` where the
    /// pattern is a plain alternation of literals.
    static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        let lowered = text.lowercased()
        return needles.contains { lowered.contains($0.lowercased()) }
    }

    /// `/^\d+$/.test(value)`
    static func isDigitsOnly(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

extension String {
    /// `value.trim()`
    var jsTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// `value.trimEnd()`
    var jsTrimmedEnd: String {
        var result = self
        while let last = result.last, last.isWhitespace { result.removeLast() }
        return result
    }

    /// `value.replace(/\/+$/, '')` — used to normalise the Lucky base URL.
    var withoutTrailingSlashes: String {
        var result = self
        while result.hasSuffix("/") { result.removeLast() }
        return result
    }

    /// `value.split(/\r?\n/)`
    var jsLines: [String] {
        replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    /// `value.replace(/\D/g, '')` — `\D` is `[^0-9]`, so a full-width digit is stripped too.
    var jsDigitsOnly: String { filter { $0.isASCII && $0.isNumber } }

    /// `value.replace(/^0+(?=\d)/, '')`
    var withoutLeadingZeros: String {
        var result = self
        while result.count > 1, result.hasPrefix("0") { result.removeFirst() }
        return result
    }

    /// `left.localeCompare(right)` — ordering only, not a collation guarantee.
    func jsLocaleCompare(_ other: String) -> Int {
        if self == other { return 0 }
        let order = compare(other, options: [], range: nil, locale: Locale(identifier: "zh-CN"))
        return order == .orderedAscending ? -1 : 1
    }
}
