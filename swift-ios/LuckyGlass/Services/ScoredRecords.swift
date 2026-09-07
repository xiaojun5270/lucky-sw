import Foundation

extension JSONUnwrap {
    /// `extractTasks` in `services/ddns.ts`, `extractCertificates` and the inline search in
    /// `getSslSyncClientOptions` in `services/ssl.ts`.
    ///
    /// Those three endpoints answer with a differently-shaped payload on almost every Lucky
    /// version, and none of them agrees on a key name, so instead of looking for a key they
    /// score every array of records by how many *expected fields* its elements carry and keep
    /// the highest scorer. A score of zero means nothing in the payload looked like the
    /// wanted entity, and the caller shows an empty list rather than random records.
    ///
    /// - Parameter includeRecordValues: DDNS also accepts an object *whose values* are the
    ///   records (`{ "task-1": {…}, "task-2": {…} }`); the SSL searches do not.
    ///
    /// Presence is `value[key] !== undefined`, so a field explicitly set to `null` still
    /// scores — `JSONObject.has` matches that.
    static func bestScoredRecords(
        _ payload: JSONValue,
        keys: [String],
        includeRecordValues: Bool = false
    ) -> [JSONValue] {
        var queue: [JSONValue] = [payload]
        var head = 0
        var best: [JSONValue] = []
        var bestScore = 0

        func score(_ records: [JSONValue]) -> Int {
            records.reduce(0) { total, item in
                guard case .object(let object) = item else { return total }
                return total + keys.reduce(0) { $0 + (object.has($1) ? 1 : 0) }
            }
        }

        func consider(_ records: [JSONValue]) {
            let value = score(records)
            guard !records.isEmpty, value > bestScore else { return }
            best = records
            bestScore = value
        }

        while head < queue.count {
            let current = queue[head]
            head += 1
            switch current {
            case .array(let items):
                consider(items.filter(\.isRecord))
                queue.append(contentsOf: items)
            case .object(let object):
                if includeRecordValues { consider(object.values.filter(\.isRecord)) }
                queue.append(contentsOf: object.values)
            default:
                continue
            }
        }
        return bestScore > 0 ? best : []
    }
}
