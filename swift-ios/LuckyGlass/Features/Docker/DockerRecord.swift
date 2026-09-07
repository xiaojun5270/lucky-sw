import Foundation

/// §4 — the readers `app/docker.tsx` defines for its own use.
///
/// None of these have a counterpart elsewhere in the port. `Format.text` reads one label, while
/// docker's `pick` joins an array with `", "`; `LuckyLog.lines` flattens a log envelope through a
/// different key set than docker's `lines`. Both are reimplemented rather than bent to fit.
enum DockerRecord {
    /// `pick(item, keys, fallback)` — the first key holding a string or a number, or a non-empty
    /// array joined with `", "`. A record or a bool is skipped rather than stringified.
    static func pick(_ item: JSONValue, _ keys: [String], _ fallback: String = "") -> String {
        for key in keys {
            guard let value = item[key] else { continue }
            switch value {
            case .string(let text): return text
            case .number: return value.asDisplayString
            case .array(let items) where !items.isEmpty:
                return items.map(\.asDisplayString).joined(separator: ", ")
            default: continue
            }
        }
        return fallback
    }

    /// `keyOf(item, index)`
    static func keyOf(_ item: JSONValue, _ index: Int) -> String {
        pick(item, ["Id", "ID", "id", "Name", "name", "Key", "key"], String(index))
    }

    /// `searchText(item)` — the whole record stringified and lowercased, which is why the search
    /// box matches a label value or a mount path just as readily as a name.
    static func searchText(_ item: JSONValue) -> String {
        JSONSerializer.stringify(item).lowercased()
    }

    /// `imageReferences(item)` — every tag the entry carries, `<none>` dropped, order preserved.
    static func imageReferences(_ item: JSONValue) -> [String] {
        var references: [String] = []
        var seen = Set<String>()
        for key in ["RepoTags", "Tags", "repoTags", "tags", "Name", "name"] {
            let candidates: [String]
            switch item[key] {
            case .array(let items): candidates = items.map(\.asDisplayString)
            case .string(let text): candidates = text.components(separatedBy: ",")
            default: continue
            }
            for candidate in candidates {
                let trimmed = candidate.jsTrimmed
                guard !trimmed.isEmpty, !trimmed.lowercased().contains("<none>") else { continue }
                guard seen.insert(trimmed).inserted else { continue }
                references.append(trimmed)
            }
        }
        return references
    }

    /// `imagePushValue(name)` — splits a reference into image and tag. The colon only counts when
    /// it comes after the last slash, so `registry:5000/app` keeps its port.
    ///
    /// The two offsets stand in for `lastIndexOf`, whose `-1` for "absent" is what makes the
    /// original's bare `>` comparison work on an untagged reference.
    static func imagePushValue(_ name: String) -> JSONObject {
        let reference = (name.components(separatedBy: ",").first ?? "").jsTrimmed
        let slash = offset(of: "/", in: reference)
        let colon = offset(of: ":", in: reference)
        guard colon > slash, let cut = reference.lastIndex(of: ":") else {
            return JSONObject([
                ("image", .string(reference == "<none>" ? "" : reference)),
                ("tag", .string("latest")),
            ])
        }
        let tag = String(reference[reference.index(after: cut)...])
        return JSONObject([
            ("image", .string(String(reference[reference.startIndex..<cut]))),
            ("tag", .string(tag.isEmpty ? "latest" : tag)),
        ])
    }

    /// `value.lastIndexOf(character)`
    private static func offset(of character: Character, in value: String) -> Int {
        guard let index = value.lastIndex(of: character) else { return -1 }
        return value.distance(from: value.startIndex, to: index)
    }
}

// MARK: - Sizes

extension DockerRecord {
    private static let units = ["B", "KB", "MB", "GB", "TB"]

    /// `bytes(value)` — `Number(value) || 0`, so a blank or unparseable size is `--` rather than
    /// `0 B`. The index is floored, then clamped to `TB`; only `B` prints without decimals.
    static func bytes(_ value: JSONValue?) -> String {
        let size = value?.asNumber ?? 0
        guard size != 0, size.isFinite else { return "--" }
        let raw = Int((log(abs(size)) / log(1024)).rounded(.down))
        let index = max(0, min(raw, units.count - 1))
        let scaled = size / pow(1024, Double(index))
        return "\(JSCompat.toFixed(scaled, index == 0 ? 0 : 2)) \(units[index])"
    }

    /// `compactDockerBytes(value, available)` — a metric the container never reported is `N/A`,
    /// a metric it reported as zero is `0 B`, and `bytes` would print `--` for both.
    static func compactBytes(_ value: Double, _ available: Bool) -> String {
        guard available else { return "N/A" }
        guard value > 0 else { return "0 B" }
        return bytes(.number(value))
    }
}

// MARK: - Container status

extension DockerRecord {
    private static let durationWords: [(String, String)] = [
        ("second", "秒"), ("minute", "分钟"), ("hour", "小时"),
        ("day", "天"), ("week", "周"), ("month", "个月"),
    ]

    /// `containerStatus(item, running, paused)` — the badge text on a container row.
    ///
    /// A stopped container shows the daemon's own words unless they read as an exit, and a running
    /// one shows its uptime with the English unit localised.
    static func containerStatus(_ item: JSONValue, running: Bool, paused: Bool) -> String {
        if paused { return "已暂停" }
        let raw = pick(item, ["Status", "status", "State", "state"], running ? "运行中" : "已停止")
        guard running else {
            let lowered = raw.lowercased()
            let stopped = ["exit", "stop", "dead"].contains { lowered.contains($0) }
            return stopped ? "已停止" : raw
        }
        guard let duration = upDuration(raw) else { return "运行中" }
        var localized = duration
        for (english, chinese) in durationWords {
            localized = replaceFirstUnit(english, with: chinese, in: localized)
        }
        return "运行: \(localized)"
    }

    /// `text.replace(/{unit}s?/i, chinese)` — first match only, and the optional plural `s` is
    /// greedy, so `minutes` is consumed whole rather than leaving a stray `s` behind.
    private static func replaceFirstUnit(
        _ unit: String, with chinese: String, in text: String
    ) -> String {
        guard let range = text.range(of: unit, options: .caseInsensitive) else { return text }
        var upper = range.upperBound
        if upper < text.endIndex, text[upper] == "s" || text[upper] == "S" {
            upper = text.index(after: upper)
        }
        return text.replacingCharacters(in: range.lowerBound..<upper, with: chinese)
    }

    /// `raw.match(/Up\s+(.+?)(?:\s+\(|$)/i)?.[1]` — the span between `Up` and either a bracketed
    /// health note or the end of the line.
    private static func upDuration(_ raw: String) -> String? {
        guard let up = raw.range(of: "Up", options: .caseInsensitive) else { return nil }
        var start = up.upperBound
        var sawSpace = false
        while start < raw.endIndex, raw[start].isWhitespace {
            sawSpace = true
            start = raw.index(after: start)
        }
        guard sawSpace, start < raw.endIndex else { return nil }
        let rest = raw[start...]
        // ` (` closes the group; a lone `(` does not, which is why the space is part of the test.
        var index = rest.startIndex
        while index < rest.endIndex {
            let next = rest.index(after: index)
            if rest[index].isWhitespace, next < rest.endIndex, rest[next] == "(" {
                let text = String(rest[rest.startIndex..<index])
                return text.isEmpty ? nil : text
            }
            index = next
        }
        return rest.isEmpty ? nil : String(rest)
    }
}

// MARK: - Compose

extension DockerRecord {
    /// `pickComposeField(item, keys)` — first non-blank trimmed string, or a number.
    static func pickComposeField(_ item: JSONValue, _ keys: [String]) -> String {
        for key in keys {
            switch item[key] {
            case .string(let text) where !text.jsTrimmed.isEmpty: return text.jsTrimmed
            case .number(let number): return JSONSerializer.numberString(number)
            default: continue
            }
        }
        return ""
    }

    /// `composePayload(item)` — the two fields every compose call is keyed by.
    static func composePayload(_ item: JSONValue) -> (name: String, path: String) {
        (
            pickComposeField(item, [
                "name", "Name", "project_name", "projectName", "ProjectName",
            ]),
            pickComposeField(item, [
                "path", "Path", "project_path", "projectPath", "ProjectPath",
                "working_dir", "WorkingDir",
            ])
        )
    }

    private static let missingDirectory = [
        "目录不存在", "directory does not exist", "directory not found",
        "no such file", "no such directory",
    ]

    /// `composeProjectError(error, projectPath)` — rewrites the daemon's "no such directory" into
    /// the mount instruction, which is what the failure almost always means: Lucky runs in a
    /// container and the project directory was never bind-mounted into it.
    static func composeProjectError(_ message: String, projectPath: String) -> String {
        let text = message.isEmpty ? "Compose 操作失败" : message
        let lowered = text.lowercased()
        // `directory\s+(?:does not exist|not found)` collapses to a substring test because the
        // daemon only ever emits a single space there.
        guard missingDirectory.contains(where: { lowered.contains($0.lowercased()) }) else {
            return text
        }
        return "Lucky 服务无法访问项目目录：\(projectPath)。"
            + "请将宿主机 Compose 目录按相同绝对路径读写挂载到 Lucky 容器。"
    }
}

// MARK: - Envelope walking

extension DockerRecord {
    /// `deepScalar(payload, keys)` — one breadth-first sweep per key, looking for a *scalar* held
    /// under a case-insensitive key match.
    ///
    /// Deliberately not `JSONUnwrap.deepValue`, which returns the first key match whatever its
    /// type: here a record or an array under `status` is passed over and the walk keeps going,
    /// which is what lets `{ result: { status: {...} }, status: "running" }` still find the string.
    ///
    /// Every entry of a record is scanned before any child is enqueued, so a shallow match always
    /// beats a deep one. Arrays are walked too — `Object.entries` numbers them, and a numeric key
    /// never matches a word.
    static func deepScalar(_ payload: JSONValue, _ keys: [String]) -> JSONValue? {
        for key in keys {
            let needle = key.lowercased()
            var queue: [JSONValue] = [payload]
            while !queue.isEmpty {
                let current = queue.removeFirst()
                var children: [JSONValue] = []
                switch current {
                case .object(let record):
                    for pair in record.pairs where pair.key.lowercased() == needle {
                        switch pair.value {
                        case .string, .number, .bool: return pair.value
                        default: continue
                        }
                    }
                    children = record.values
                case .array(let items):
                    children = items
                default:
                    continue
                }
                for child in children where child.isRecord || child.isArray {
                    queue.append(child)
                }
            }
        }
        return nil
    }

    /// `nested(payload, keys)` — a breadth-first search for the first record held under a
    /// case-insensitive key match, one key at a time. Falls back to the payload itself, so an
    /// editor always has something to edit.
    static func nested(_ payload: JSONValue, _ keys: [String]) -> JSONObject {
        let root = payload.record
        for key in keys {
            var queue: [JSONObject] = [root]
            let needle = key.lowercased()
            while !queue.isEmpty {
                let current = queue.removeFirst()
                if let match = current.keys.first(where: { $0.lowercased() == needle }),
                   let value = current[match], let record = value.objectValue {
                    return record
                }
                for pair in current.pairs {
                    if let child = pair.value.objectValue { queue.append(child) }
                }
            }
        }
        return root
    }

    private static let configTextKeys = [
        "content", "Content", "config", "Config", "yaml", "YAML", "dockerfile", "Dockerfile",
    ]

    /// `composeConfigText(payload)` — the YAML or Dockerfile body, wherever the module hid it.
    /// `data` and `result` are tried after the named keys at every level, not only at the root.
    static func composeConfigText(_ payload: JSONValue) -> String {
        var queue: [JSONObject] = [payload.record]
        while !queue.isEmpty {
            let source = queue.removeFirst()
            for key in configTextKeys {
                if case .string(let text)? = source[key] { return text }
            }
            for key in ["data", "result"] {
                if case .string(let text)? = source[key] { return text }
            }
            for pair in source.pairs {
                if let child = pair.value.objectValue { queue.append(child) }
            }
        }
        return ""
    }
}
