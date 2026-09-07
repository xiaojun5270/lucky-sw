import Foundation

/// Dynamic JSON value.
///
/// The Lucky server has no stable response schema: the same list endpoint may
/// return the array at the top level, under `data`, under `data.list`, or under a
/// module-specific key, and numeric fields arrive as either numbers or strings.
/// The TypeScript client therefore types everything as `Record<string, unknown>`
/// and unwraps defensively. `JSONValue` is the Swift equivalent — modelling these
/// responses with fixed `Codable` structs would drop payloads the original app
/// displays.
///
/// `.binary` is not a JSON case; it carries a downloaded file body so the fetch
/// layer can keep the original `{ ret: 0, data: blob, ... }` envelope shape.
indirect enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)
    case binary(Data)

    // MARK: - Construction

    init(_ value: Bool) { self = .bool(value) }
    init(_ value: Double) { self = .number(value) }
    init(_ value: Int) { self = .number(Double(value)) }
    init(_ value: String) { self = .string(value) }
    init(_ value: [JSONValue]) { self = .array(value) }
    init(_ value: JSONObject) { self = .object(value) }

    static func int(_ value: Int) -> JSONValue { .number(Double(value)) }

    // MARK: - Kind tests

    var isNull: Bool { if case .null = self { return true } else { return false } }

    /// Matches the original `isRecord` guard: a plain object, not an array.
    var isRecord: Bool { if case .object = self { return true } else { return false } }

    var isArray: Bool { if case .array = self { return true } else { return false } }

    /// `typeof value === 'string'`
    var isString: Bool { if case .string = self { return true } else { return false } }

    /// `typeof value === 'number' && Number.isFinite(value)`
    var isFiniteNumber: Bool {
        if case .number(let value) = self { return value.isFinite }
        return false
    }

    var isBool: Bool { if case .bool = self { return true } else { return false } }

    // MARK: - Typed access

    var objectValue: JSONObject? { if case .object(let value) = self { return value } else { return nil } }
    var arrayValue: [JSONValue]? { if case .array(let value) = self { return value } else { return nil } }
    var stringValue: String? { if case .string(let value) = self { return value } else { return nil } }
    var boolValue: Bool? { if case .bool(let value) = self { return value } else { return nil } }
    var dataValue: Data? { if case .binary(let value) = self { return value } else { return nil } }

    var doubleValue: Double? {
        if case .number(let value) = self { return value } else { return nil }
    }

    /// `record(value)` in the original: an object, or `{}` for anything else.
    var record: JSONObject { objectValue ?? JSONObject() }

    /// `array(value)` in the original: an array, or `[]` for anything else.
    var list: [JSONValue] { arrayValue ?? [] }

    subscript(key: String) -> JSONValue? {
        get { objectValue?[key] }
        set {
            var object = objectValue ?? JSONObject()
            object[key] = newValue
            self = .object(object)
        }
    }

    subscript(index: Int) -> JSONValue? {
        guard case .array(let items) = self, index >= 0, index < items.count else { return nil }
        return items[index]
    }

    // MARK: - JavaScript-compatible coercions

    /// `Number(value) || 0` — strings are parsed, booleans and null collapse to 0.
    /// `Number('')` is 0 in JavaScript, and `|| 0` also turns `NaN` into 0.
    var asNumber: Double {
        switch self {
        case .number(let value): return value.isFinite ? value : 0
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return 0 }
            guard let parsed = Double(trimmed), parsed.isFinite else { return 0 }
            return parsed
        case .bool(let value): return value ? 1 : 0
        default: return 0
        }
    }

    var asInt: Int {
        let value = asNumber
        guard value.isFinite, value >= -9.007e15, value <= 9.007e15 else { return 0 }
        return Int(value)
    }

    /// `String(value)` — used wherever the original interpolates an unknown value.
    var asDisplayString: String {
        switch self {
        case .null: return ""
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return JSONSerializer.numberString(value)
        case .string(let value): return value
        case .array, .object: return JSONSerializer.stringify(self)
        case .binary(let data): return "[\(data.count) bytes]"
        }
    }

    /// `Boolean(value)` — JavaScript truthiness, used by `value ? a : b` guards.
    var isTruthy: Bool {
        switch self {
        case .null: return false
        case .bool(let value): return value
        case .number(let value): return value != 0 && !value.isNaN
        case .string(let value): return !value.isEmpty
        case .array, .object: return true
        case .binary(let data): return !data.isEmpty
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                     ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral,
                     ExpressibleByNilLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(nilLiteral: ()) { self = .null }
}
