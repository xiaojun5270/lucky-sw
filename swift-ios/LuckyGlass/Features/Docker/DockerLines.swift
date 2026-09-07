import Foundation

// MARK: - Log flattening

extension DockerRecord {
    private static let textKeys = [
        "LogContent", "logContent", "message", "Message", "content", "Content",
        "text", "Text", "log", "Log",
    ]
    private static let timeKeys = ["LogTime", "logTime", "timestamp", "Timestamp", "time", "Time"]
    private static let levelKeys = ["level", "Level", "logLevel", "LogLevel"]
    private static let wrapperKeys = [
        "logs", "Logs", "list", "List", "rows", "Rows", "items", "Items",
        "data", "Data", "result", "Result",
    ]
    private static let envelopeKeys = ["ret", "msg", "total", "page", "pageSize"]

    /// docker's own `lines(payload)` — flattens a log envelope into printable lines.
    ///
    /// Deliberately not `LuckyLog.lines`: this one reads `LogContent` before `message`, prefixes
    /// each line with `[time level]`, and falls back to a `key: value · key: value` digest of the
    /// record's scalars, none of which the shared reader does.
    ///
    /// The original's `visited` set guards against a reference cycle, which a parsed JSON payload
    /// cannot contain, so it has no counterpart here.
    static func lines(_ payload: JSONValue?) -> [String] {
        guard let payload else { return [] }
        var result: [String] = []
        append(payload, into: &result)
        return result
    }

    private static func append(_ value: JSONValue, into result: inout [String]) {
        switch value {
        case .string(let text):
            result.append(contentsOf: text.jsLines.map(\.jsTrimmedEnd)
                .filter { !$0.jsTrimmed.isEmpty })
        case .number, .bool:
            result.append(value.asDisplayString)
        case .array(let items):
            for item in items { append(item, into: &result) }
        case .object(let record):
            appendRecord(record, into: &result)
        case .null, .binary:
            return
        }
    }

    private static func appendRecord(_ entry: JSONObject, into result: inout [String]) {
        if let content = present(entry, textKeys) {
            let time = scalar(entry, timeKeys)
            let level = scalar(entry, levelKeys)
            let prefix = [time, level].compactMap { $0 }.filter { !$0.isEmpty }
                .joined(separator: " ")
            let before = result.count
            append(content, into: &result)
            if !prefix.isEmpty {
                for index in before..<result.count {
                    result[index] = "[\(prefix)] \(result[index])"
                }
            }
            return
        }
        if let wrapper = present(entry, wrapperKeys) {
            append(wrapper, into: &result)
            return
        }
        let fields = entry.pairs.filter { pair in
            guard !envelopeKeys.contains(pair.key) else { return false }
            switch pair.value {
            case .string, .number, .bool: return true
            default: return false
            }
        }
        .map { "\($0.key): \($0.value.asDisplayString)" }
        if !fields.isEmpty { result.append(fields.joined(separator: " · ")) }
    }

    /// `keys.map(k => entry[k]).find(v => v !== undefined && v !== null)`
    private static func present(_ entry: JSONObject, _ keys: [String]) -> JSONValue? {
        for key in keys {
            guard let value = entry[key], !value.isNull else { continue }
            return value
        }
        return nil
    }

    /// The same walk, but only a string or a number counts — a nested time object is skipped.
    private static func scalar(_ entry: JSONObject, _ keys: [String]) -> String? {
        for key in keys {
            switch entry[key] {
            case .string(let text): return text
            case .number(let number): return JSONSerializer.numberString(number)
            default: continue
            }
        }
        return nil
    }
}

// MARK: - Container artwork lookup

extension DockerRecord {
    private static let iconKeys = ["Icon", "icon", "Logo", "logo", "ImageIcon"]
    private static let iconLabels = [
        "net.unraid.docker.icon", "org.opencontainers.image.icon",
        "com.docker.desktop.extension.icon", "icon",
    ]
    /// Terms too generic to identify anything — every image in a registry would match `docker`.
    private static let noise = ["latest", "docker", "library", "ghcr", "com"]

    /// `containerIcon(item, icons)` — the icon library path that best fits a container.
    ///
    /// A container that names its own icon wins outright. Otherwise the name and the image are cut
    /// into terms and scored against every icon filename: an exact match is worth 10, a substring
    /// is worth the term's length, and a total below 3 is not enough to guess with.
    static func containerIcon(_ item: JSONValue, _ icons: [JSONValue]) -> String {
        let labels = item["Labels"]?.objectValue ?? JSONObject()
        let direct = iconKeys.compactMap { item[$0] } + iconLabels.compactMap { labels[$0] }
        for value in direct {
            guard case .string(let text) = value, !text.jsTrimmed.isEmpty else { continue }
            return text.jsTrimmed
        }
        let terms = [pick(item, ["Names", "Name", "name"]), pick(item, ["Image", "ImageName"])]
            .flatMap(iconTerms)
        guard !terms.isEmpty else { return "" }
        var best = ""
        var bestScore = 0
        for icon in icons {
            let path = pick(icon, ["RelativePath", "Path", "path"])
            let name = pick(icon, ["Name", "FileName", "name"], path).lowercased()
            let score = terms.reduce(0) { total, term in
                if name == term { return total + 10 }
                return total + (name.contains(term) ? term.count : 0)
            }
            if score > bestScore {
                best = path
                bestScore = score
            }
        }
        return bestScore >= 3 ? best : ""
    }

    /// `value.toLowerCase().split(/[\/:@._-]+/)` then the length and noise filters.
    private static func iconTerms(_ value: String) -> [String] {
        value.lowercased()
            .split { "/:@._-".contains($0) }
            .map(String.init)
            .filter { $0.count >= 3 && !noise.contains($0) }
    }

    /// `/^(https?:|data:|file:)/i.test(icon)` — an icon the library did not supply, which must be
    /// fetched without the admin token attached.
    static func isExternalIcon(_ icon: String) -> Bool {
        let lowered = icon.lowercased()
        return ["http:", "https:", "data:", "file:"].contains { lowered.hasPrefix($0) }
    }
}
