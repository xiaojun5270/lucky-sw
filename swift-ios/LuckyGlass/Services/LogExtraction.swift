import Foundation

/// Port of the log-extraction half of `src/services/lucky.ts`.
///
/// Lucky's log endpoints are the least consistent part of the API: a response can be a
/// string, an array of strings, an array of records using any of a dozen field names for
/// the message, a paged envelope wrapping any of those, or a JSON *string* containing one
/// of those. The walk order below decides what the log screens actually render, so it is
/// reproduced field for field rather than simplified.
///
/// The original threads a `seen` set through the recursion to survive cyclic objects.
/// Parsed JSON is a tree and `JSONValue` is a value type, so there is nothing to guard
/// against and the parameter is dropped.
enum LuckyLog {
    /// `logTextKeys` — checked first, so a record with both `msg` and `content` renders once.
    static let textKeys = [
        "log", "Log", "message", "Message", "content", "Content", "LogContent",
        "text", "Text", "line", "Line", "output", "Output",
    ]
    /// `logCollectionKeys`
    static let collectionKeys = [
        "logs", "Logs", "lastLogs", "LastLogs", "lastlogs", "rows", "Rows",
        "entries", "Entries", "records", "Records", "items", "Items", "list", "List",
    ]
    /// `logWrapperKeys`
    static let wrapperKeys = [
        "data", "Data", "result", "Result", "response", "Response", "payload", "Payload",
    ]
    /// `logEnvelopeKeys` — paging metadata, hidden from the "render the record as JSON" fallback.
    static let envelopeKeys: Set<String> = [
        "ret", "msg", "code", "success", "total", "Total", "totalCount", "TotalCount",
        "logsCount", "LogsCount", "count", "Count", "page", "Page", "pageSize", "PageSize",
        "currentPage", "CurrentPage",
    ]
    /// The fields that mark a `msg` as a log line rather than an envelope message.
    static let timeKeys = ["timestamp", "Timestamp", "time", "Time", "level", "Level", "LogTime"]
    /// `logEntryCursor`
    static let cursorKeys = [
        "timestamp", "Timestamp", "timeStamp", "TimeStamp", "LogTimestamp", "logTimestamp",
    ]

    // MARK: - Line extraction

    /// `extractLogLines(payload)` / `extractLogValue(value)`
    static func lines(_ value: JSONValue) -> [String] {
        var lines: [String] = []
        _ = appendLines(value, into: &lines)
        return lines
    }

    /// `parseStructuredLogString` — a string that looks like JSON is treated as data, not text.
    static func parseStructured(_ value: String) -> JSONValue? {
        let trimmed = value.jsTrimmed
        let looksStructured = (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
        guard looksStructured, let parsed = JSONParser.tryParse(trimmed) else { return nil }
        // `parsed && typeof parsed === 'object'` — arrays count, `null` does not.
        return parsed.isRecord || parsed.isArray ? parsed : nil
    }

    /// `appendLogLines(value, lines, seen, allowFallback)`. The return value reports whether
    /// anything was produced, which is how each branch decides to stop looking.
    @discardableResult
    static func appendLines(
        _ value: JSONValue,
        into lines: inout [String],
        allowFallback: Bool = true
    ) -> Bool {
        switch value {
        case .string(let text):
            if let parsed = parseStructured(text) {
                appendLines(parsed, into: &lines, allowFallback: allowFallback)
                return !lines.isEmpty
            }
            lines.append(contentsOf: text.jsLines.map(\.jsTrimmedEnd).filter { !$0.jsTrimmed.isEmpty })
            return !lines.isEmpty
        case .number, .bool:
            lines.append(value.asDisplayString)
            return true
        case .array(let items):
            let before = lines.count
            for item in items { appendLines(item, into: &lines) }
            return lines.count > before
        case .object(let object):
            return appendRecordLines(object, into: &lines, allowFallback: allowFallback)
        case .null, .binary:
            // `null` matches none of the original's `typeof` branches, and a downloaded
            // body reaches the fallback with no visible fields, which also yields nothing.
            return false
        }
    }

    /// The record branch of `appendLogLines`, in the original's order: message aliases, a
    /// timestamped `msg`, collections, wrappers, then any other nested object.
    private static func appendRecordLines(
        _ object: JSONObject,
        into lines: inout [String],
        allowFallback: Bool
    ) -> Bool {
        var recognizedEnvelope = false

        /// Each group behaves the same way: the presence of the key means "this is a log
        /// envelope" even when the value is empty, and the first key that produces a line wins.
        func scan(_ keys: [String]) -> Bool {
            for key in keys {
                guard object.has(key) else { continue }
                recognizedEnvelope = true
                guard let candidate = object[key], !candidate.isNull else { continue }
                let before = lines.count
                appendLines(candidate, into: &lines)
                if lines.count > before { return true }
            }
            return false
        }

        if scan(textKeys) { return true }

        // A bare `msg` is the envelope's error message; a `msg` next to a timestamp or a
        // level is a log line.
        if object.has("msg"), timeKeys.contains(where: object.has) {
            recognizedEnvelope = true
            let before = lines.count
            appendLines(object["msg"] ?? .null, into: &lines)
            if lines.count > before { return true }
        }

        if scan(collectionKeys) { return true }
        if scan(wrapperKeys) { return true }

        // Some builds add one more named wrapper around the normal envelope. Walking the
        // remaining object values catches that, with the JSON fallback switched off so an
        // unrelated config object is not printed as a log line.
        var sawNestedValue = false
        for (key, nested) in object.pairs {
            if envelopeKeys.contains(key) || textKeys.contains(key)
                || collectionKeys.contains(key) || wrapperKeys.contains(key) { continue }
            guard nested.isRecord || nested.isArray else { continue }
            sawNestedValue = true
            let before = lines.count
            appendLines(nested, into: &lines, allowFallback: false)
            if lines.count > before { return true }
        }

        if recognizedEnvelope || sawNestedValue { return false }
        guard allowFallback else { return false }

        // A record that resembles nothing known is rendered as JSON, minus the envelope
        // fields, so an unrecognised log shape is still visible in the UI.
        let visible = object.filter { key, _ in !envelopeKeys.contains(key) }
        guard !visible.isEmpty else { return false }
        lines.append(JSONSerializer.stringify(.object(visible)))
        return true
    }

    // MARK: - Paging metadata

    /// `nestedLogNumber(payload, keys)` — the first non-negative count found within three
    /// wrapper levels. `Number('')` is 0 in JavaScript, so an empty string is a valid zero;
    /// `Number('abc')` is `NaN` and is skipped, which is why this uses `JSCompat.number`
    /// rather than `asNumber`.
    static func nestedNumber(_ payload: JSONValue, keys: [String]) -> Int? {
        var queue: [(value: JSONValue, depth: Int)] = [(payload, 0)]
        var head = 0
        while head < queue.count {
            let (value, depth) = queue[head]
            head += 1
            guard case .object(let object) = value else { continue }

            for key in keys {
                guard let raw = object[key] else { continue }
                let number: Double
                switch raw {
                case .number(let value): number = value
                case .string(let text): number = JSCompat.number(text)
                default: number = .nan
                }
                if number.isFinite, number >= 0 { return Int(number.rounded(.towardZero)) }
            }

            if depth >= 3 { continue }
            for key in wrapperKeys + ["pagination", "Pagination", "meta", "Meta"] {
                if let nested = object[key], nested.isRecord { queue.append((nested, depth + 1)) }
            }
        }
        return nil
    }

    /// `LogCollectionMatch`. `found` with a `nil` value is the original's
    /// `{ found: true, value: null }`: the response *has* a log collection and it is empty,
    /// which the batch reader treats differently from "no collection at all".
    ///
    /// Named `LogCollection` rather than `Collection` so it cannot shadow the standard
    /// library protocol inside this namespace.
    struct LogCollection {
        var found: Bool
        var value: JSONValue?

        var entries: [JSONValue]? {
            if case .array(let items)? = value { return items }
            // `null` and `undefined` under a found collection mean "empty".
            if found, value == nil || value?.isNull == true { return [] }
            return nil
        }
    }

    /// `nestedLogCollection(payload)` — breadth-first for the first **non-empty** collection,
    /// remembering the first empty one as a fallback so "no logs yet" can be told apart from
    /// "no log field at all". A collection stored as a JSON string is parsed and re-tested.
    static func nestedCollection(_ payload: JSONValue) -> LogCollection {
        var queue: [JSONValue] = [payload]
        var head = 0
        var emptyValue: JSONValue?
        var foundEmpty = false

        /// Records the first empty candidate without overwriting it.
        func noteEmpty(_ value: JSONValue?) {
            guard !foundEmpty else { return }
            emptyValue = value
            foundEmpty = true
        }

        while head < queue.count {
            let value = queue[head]
            head += 1
            guard case .object(let object) = value else { continue }

            for key in collectionKeys {
                guard object.has(key), let candidate = object[key] else { continue }
                switch candidate {
                case .array(let items):
                    if !items.isEmpty { return LogCollection(found: true, value: candidate) }
                    noteEmpty(candidate)
                case .string(let text):
                    let parsed = parseStructured(text)
                    if case .array(let items)? = parsed {
                        if !items.isEmpty { return LogCollection(found: true, value: parsed) }
                        noteEmpty(parsed)
                    } else if let parsed, parsed.isRecord {
                        queue.append(parsed)
                    } else if !text.jsTrimmed.isEmpty {
                        return LogCollection(found: true, value: candidate)
                    } else {
                        noteEmpty(candidate)
                    }
                case .null:
                    noteEmpty(.null)
                default:
                    continue
                }
            }

            for key in wrapperKeys {
                guard let nested = object[key] else { continue }
                switch nested {
                case .object: queue.append(nested)
                case .array(let items):
                    if !items.isEmpty { return LogCollection(found: true, value: nested) }
                    noteEmpty(nested)
                case .string(let text):
                    let parsed = parseStructured(text)
                    if case .array(let items)? = parsed {
                        if !items.isEmpty { return LogCollection(found: true, value: parsed) }
                        noteEmpty(parsed)
                    } else if let parsed, parsed.isRecord {
                        queue.append(parsed)
                    } else if !text.jsTrimmed.isEmpty {
                        return LogCollection(found: true, value: nested)
                    } else {
                        noteEmpty(nested)
                    }
                default:
                    continue
                }
            }
        }
        return foundEmpty ? LogCollection(found: true, value: emptyValue) : LogCollection(found: false, value: nil)
    }

    // MARK: - Cursors

    /// `logEntryCursor(value)` — the entry's timestamp, or `''` when it has none.
    static func entryCursor(_ value: JSONValue) -> String {
        guard case .object(let object) = value else { return "" }
        for key in cursorKeys {
            guard let cursor = object[key] else { continue }
            if case .string(let text) = cursor, !text.jsTrimmed.isEmpty { return text.jsTrimmed }
            if case .number(let number) = cursor, number.isFinite { return JSONSerializer.numberString(number) }
        }
        return ""
    }

    /// `compareLogCursor` — numeric timestamps compare by magnitude (shorter is older once
    /// leading zeros are gone), everything else by locale order.
    static func compareCursor(_ left: String, _ right: String) -> Int {
        guard JSRegex.isDigitsOnly(left), JSRegex.isDigitsOnly(right) else {
            return left.jsLocaleCompare(right)
        }
        let normalizedLeft = left.withoutLeadingZeros
        let normalizedRight = right.withoutLeadingZeros
        if normalizedLeft.count != normalizedRight.count { return normalizedLeft.count - normalizedRight.count }
        return normalizedLeft.jsLocaleCompare(normalizedRight)
    }

    /// `logStartTime(payload)` — when the service last restarted, shown above the log view.
    static func startTime(_ payload: JSONValue) -> String {
        for source in [payload, payload["data"] ?? .null, payload["result"] ?? .null] {
            guard case .object(let object) = source else { continue }
            for key in ["starttime", "startTime", "StartTime"] {
                guard let value = object[key] else { continue }
                if value.isString || value.isFiniteNumber { return value.asDisplayString }
            }
        }
        return ""
    }
}

/// `logResult(payload, page, pageSize, paged)` — one page of a paged log view.
struct LuckyLogPage: Sendable {
    var lines: [String] = []
    var raw: JSONValue = .object([])
    var total: Int?
    var pageSize: Int = 100
    var page: Int = 1
    var hasMore: Bool = false

    init(_ payload: JSONValue, page: Int = 1, requestedPageSize: Int = 100, paged: Bool = true) {
        lines = LuckyLog.lines(payload)
        raw = payload
        self.page = page

        let responsePageSize = LuckyLog.nestedNumber(payload, keys: ["pageSize", "PageSize", "limit", "Limit"])
        // `responsePageSize && responsePageSize > 0` — a reported size of 0 is ignored.
        pageSize = (responsePageSize ?? 0) > 0 ? responsePageSize! : requestedPageSize
        total = LuckyLog.nestedNumber(payload, keys: [
            "total", "Total", "totalCount", "TotalCount", "logsCount", "LogsCount", "count", "Count",
        ])

        // Without a total, "a full page came back" is the only signal that more exist.
        let collection = LuckyLog.nestedCollection(payload)
        let entryCount: Int
        if case .array(let items)? = collection.value {
            entryCount = items.count
        } else if case .string(let text)? = collection.value {
            entryCount = text.jsLines.filter { !$0.jsTrimmed.isEmpty }.count
        } else {
            entryCount = lines.count
        }
        hasMore = paged && (total.map { page * pageSize < $0 } ?? (entryCount >= pageSize))
    }
}

/// `globalLogBatch(payload, previousCursor)` — the global log view polls `/api/logs` and
/// appends only what is new, which requires every entry to carry a timestamp. When they do
/// not, the whole payload is re-rendered each poll (`incremental == false`) and the screen
/// replaces its buffer instead of appending.
struct LuckyLogBatch: Sendable {
    var lines: [String] = []
    var raw: JSONValue = .object([])
    /// The cursor to send as `pre` next time; `''` after the server truncated its buffer.
    var cursor: String = ""
    var startTime: String = ""
    var incremental: Bool = false
    /// The server's log buffer went backwards (restart or rotation), so drop what is shown.
    var reset: Bool = false

    init(_ payload: JSONValue, previousCursor: String) {
        raw = payload
        startTime = LuckyLog.startTime(payload)

        let collection = LuckyLog.nestedCollection(payload)
        let entries = collection.entries
        let cursors = entries?.map(LuckyLog.entryCursor) ?? []
        // An empty page still supports cursors if we had one going in — that is how the
        // "nothing new" response is recognised.
        if let entries {
            incremental = entries.isEmpty ? !previousCursor.isEmpty : cursors.allSatisfy { !$0.isEmpty }
        }

        let responseCursor = incremental && !cursors.isEmpty ? cursors[cursors.count - 1] : previousCursor
        let logsCount = LuckyLog.nestedNumber(payload, keys: ["logsCount", "LogsCount"])
        let emptied = !previousCursor.isEmpty && collection.found
            && entries?.isEmpty == true && logsCount == 0
        reset = emptied || (!previousCursor.isEmpty && !responseCursor.isEmpty
            && LuckyLog.compareCursor(responseCursor, previousCursor) < 0)
        cursor = emptied ? "" : responseCursor

        let selected: [JSONValue]?
        if incremental, !previousCursor.isEmpty, !reset, let entries {
            selected = entries.enumerated()
                .filter { LuckyLog.compareCursor(cursors[$0.offset], previousCursor) > 0 }
                .map(\.element)
        } else {
            selected = entries
        }
        // An empty selection is still a selection: it means "nothing new", not "re-read the
        // whole payload", which is why this tests for presence rather than emptiness.
        lines = selected.map { LuckyLog.lines(.array($0)) } ?? LuckyLog.lines(payload)
    }
}
