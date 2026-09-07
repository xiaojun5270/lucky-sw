import Foundation

/// Insertion-ordered string-keyed map.
///
/// The TypeScript original is built on `Record<string, unknown>` and relies on
/// JavaScript object key ordering in several visible places: the structured form
/// renders fields in insertion order, `StructuredDataView` lists them in the same
/// order, and the endpoint debugger's "object mode" query builder emits query
/// parameters in the order the user typed them. A Swift `Dictionary` would shuffle
/// all of that, so JSON objects are modelled with this ordered container instead.
struct JSONObject: Hashable, Sendable {
    private(set) var keys: [String] = []
    private var storage: [String: JSONValue] = [:]

    init() {}

    init(_ pairs: [(String, JSONValue)]) {
        for (key, value) in pairs { self[key] = value }
    }

    init(_ pairs: KeyValuePairs<String, JSONValue>) {
        for (key, value) in pairs { self[key] = value }
    }

    var isEmpty: Bool { keys.isEmpty }
    var count: Int { keys.count }
    var values: [JSONValue] { keys.compactMap { storage[$0] } }
    var pairs: [(key: String, value: JSONValue)] { keys.map { ($0, storage[$0] ?? .null) } }

    subscript(key: String) -> JSONValue? {
        get { storage[key] }
        set {
            if let newValue {
                if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    func has(_ key: String) -> Bool { storage[key] != nil }

    mutating func removeValue(forKey key: String) {
        self[key] = nil
    }

    /// Rename a key while keeping its position — used by the structured form editor.
    mutating func renameKey(_ key: String, to newKey: String) {
        guard key != newKey, let value = storage[key], storage[newKey] == nil,
              let index = keys.firstIndex(of: key) else { return }
        storage.removeValue(forKey: key)
        storage[newKey] = value
        keys[index] = newKey
    }

    /// `{ ...self, ...other }`
    func merging(_ other: JSONObject) -> JSONObject {
        var result = self
        for (key, value) in other.pairs { result[key] = value }
        return result
    }

    func filter(_ isIncluded: (String, JSONValue) -> Bool) -> JSONObject {
        var result = JSONObject()
        for (key, value) in pairs where isIncluded(key, value) { result[key] = value }
        return result
    }
}

extension JSONObject: Sequence {
    func makeIterator() -> AnyIterator<(key: String, value: JSONValue)> {
        var index = 0
        return AnyIterator {
            guard index < keys.count else { return nil }
            let key = keys[index]
            index += 1
            return (key, storage[key] ?? .null)
        }
    }
}

extension JSONObject: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.init(elements)
    }
}

/// An array literal of pairs, so response envelopes can be written as
/// `.object([("ret", .number(0)), ("data", payload)])` and keep their written order.
/// A dictionary literal would read better but Swift's is unordered at the source level
/// only by convention — an array of pairs makes the ordering guarantee explicit, and it
/// also permits `.object([])` for an empty envelope.
extension JSONObject: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: (String, JSONValue)...) {
        self.init(elements)
    }
}
