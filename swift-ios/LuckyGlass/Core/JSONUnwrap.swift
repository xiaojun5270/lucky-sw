import Foundation

/// Tolerant payload unwrapping.
///
/// Lucky returns list data under whatever key the module happens to use, sometimes
/// nested one to five levels deep inside `data` / `result` / `response` / `payload`
/// wrappers. The TypeScript client breadth-first searches for the first non-empty
/// array, preferring those wrapper keys, and falls back to an empty array it saw
/// along the way. Each module tuned its own depth limit and root behaviour, so the
/// search is parameterised here rather than unified — the differences are visible in
/// the UI when a payload is unusual.
enum JSONUnwrap {
    static let wrapperKeys: Set<String> = ["data", "result", "response", "payload"]

    /// `/^(?:data|result|response|payload)$/i`
    static func isWrapperKey(_ key: String) -> Bool { wrapperKeys.contains(key.lowercased()) }

    /// Breadth-first search for an array.
    ///
    /// - Parameters:
    ///   - keys: candidate key names, matched case-insensitively.
    ///   - maxDepth: nodes at this depth are matched but not expanded (`depth >= max` → skip).
    ///   - rootAllowsArray: whether a top-level array counts as a match (`list()` allows it,
    ///     `nestedArray()` does not).
    ///   - recordsOnly: filter non-object elements out *before* testing for emptiness, so an
    ///     array of strings reads as an empty match.
    ///
    /// JSON payloads are trees, so the original's identity-based `visited` set has no
    /// Swift equivalent and is unnecessary: `maxDepth` already bounds the walk.
    static func findArray(
        _ payload: JSONValue,
        keys: [String],
        maxDepth: Int = 4,
        rootAllowsArray: Bool = false,
        recordsOnly: Bool = false
    ) -> [JSONValue]? {
        let wanted = Set(keys.map { $0.lowercased() })
        var queue: [(value: JSONValue, depth: Int, allowArray: Bool)] = [(payload, 0, rootAllowsArray)]
        var head = 0
        var emptyMatch: [JSONValue]?

        while head < queue.count {
            let (value, depth, allowArray) = queue[head]
            head += 1

            if case .array(let items) = value {
                let matched = recordsOnly ? items.filter(\.isRecord) : items
                if allowArray {
                    if !matched.isEmpty { return matched }
                    if emptyMatch == nil { emptyMatch = matched }
                }
                if depth >= maxDepth { continue }
                for item in items { queue.append((item, depth + 1, false)) }
                continue
            }

            guard case .object(let object) = value else { continue }

            for (key, candidate) in object.pairs where wanted.contains(key.lowercased()) {
                guard case .array(let items) = candidate else { continue }
                let matched = recordsOnly ? items.filter(\.isRecord) : items
                if !matched.isEmpty { return matched }
                if emptyMatch == nil { emptyMatch = matched }
            }

            if depth >= maxDepth { continue }

            // Wrapper keys are explored first. `Array.prototype.sort` is stable in
            // JavaScript but `sorted(by:)` is not, so the original index breaks ties.
            let nested = object.pairs.enumerated()
                .filter { $0.element.value.isRecord || $0.element.value.isArray }
                .sorted { left, right in
                    let leftRank = isWrapperKey(left.element.key) ? 0 : 1
                    let rightRank = isWrapperKey(right.element.key) ? 0 : 1
                    return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
                }
            for entry in nested {
                queue.append((entry.element.value, depth + 1, isWrapperKey(entry.element.key)))
            }
        }
        return emptyMatch
    }

    /// `firstArray` in `services/lucky.ts` — the found array, keeping only records.
    static func recordArray(_ payload: JSONValue, keys: [String]) -> [JSONValue] {
        (findArray(payload, keys: keys) ?? []).filter(\.isRecord)
    }

    /// `list` in `services/webservice.ts` — depth 5, a top-level array is accepted,
    /// and non-records are filtered before the emptiness test.
    static func list(_ payload: JSONValue, keys: [String]) -> [JSONValue] {
        findArray(payload, keys: keys, maxDepth: 5, rootAllowsArray: true, recordsOnly: true) ?? []
    }

    /// `record(payload, keys)` in `services/webservice.ts`: for each key in turn, breadth-first
    /// search (case-insensitive, depth ≤ 5) for a nested record; the first key that matches wins.
    /// The result is a shallow copy with the `ret` / `msg` envelope fields removed.
    static func nestedRecord(_ payload: JSONValue, keys: [String]) -> JSONValue {
        var value = payload
        for wantedKey in keys {
            if let found = breadthFirstRecord(payload, key: wantedKey) {
                value = found
                break
            }
        }
        var result = value.record
        result.removeValue(forKey: "ret")
        result.removeValue(forKey: "msg")
        return .object(result)
    }

    private static func breadthFirstRecord(_ payload: JSONValue, key wantedKey: String) -> JSONValue? {
        var queue: [(value: JSONValue, depth: Int)] = [(payload, 0)]
        var head = 0
        while head < queue.count {
            let (value, depth) = queue[head]
            head += 1
            guard case .object(let object) = value else { continue }
            for (key, candidate) in object.pairs
            where key.lowercased() == wantedKey.lowercased() && candidate.isRecord {
                return candidate
            }
            if depth >= 5 { continue }
            for (_, candidate) in object.pairs where candidate.isRecord {
                queue.append((candidate, depth + 1))
            }
        }
        return nil
    }

    /// `pick(item, keys, fallback)` — first string/number field, or a comma-joined array.
    static func pick(_ item: JSONValue, _ keys: [String], _ fallback: String = "") -> String {
        for key in keys {
            guard let value = item[key] else { continue }
            switch value {
            case .string(let text): return text
            case .number(let number): return JSONSerializer.numberString(number)
            case .array(let items) where !items.isEmpty:
                return items.map(\.asDisplayString).joined(separator: ", ")
            default: continue
            }
        }
        return fallback
    }

    /// Case-insensitive deep lookup for a single key (`deepDockerValue`).
    /// The first record that owns a matching key wins, even if its value is null —
    /// callers type-check the result themselves.
    static func deepValue(_ source: JSONValue, key: String) -> JSONValue? {
        let wanted = key.lowercased()
        var queue: [JSONValue] = [source]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            switch current {
            case .array(let items):
                queue.append(contentsOf: items)
            case .object(let object):
                if let match = object.keys.first(where: { $0.lowercased() == wanted }) {
                    return object[match]
                }
                queue.append(contentsOf: object.values)
            default:
                continue
            }
        }
        return nil
    }

    /// `dockerNumber` — first deep key that yields a finite number, digits scraped out of
    /// strings such as `"1,024 MiB"`.
    static func deepNumber(_ source: JSONValue, keys: [String]) -> Double? {
        for key in keys {
            guard let value = deepValue(source, key: key) else { continue }
            if case .number(let number) = value, number.isFinite { return number }
            if case .string(let text) = value,
               let match = JSRegex.firstNumber(in: text.replacingOccurrences(of: ",", with: "")) {
                return match
            }
        }
        return nil
    }
}
