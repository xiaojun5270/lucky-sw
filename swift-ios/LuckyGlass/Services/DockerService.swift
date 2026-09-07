import Foundation

/// `DockerContainerFileOperation` — the fifteen operations the container file browser runs.
/// The raw values are the URL segments, so the hyphenated ones keep their spelling.
enum DockerFileOperation: String, Sendable, CaseIterable, Identifiable {
    case list, read, write, delete, mkdir, touch, rename, copy, chmod, search
    case compress
    case compressAsync = "compress-async"
    case decompress
    case decompressAsync = "decompress-async"
    case previewArchive = "preview-archive"

    var id: String { rawValue }

    /// `dockerContainerFileMethods[operation]`
    var method: String {
        switch self {
        case .list, .read, .previewArchive: return "GET"
        case .delete: return "DELETE"
        default: return "POST"
        }
    }

    /// `readOnly = method === 'GET'` — a read-only operation sends its arguments as the query
    /// string instead of a body.
    var readOnly: Bool { method == "GET" }

    /// `operation.includes('compress') || operation.includes('decompress')`. The second test is
    /// redundant in the original — `'decompress'.includes('compress')` is already true — so all
    /// four (de)compress operations get the ten-minute budget.
    var longRunning: Bool { rawValue.contains("compress") }
}

/// `DockerComposeCreateInput` — the body of `compose/up-async`.
struct DockerComposeCreateInput: Sendable {
    var projectName: String?
    var workingDirectory: String
    var composeContent: String
    var configFileName: String
    var build: Bool?

    /// `JSON.stringify` omits an `undefined` value entirely, so the two optional fields are
    /// inserted only when present rather than sent as `null`.
    var payload: JSONValue {
        var object = JSONObject()
        if let projectName { object["project_name"] = .string(projectName) }
        object["working_dir"] = .string(workingDirectory)
        object["compose_content"] = .string(composeContent)
        object["config_file_name"] = .string(configFileName)
        if let build { object["build"] = .bool(build) }
        return .object(object)
    }
}

/// One failed entry of a batch: `{ item, error }`.
struct DockerBatchFailure<Item: Sendable>: Sendable {
    var item: Item
    var error: String
}

/// `DockerBatchProgress<T>` — the snapshot `runDockerBatch` hands to `onProgress` after every
/// completed item. Both arrays are copies, so a callback can keep them.
struct DockerBatchProgress<Item: Sendable>: Sendable {
    var succeeded: [Item] = []
    var failed: [DockerBatchFailure<Item>] = []
    var completedCount: Int = 0
    var totalCount: Int = 0
}

/// What `runDockerBatch` resolves to. It never throws: a failing item lands in `failed`.
struct DockerBatchResult<Item: Sendable>: Sendable {
    var succeeded: [Item] = []
    var failed: [DockerBatchFailure<Item>] = []
    /// `cancelled: cursor < items.length` — true when the cancellation hook stopped the
    /// workers before they had consumed every item.
    var cancelled: Bool = false
}

/// What `getDockerOverview` resolves to — a plain object in the original, deliberately not a
/// Lucky envelope, so there is no `ret`.
///
/// Every count is optional because "the endpoint was unavailable" and "the endpoint reported
/// zero" have to stay distinguishable: the dashboard shows a dash for the first and `0` for the
/// second. `containerCount` and `imageCount` are `Double` because they may come from a
/// server-reported fallback field rather than from counting the array.
struct DockerOverview: Sendable {
    var info: JSONValue = .object([])
    var containers: [LuckyListItem] = []
    var containersAvailable = false
    var containerCount: Double?
    var imageCount: Double?
    var imageSize: Double?
    var composeCount: Int?
    var networkCount: Int?
    var volumeCount: Int?
}

/// The shared cursor and accumulators behind `runDockerBatch`. An actor rather than captured
/// `var`s because the four workers really do race for the next index — in JavaScript
/// `items[cursor++]` is atomic by virtue of the single thread, and here it is not.
private actor DockerBatchState<Item: Sendable> {
    private let items: [Item]
    private var cursor = 0
    private var succeeded: [Item] = []
    private var failed: [DockerBatchFailure<Item>] = []

    init(_ items: [Item]) { self.items = items }

    /// `item = items[cursor++]`
    func next() -> Item? {
        guard cursor < items.count else { return nil }
        let item = items[cursor]
        cursor += 1
        return item
    }

    /// The `finally` block: progress fires for a failure exactly as it does for a success.
    func record(_ item: Item, failure: String?) -> DockerBatchProgress<Item> {
        if let failure {
            failed.append(DockerBatchFailure(item: item, error: failure))
        } else {
            succeeded.append(item)
        }
        return DockerBatchProgress(
            succeeded: succeeded,
            failed: failed,
            completedCount: succeeded.count + failed.count,
            totalCount: items.count
        )
    }

    func result() -> DockerBatchResult<Item> {
        DockerBatchResult(succeeded: succeeded, failed: failed, cancelled: cursor < items.count)
    }
}

/// A lock-guarded array of JSON values.
///
/// `checkDockerImagesUpgrade` reads its accumulated `results` from inside a **synchronous**
/// progress callback, which an actor cannot serve. The original gets away with a plain array
/// because JavaScript has no data race to lose; a lock is the smallest thing that keeps the
/// callback synchronous here.
private final class DockerResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [JSONValue] = []

    func append(_ value: JSONValue) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(value)
    }

    /// `[...results]`
    var snapshot: [JSONValue] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

/// Port of `src/services/docker.ts` — 123 callables over `/api/docker/…`.
///
/// Three things here are unlike the rest of the client and are reproduced as they are rather
/// than harmonised. It has its own query builder (`LuckyQuery.docker`, which keeps `false` and
/// `0` but drops `''`), so `removeContainer(id)` really does send `?force=false`. It has its own
/// tolerant payload search, which differs from `JSONUnwrap`'s in ways a Docker payload can
/// actually expose. And it has a per-endpoint timeout matrix from 10 s to 10 min, because a
/// `docker build` and a cached stats read cannot share a deadline.
///
/// Every `AbortSignal` parameter is dropped in favour of task cancellation, as described in
/// `LuckyService`; the cancellation checks sit at the same points the original checks the signal.
enum DockerService {
    private static var client: LuckyClient { .shared }

    // MARK: - The request primitive

    /// `callDockerApi(path, method, data, params, timeoutMs, signal, responseType)`.
    ///
    /// `path.replace(/^\//, '')` strips exactly one leading slash, so a caller that passes
    /// `//containers` really does reach `/api/docker//containers`.
    @discardableResult
    static func call(
        _ path: String,
        _ method: String = "GET",
        body: LuckyBody? = nil,
        params: [LuckyQuery.Parameter] = [],
        timeout: TimeInterval = LuckyClientConstants.defaultTimeout,
        responseKind: LuckyRequest.ResponseKind = .auto
    ) async throws -> JSONValue {
        var suffix = path
        if suffix.hasPrefix("/") { suffix.removeFirst() }
        var request = LuckyRequest(
            "/api/docker/\(suffix)\(LuckyQuery.docker(params))",
            method: method,
            body: body
        )
        request.timeout = timeout
        request.responseKind = responseKind
        return try await client.fetch(request)
    }

    /// The `params` argument is a `LuckyRecord`, so a query built from a caller's object keeps
    /// that object's key order.
    private static func parameters(_ value: JSONValue) -> [LuckyQuery.Parameter] {
        value.record.pairs.map { pair -> LuckyQuery.Parameter in (pair.key, pair.value) }
    }

    // MARK: - Payload search

    /// `findArray(payload, keys)` — this module's own tolerant array lookup, deliberately not
    /// `JSONUnwrap`'s.
    ///
    /// The BFS restarts from the root for **every** key, so key priority beats depth. Any array
    /// popped off the queue is returned whatever key it arrived under, which is how a payload
    /// shaped `{ data: [...] }` answers a search for `containers`. Records are always enqueued;
    /// arrays are enqueued only under a wrapper key. There is no depth limit and no visited set —
    /// a parsed `JSONValue` tree cannot contain a cycle, and a value-typed `Set` would wrongly
    /// collapse two structurally equal siblings.
    private static func findArray(_ payload: JSONValue, _ keys: [String]) -> [JSONValue]? {
        for wanted in keys.map({ $0.lowercased() }) {
            var queue: [JSONValue] = [payload]
            while !queue.isEmpty {
                let source = queue.removeFirst()
                if case .array(let entries) = source { return entries }
                guard case .object(let object) = source else { continue }
                // First pass: the key we are actually looking for.
                for pair in object.pairs where pair.key.lowercased() == wanted {
                    if case .array(let entries) = pair.value { return entries }
                }
                // Second pass: descend.
                for pair in object.pairs {
                    if pair.value.isRecord {
                        queue.append(pair.value)
                    } else if pair.value.isArray, JSONUnwrap.isWrapperKey(pair.key) {
                        queue.append(pair.value)
                    }
                }
            }
        }
        return nil
    }

    /// `list(payload, keys)` — `.filter(isRecord)`, so a stray string in the array is dropped
    /// rather than surfacing as a row the screens cannot render.
    private static func list(_ payload: JSONValue, _ keys: [String]) -> [LuckyListItem] {
        (findArray(payload, keys) ?? []).filter(\.isRecord)
    }

    /// `findScalar(payload, keys)` — one BFS for **all** the keys at once, so unlike `findArray`
    /// depth beats key priority here. Arrays are flattened into the queue whatever their key, and
    /// only a string, number or boolean is accepted: a matching key whose value is a record is
    /// ignored and the search continues.
    private static func findScalar(_ payload: JSONValue, _ keys: [String]) -> JSONValue? {
        let wanted = Set(keys.map { $0.lowercased() })
        var queue: [JSONValue] = [payload]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if case .array(let entries) = current {
                queue.append(contentsOf: entries)
                continue
            }
            guard case .object(let object) = current else { continue }
            for pair in object.pairs where wanted.contains(pair.key.lowercased()) {
                switch pair.value {
                case .string, .number, .bool: return pair.value
                default: break
                }
            }
            queue.append(contentsOf: object.values)
        }
        return nil
    }

    /// `findRecord(payload, keys)` — records only, and it **falls back to `payload` itself**
    /// rather than returning nothing. That fallback is load-bearing: `overview()` reads
    /// `Containers` straight off an `info` response that has no `info` wrapper at all.
    private static func findRecord(_ payload: JSONValue, _ keys: [String]) -> JSONValue {
        let wanted = Set(keys.map { $0.lowercased() })
        var queue: [JSONValue] = [payload]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            guard case .object(let object) = current else { continue }
            for pair in object.pairs where wanted.contains(pair.key.lowercased()) {
                if pair.value.isRecord { return pair.value }
            }
            for pair in object.pairs where pair.value.isRecord {
                queue.append(pair.value)
            }
        }
        return payload
    }

    /// `preferredTaskScalar(payload, keys)` — a **one-key** `findScalar` per key, which is how the
    /// task poller gets `status` to beat a deeper `state`. An empty string counts as "not
    /// answered" and the search moves on to the next key.
    private static func preferredTaskScalar(_ payload: JSONValue, _ keys: [String]) -> JSONValue? {
        for key in keys {
            guard let value = findScalar(payload, [key]) else { continue }
            if case .string(let text) = value, text.isEmpty { continue }
            return value
        }
        return nil
    }

    /// `containerText(item, keys)` — direct property reads, **case-sensitive and un-nested**,
    /// unlike everything above. A trimmed non-empty string wins; otherwise a non-empty array is
    /// joined with `", "`. An empty string does not stop the loop.
    ///
    /// `value.map(String).join(", ")` becomes `asDisplayString`, which differs from `String()`
    /// only for an array element that is itself a record — a shape Docker never sends here.
    private static func containerText(_ item: JSONValue, _ keys: [String]) -> String {
        for key in keys {
            guard let value = item[key] else { continue }
            if case .string(let text) = value {
                let trimmed = text.jsTrimmed
                if !trimmed.isEmpty { return trimmed }
                continue
            }
            if case .array(let entries) = value, !entries.isEmpty {
                return entries.map(\.asDisplayString).joined(separator: ", ")
            }
        }
        return ""
    }

    /// `item.Key ?? item.key` — `??` skips an explicit null as well as a missing key, whereas
    /// `JSONValue`'s subscript returns a perfectly good `.null` for the former.
    private static func present(_ value: JSONValue, _ key: String) -> JSONValue? {
        guard let found = value[key], !found.isNull else { return nil }
        return found
    }

    /// `Number(value)` for a value that came out of `findScalar`, kept only when finite.
    ///
    /// It switches on the case rather than routing everything through `JSCompat.number` because
    /// `Number(true)` is 1 while `JSCompat.number("true")` is NaN. The only input the two would
    /// still read differently is the literal string `"Infinity"`, which no Docker daemon reports.
    private static func finiteNumber(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        let number: Double
        switch value {
        case .number(let raw): number = raw
        case .bool(let flag): number = flag ? 1 : 0
        case .string(let text): number = JSCompat.number(text)
        default: return nil
        }
        return number.isFinite ? number : nil
    }

    /// `[...new Set(values.map(v => v.trim()).filter(Boolean))]` — trim, drop empties,
    /// de-duplicate keeping first-seen order.
    private static func uniqueTrimmed(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.jsTrimmed
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    /// The `failed` field of a batch envelope: `[{ item, error }]`.
    private static func failureList(_ failures: [DockerBatchFailure<String>]) -> JSONValue {
        .array(failures.map { .object([("item", .string($0.item)), ("error", .string($0.error))]) })
    }

    /// `[A-Za-z0-9_]` — the character class JavaScript's `\b` is defined against, which is ASCII
    /// only even in a Unicode string.
    private static func isWordCharacter(_ character: Character) -> Bool {
        character == "_" || (character.isASCII && (character.isLetter || character.isNumber))
    }

    /// `\bup\b` over an already-lower-cased string. The boundaries matter: a container whose
    /// status mentions `backup` or `upgrade` must not read as running.
    private static func containsWord(_ word: String, in text: String) -> Bool {
        let characters = Array(text)
        let target = Array(word)
        guard !target.isEmpty, characters.count >= target.count else { return false }
        for start in 0...(characters.count - target.count) {
            guard Array(characters[start..<(start + target.count)]) == target else { continue }
            let before: Character? = start > 0 ? characters[start - 1] : nil
            let after: Character? = start + target.count < characters.count
                ? characters[start + target.count]
                : nil
            if let before, isWordCharacter(before) { continue }
            if let after, isWordCharacter(after) { continue }
            return true
        }
        return false
    }

    /// `/running|active|\bup\b|paused|restarting/` — an alternation, so the order of the tests
    /// makes no difference to the answer.
    private static func looksRunningState(_ state: String) -> Bool {
        for needle in ["running", "active", "paused", "restarting"] where state.contains(needle) {
            return true
        }
        return containsWord("up", in: state)
    }

    /// `[a-f\d]{minimum,maximum}` against a lower-cased token.
    ///
    /// `Character.isHexDigit` accepts fullwidth `ａ` and `０` as well, so the test is pinned to
    /// ASCII — otherwise a fullwidth string would be mistaken for a digest.
    private static func isHexToken(_ value: String, minimum: Int, maximum: Int = .max) -> Bool {
        guard value.count >= minimum, value.count <= maximum else { return false }
        return value.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    /// `/^(?:sha256:)?[a-f\d]{12,}$/i` — the test that routes `removeImage` down its ID branch.
    private static func looksLikeImageId(_ reference: String) -> Bool {
        var body = reference.lowercased()
        if body.hasPrefix("sha256:") { body.removeFirst(7) }
        return isHexToken(body, minimum: 12)
    }

    /// `/invalid filter\s+['"]?dangling/i` — the daemon message that triggers `prune`'s
    /// compatibility path. `\s+` needs at least one space and the quote is optional, so both
    /// `invalid filter 'dangling'` and `invalid filter dangling=true` match, while
    /// `invalid filterdangling` does not. Every occurrence is tried, not just the first.
    private static func matchesDanglingFilter(_ message: String) -> Bool {
        let lowered = message.lowercased()
        var searchStart = lowered.startIndex
        while let found = lowered.range(of: "invalid filter", range: searchStart..<lowered.endIndex) {
            var index = found.upperBound
            var spaces = 0
            while index < lowered.endIndex, lowered[index].isWhitespace {
                index = lowered.index(after: index)
                spaces += 1
            }
            if spaces > 0 {
                var rest = lowered[index...]
                if rest.hasPrefix("'") || rest.hasPrefix("\"") { rest = rest.dropFirst() }
                if rest.hasPrefix("dangling") { return true }
            }
            searchStart = found.upperBound
        }
        return false
    }

    /// `{ ret: 0, stats, sampled, total }` — the envelope `refreshContainerStats` both reports
    /// through `onProgress` and returns.
    private static func statsPayload(_ stats: [JSONValue], total: Int) -> JSONValue {
        .object([
            ("ret", .int(0)),
            ("stats", .array(stats)),
            ("sampled", .int(stats.count)),
            ("total", .int(total)),
        ])
    }

    /// `item.Running ?? item.running`, then the joined state string.
    ///
    /// The `filter(Boolean).join(" ")` step renders each value with `asDisplayString` where the
    /// original uses `String()`; the two agree for every scalar and only differ if a daemon put a
    /// record in `State`.
    private static func isRunningItem(_ item: JSONValue) -> Bool {
        if let flag = present(item, "Running") ?? present(item, "running") {
            switch flag {
            case .bool(true): return true
            case .number(let raw) where raw == 1: return true
            case .string(let text):
                let normalized = text.jsTrimmed.lowercased()
                if normalized == "true" || normalized == "1" { return true }
            default: break
            }
        }
        let state = ["State", "state", "Status", "status"]
            .compactMap { key -> String? in
                guard let value = item[key], value.isTruthy else { return nil }
                return value.asDisplayString
            }
            .joined(separator: " ")
            .lowercased()
        return looksRunningState(state)
    }

    /// Step 5 of `refreshDockerContainerStats`: a target needs a non-empty id **and** a
    /// running-ish state, and its name loses Docker's leading `/`.
    private static func statsTargets(_ items: [LuckyListItem]) -> [(id: String, name: String)] {
        items.compactMap { item -> (id: String, name: String)? in
            let id = containerText(item, ["Id", "ID", "id", "ContainerID", "ContainerId"])
            let name = containerText(item, ["Names", "Name", "name", "ContainerName"])
            guard !id.isEmpty, isRunningItem(item) else { return nil }
            return (id, String(name.drop(while: { $0 == "/" })))
        }
    }

    // MARK: - Containers

    /// `listDockerContainers()` — `?all=true&includeStats=false&includeNetworkMode=true`. Stats
    /// are excluded here because `refreshContainerStats` samples them separately; asking for them
    /// inline makes the list request as slow as the slowest container.
    static func containers() async throws -> LuckyItemList {
        let raw = try await call("containers", params: [
            ("all", .bool(true)),
            ("includeStats", .bool(false)),
            ("includeNetworkMode", .bool(true)),
        ])
        return LuckyItemList(items: list(raw, ["containers", "list"]), raw: raw)
    }

    /// `getDockerContainer(id)`
    static func container(_ id: String) async throws -> JSONValue {
        try await call("containers/\(LuckyQuery.escape(id))")
    }

    /// `createDockerContainer(data)`
    @discardableResult
    static func createContainer(_ data: JSONValue) async throws -> JSONValue {
        try await call("containers", "POST", body: .value(data))
    }

    /// `editDockerContainer(id, data)` — the server destroys and recreates the container, so this
    /// gets five minutes rather than twelve seconds.
    @discardableResult
    static func editContainer(_ id: String, _ data: JSONValue) async throws -> JSONValue {
        try await call(
            "containers/\(LuckyQuery.escape(id))/edit", "POST", body: .value(data), timeout: 300
        )
    }

    /// `removeDockerContainer(id, force, removeVolumes)` — the flags travel in the query, and
    /// `LuckyQuery.docker` keeps `false`, so the plain `removeContainer(id)` really does send
    /// `?force=false&remove_volumes=false`.
    @discardableResult
    static func removeContainer(
        _ id: String,
        force: Bool = false,
        removeVolumes: Bool = false
    ) async throws -> JSONValue {
        try await call("containers/\(LuckyQuery.escape(id))", "DELETE", params: [
            ("force", .bool(force)),
            ("remove_volumes", .bool(removeVolumes)),
        ])
    }

    /// `renameDockerContainer(id, name)`
    @discardableResult
    static func renameContainer(_ id: String, name: String) async throws -> JSONValue {
        try await call(
            "containers/\(LuckyQuery.escape(id))/rename",
            "POST",
            body: .value(.object([("name", .string(name))]))
        )
    }

    /// The five lifecycle verbs `runDockerContainerAction` accepts.
    enum ContainerAction: String, Sendable, CaseIterable, Identifiable {
        case start, stop, restart, pause, unpause

        var id: String { rawValue }

        /// `{"timeout": 10}` for `stop` and `restart` only — the other three send **no body**,
        /// which is not the same as sending `{}`.
        var body: LuckyBody? {
            switch self {
            case .stop, .restart: return .value(.object([("timeout", .int(10))]))
            default: return nil
            }
        }
    }

    /// `runDockerContainerAction(id, action)`
    @discardableResult
    static func containerAction(_ id: String, _ action: ContainerAction) async throws -> JSONValue {
        try await call(
            "containers/\(LuckyQuery.escape(id))/\(action.rawValue)", "POST", body: action.body
        )
    }

    /// `getDockerContainerLogs(id, tail)` — `timestamps=true` always. The endpoint is not paged;
    /// `tail` is the whole story.
    static func containerLogs(_ id: String, tail: Int = 200) async throws -> JSONValue {
        try await call("containers/\(LuckyQuery.escape(id))/logs", params: [
            ("tail", .int(tail)),
            ("timestamps", .bool(true)),
        ])
    }

    /// `getDockerContainerStats(id)` — the sample the server already has.
    static func containerStats(_ id: String) async throws -> JSONValue {
        try await call("containers/\(LuckyQuery.escape(id))/stats-cached")
    }

    /// `getDockerContainerLiveStats(id)` — a fresh sample costs the daemon a measurement window,
    /// so this has the **shortest** timeout in the module: better to drop one cell of a stats grid
    /// than to hold the whole batch open.
    static func containerLiveStats(_ id: String) async throws -> JSONValue {
        try await call("containers/\(LuckyQuery.escape(id))/stats", timeout: 10)
    }

    /// `getDockerContainerProcesses(id)`
    static func containerProcesses(_ id: String) async throws -> JSONValue {
        try await call("containers/\(LuckyQuery.escape(id))/processes")
    }

    /// `getAllDockerContainerStats()`
    static func allContainerStats() async throws -> JSONValue {
        try await call("containers/stats-cached", timeout: 15)
    }

    /// `getDockerContainerComposeConfig(id)`
    static func containerComposeConfig(_ id: String) async throws -> JSONValue {
        try await call("containers/\(LuckyQuery.escape(id))/compose-config")
    }

    /// `setDockerContainerLabel(id, label)`
    @discardableResult
    static func setContainerLabel(_ id: String, label: String) async throws -> JSONValue {
        try await call(
            "containers/\(LuckyQuery.escape(id))/label",
            "POST",
            body: .value(.object([("label", .string(label))]))
        )
    }

    /// `removeDockerContainerLabel(id)` — a DELETE with neither body nor query.
    @discardableResult
    static func removeContainerLabel(_ id: String) async throws -> JSONValue {
        try await call("containers/\(LuckyQuery.escape(id))/label", "DELETE")
    }

    /// `uploadDockerContainerFile(id, formData)` — the boundary is generated by `MultipartBody`,
    /// and `LuckyRequest` deliberately does not set `Content-Type` for it.
    @discardableResult
    static func uploadContainerFile(_ id: String, _ form: MultipartBody) async throws -> JSONValue {
        try await call(
            "containers/\(LuckyQuery.escape(id))/files/upload",
            "POST",
            body: .multipart(form),
            timeout: LuckyClientConstants.transferTimeout
        )
    }

    /// `downloadDockerContainerFile(id, path)` — `responseKind: .blob`, so a small body that
    /// happens to parse as JSON is still treated as an envelope and surfaces the server's error
    /// rather than saving an error page as a file.
    static func downloadContainerFile(_ id: String, path: String) async throws -> JSONValue {
        try await call(
            "containers/\(LuckyQuery.escape(id))/files/download",
            params: [("path", .string(path))],
            timeout: LuckyClientConstants.transferTimeout,
            responseKind: .blob
        )
    }

    /// `exportDockerContainer(id)` — a POST that answers with a tar stream and sends no body.
    static func exportContainer(_ id: String) async throws -> JSONValue {
        try await call(
            "containers/\(LuckyQuery.escape(id))/export",
            "POST",
            timeout: LuckyClientConstants.transferTimeout,
            responseKind: .blob
        )
    }

    /// `commitDockerContainer(id, data)`
    @discardableResult
    static func commitContainer(_ id: String, _ data: JSONValue) async throws -> JSONValue {
        try await call(
            "containers/\(LuckyQuery.escape(id))/commit", "POST", body: .value(data), timeout: 300
        )
    }

    /// `copyDockerContainer(id, name)` — clones the configuration into a new container.
    @discardableResult
    static func copyContainer(_ id: String, name: String) async throws -> JSONValue {
        try await call(
            "containers/\(LuckyQuery.escape(id))/copy",
            "POST",
            body: .value(.object([("name", .string(name))])),
            timeout: 300
        )
    }

    /// `checkDockerContainerUpgrade(id)` — one registry round trip, hence a minute.
    static func checkContainerUpgrade(_ id: String) async throws -> JSONValue {
        try await call("containers/\(LuckyQuery.escape(id))/upgrade-check", timeout: 60)
    }

    /// `upgradeDockerContainer(id, data)` — pull, stop, recreate.
    @discardableResult
    static func upgradeContainer(_ id: String, _ data: JSONValue) async throws -> JSONValue {
        try await call(
            "containers/\(LuckyQuery.escape(id))/upgrade", "POST", body: .value(data), timeout: 300
        )
    }

    // MARK: - Container file browser

    /// `runDockerContainerFileOperation(id, operation, data)`.
    ///
    /// A read-only operation sends `data` as the **query string** and no body; every other one
    /// sends it as the body and no query. `delete` is the odd one out on the path as well — it
    /// posts to `files` rather than `files/delete`, and it carries a JSON body on a DELETE.
    @discardableResult
    static func containerFileOperation(
        _ id: String,
        _ operation: DockerFileOperation,
        _ data: JSONValue = .object([])
    ) async throws -> JSONValue {
        let base = "containers/\(LuckyQuery.escape(id))/files"
        // The operation segment is a safe literal in the original and is not escaped.
        let path = operation == .delete ? base : "\(base)/\(operation.rawValue)"
        return try await call(
            path,
            operation.method,
            body: operation.readOnly ? nil : .value(data),
            params: operation.readOnly ? parameters(data) : [],
            timeout: operation.longRunning ? LuckyClientConstants.transferTimeout : LuckyClientConstants.defaultTimeout
        )
    }

    /// The same call with the operation still a string — what the endpoint browser and any
    /// server-driven menu hand over. The unsupported-operation check happens **before** any
    /// request, exactly as `hasOwnProperty` does in the original.
    @discardableResult
    static func containerFileOperation(
        _ id: String,
        _ operation: String,
        _ data: JSONValue = .object([])
    ) async throws -> JSONValue {
        guard let resolved = DockerFileOperation(rawValue: operation) else {
            throw LuckyError("不支持的容器文件操作：\(operation.isEmpty ? "空" : operation)")
        }
        return try await containerFileOperation(id, resolved, data)
    }

    // MARK: - Labels, groups and ordering

    /// `getDockerLabels()`
    static func labels() async throws -> JSONValue {
        try await call("labels")
    }

    /// `getDockerLabelContainers(label)`
    static func labelContainers(_ label: String) async throws -> JSONValue {
        try await call("labels/\(LuckyQuery.escape(label))/containers")
    }

    /// `getDockerContainerGroups()`
    static func containerGroups() async throws -> JSONValue {
        try await call("container-groups")
    }

    /// `createDockerContainerGroup(data)`
    @discardableResult
    static func createContainerGroup(_ data: JSONValue) async throws -> JSONValue {
        try await call("container-groups", "POST", body: .value(data))
    }

    /// `updateDockerContainerGroup(data)` — same path, PUT instead of POST.
    @discardableResult
    static func updateContainerGroup(_ data: JSONValue) async throws -> JSONValue {
        try await call("container-groups", "PUT", body: .value(data))
    }

    /// `removeDockerContainerGroup(key)` — the key goes in the **query**, unlike the three
    /// DELETEs in this module that carry a JSON body.
    @discardableResult
    static func removeContainerGroup(key: String) async throws -> JSONValue {
        try await call("container-groups", "DELETE", params: [("key", .string(key))])
    }

    /// `getDockerContainerGroupCount(groupKey)`
    static func containerGroupCount(groupKey: String) async throws -> JSONValue {
        try await call("container-groups/count", params: [("groupKey", .string(groupKey))])
    }

    /// `reorderDockerContainerGroups(data)` — the body is whatever the screen hands over, which is
    /// an array of keys in practice but is typed as any JSON value.
    @discardableResult
    static func reorderContainerGroups(_ data: JSONValue) async throws -> JSONValue {
        try await call("container-groups/order", "PUT", body: .value(data))
    }

    /// `setDockerContainerGroupCollapsed(key, collapsed)`
    @discardableResult
    static func setContainerGroupCollapsed(key: String, collapsed: Bool) async throws -> JSONValue {
        try await call("container-groups/collapsed", "PUT", body: .value(.object([
            ("key", .string(key)),
            ("collapsed", .bool(collapsed)),
        ])))
    }

    /// `getDockerContainerGroupCollapsedStates()`
    static func containerGroupCollapsedStates() async throws -> JSONValue {
        try await call("container-groups/collapsed/states")
    }

    /// `getDockerContainerOrderMapping()`
    static func containerOrderMapping() async throws -> JSONValue {
        try await call("containers/order-mapping")
    }

    /// `updateDockerContainerOrderMapping(containerGroupMap, orderList)` — both halves are sent
    /// together, so a reorder and a regroup cannot land out of step.
    @discardableResult
    static func updateContainerOrderMapping(
        containerGroupMap: JSONValue,
        orderList: JSONValue
    ) async throws -> JSONValue {
        try await call("containers/order-mapping", "PUT", body: .value(.object([
            ("containerGroupMap", containerGroupMap),
            ("orderList", orderList),
        ])))
    }

    /// `setDockerContainerGroup(containerName, groupKey)` — keyed by **name**, not id.
    @discardableResult
    static func setContainerGroup(containerName: String, groupKey: String) async throws -> JSONValue {
        try await call("containers/set-group", "POST", body: .value(.object([
            ("containerName", .string(containerName)),
            ("groupKey", .string(groupKey)),
        ])))
    }

    /// `switchDockerContainerVersion(containerIds, targetImageRef)` — recreates every listed
    /// container against another image reference.
    @discardableResult
    static func switchContainerVersion(
        containerIds: JSONValue,
        targetImageRef: String
    ) async throws -> JSONValue {
        try await call("containers/switch-version", "POST", body: .value(.object([
            ("container_ids", containerIds),
            ("target_image_ref", .string(targetImageRef)),
        ])), timeout: 300)
    }

    // MARK: - The live stats sweep

    /// `refreshDockerContainerStats(onProgress, containerInput, signal)`.
    ///
    /// Six requests at a time, batches strictly sequential, `onProgress` once per batch with a
    /// copy of the accumulated array. A single container's failure is swallowed — one unreachable
    /// container must not blank the whole grid — with cancellation the one exception.
    ///
    /// The task group is index-tagged so the surviving entries keep the order `Promise.all` gave
    /// them; a plain `for await` would order them by completion instead.
    @discardableResult
    static func refreshContainerStats(
        items: [LuckyListItem]? = nil,
        onProgress: (@Sendable (JSONValue) -> Void)? = nil
    ) async throws -> JSONValue {
        try Task.checkCancellation()
        let rows: [LuckyListItem]
        if let items {
            rows = items
        } else {
            rows = try await containers().items
        }
        try Task.checkCancellation()
        let targets = statsTargets(rows)
        var stats: [JSONValue] = []
        var index = 0
        while index < targets.count {
            try Task.checkCancellation()
            let batch = Array(targets[index..<min(index + 6, targets.count)])
            let collected = try await withThrowingTaskGroup(of: (Int, JSONValue?).self) { group in
                for (offset, target) in batch.enumerated() {
                    group.addTask {
                        do {
                            let result = try await containerLiveStats(target.id)
                            return (offset, .object([
                                ("Id", .string(target.id)),
                                ("Name", .string(target.name)),
                                ("stats", result),
                            ]))
                        } catch {
                            // `if (requestSignal?.aborted) throw error`. `LuckyClient` rewrites a
                            // cancelled request into `LuckyError("请求已取消")`, so the task's own
                            // flag is the reliable test here, not the error's identity.
                            if Task.isCancelled { throw error }
                            return (offset, nil)
                        }
                    }
                }
                var ordered = [JSONValue?](repeating: nil, count: batch.count)
                for try await (offset, value) in group { ordered[offset] = value }
                return ordered
            }
            stats.append(contentsOf: collected.compactMap { $0 })
            onProgress?(statsPayload(stats, total: targets.count))
            index += 6
        }
        let payload = statsPayload(stats, total: targets.count)
        if targets.isEmpty { onProgress?(payload) }
        return payload
    }

    // MARK: - Images

    /// `listDockerImages()` — `?all=false`, so intermediate layers stay hidden. The flag survives
    /// into the query because `LuckyQuery.docker` keeps `false`.
    static func images() async throws -> LuckyItemList {
        let raw = try await call("images", params: [("all", .bool(false))])
        return LuckyItemList(items: list(raw, ["images", "list"]), raw: raw)
    }

    /// `getDockerImage(id)`
    static func image(_ id: String) async throws -> JSONValue {
        try await call("images/\(LuckyQuery.escape(id))")
    }

    /// `pullDockerImage(data)` — queues a task and returns immediately; `waitForTask` follows it.
    @discardableResult
    static func pullImage(_ data: JSONValue) async throws -> JSONValue {
        try await call("images/pull-async", "POST", body: .value(data))
    }

    /// `tagDockerImage(id, repository, tag)`
    @discardableResult
    static func tagImage(
        _ id: String,
        repository: String,
        tag: String = "latest"
    ) async throws -> JSONValue {
        try await call("images/\(LuckyQuery.escape(id))/tag", "POST", body: .value(.object([
            ("repository", .string(repository)),
            ("tag", .string(tag)),
        ])))
    }

    /// `searchDockerImages(term)` — the limit of 25 is the client's choice, not the server's.
    static func searchImages(_ term: String) async throws -> JSONValue {
        try await call("images/search", "POST", body: .value(.object([
            ("term", .string(term)),
            ("limit", .int(25)),
        ])))
    }

    /// `getDockerImageHistory(id)`
    static func imageHistory(_ id: String) async throws -> JSONValue {
        try await call("images/\(LuckyQuery.escape(id))/history")
    }

    /// `buildDockerImage(data)`
    @discardableResult
    static func buildImage(_ data: JSONValue) async throws -> JSONValue {
        try await call(
            "images/build", "POST",
            body: .value(data),
            timeout: LuckyClientConstants.transferTimeout
        )
    }

    /// `pullDockerImageSync(image, tag)` — holds the connection open until the pull finishes,
    /// unlike `pullImage`, which returns a task id.
    @discardableResult
    static func pullImageSync(_ image: String, tag: String = "latest") async throws -> JSONValue {
        try await call("images/pull", "POST", body: .value(.object([
            ("image", .string(image)),
            ("tag", .string(tag)),
        ])), timeout: LuckyClientConstants.transferTimeout)
    }

    /// `pushDockerImage(image, tag)`
    @discardableResult
    static func pushImage(_ image: String, tag: String = "latest") async throws -> JSONValue {
        try await call("images/push", "POST", body: .value(.object([
            ("image", .string(image)),
            ("tag", .string(tag)),
        ])), timeout: LuckyClientConstants.transferTimeout)
    }

    /// `buildDockerImageFromGit(data)`
    @discardableResult
    static func buildImageFromGit(_ data: JSONValue) async throws -> JSONValue {
        try await call(
            "images/build-from-git", "POST",
            body: .value(data),
            timeout: LuckyClientConstants.transferTimeout
        )
    }

    /// `buildDockerImageFromZip(data)` — the JSON half of the overload; the archive is named by a
    /// server-side path.
    @discardableResult
    static func buildImageFromZip(_ data: JSONValue) async throws -> JSONValue {
        try await call(
            "images/build-from-zip", "POST",
            body: .value(data),
            timeout: LuckyClientConstants.transferTimeout
        )
    }

    /// `buildDockerImageFromZip(formData)` — the multipart half, for an archive picked on device.
    @discardableResult
    static func buildImageFromZip(_ form: MultipartBody) async throws -> JSONValue {
        try await call(
            "images/build-from-zip", "POST",
            body: .multipart(form),
            timeout: LuckyClientConstants.transferTimeout
        )
    }

    /// `importDockerImage(data)`
    @discardableResult
    static func importImage(_ data: JSONValue) async throws -> JSONValue {
        try await call("images/import", "POST", body: .value(data), timeout: 300)
    }

    /// `loadDockerImage(data)` — JSON half. Note the 300 s budget rather than the 600 s the other
    /// uploads get.
    @discardableResult
    static func loadImage(_ data: JSONValue) async throws -> JSONValue {
        try await call("images/load", "POST", body: .value(data), timeout: 300)
    }

    /// `loadDockerImage(formData)` — multipart half.
    @discardableResult
    static func loadImage(_ form: MultipartBody) async throws -> JSONValue {
        try await call("images/load", "POST", body: .multipart(form), timeout: 300)
    }

    /// `getDockerImageTags(id)`
    static func imageTags(_ id: String) async throws -> JSONValue {
        try await call("images/\(LuckyQuery.escape(id))/tags")
    }

    /// `getDockerImageFilesystem(id, path)` — browses the image without starting a container.
    static func imageFilesystem(_ id: String, path: String = "/") async throws -> JSONValue {
        try await call(
            "images/\(LuckyQuery.escape(id))/filesystem", params: [("path", .string(path))]
        )
    }

    /// `checkDockerImageUpgrade(imageRef)` — one registry manifest fetch, which is slow enough to
    /// warrant 45 s but not slow enough to deserve a task.
    static func checkImageUpgrade(_ imageRef: String) async throws -> JSONValue {
        try await call(
            "images/upgrade-check", "POST",
            body: .value(.object([("image_ref", .string(imageRef))])),
            timeout: 45
        )
    }

    /// `getDockerImageUpgradeStatus(imageRef)` — the cached verdicts. An empty reference asks for
    /// every image, and the original passes no `params` object at all in that case; the query
    /// builder would have dropped the empty string anyway, so the two agree.
    static func imageUpgradeStatus(_ imageRef: String = "") async throws -> JSONValue {
        try await call(
            "images/upgrade-status",
            params: imageRef.isEmpty ? [] : [("image_ref", .string(imageRef))]
        )
    }

    /// `dismissDockerImageUpgrade(imageRef, imageId)` — hides one verdict. The empty `image_id`
    /// **is** sent, because only `undefined` is dropped by `JSON.stringify`.
    @discardableResult
    static func dismissImageUpgrade(_ imageRef: String, imageId: String = "") async throws -> JSONValue {
        try await call("images/upgrade-dismiss", "POST", body: .value(.object([
            ("image_ref", .string(imageRef)),
            ("image_id", .string(imageId)),
        ])))
    }

    /// `clearDockerImageUpgradeStatus()`
    @discardableResult
    static func clearImageUpgradeStatus() async throws -> JSONValue {
        try await call("images/upgrade-status", "DELETE")
    }

    /// `removeDockerSavedDigest(imageId)` — forgets the digest an upgrade check compares against.
    @discardableResult
    static func removeSavedDigest(_ imageId: String) async throws -> JSONValue {
        try await call(
            "images/remove-saved-digest", "POST",
            body: .value(.object([("image_id", .string(imageId))]))
        )
    }

    /// `backupDockerImageTag(imageRef)` — retags the current image so an upgrade can be undone.
    @discardableResult
    static func backupImageTag(_ imageRef: String) async throws -> JSONValue {
        try await call(
            "images/backup-tag", "POST",
            body: .value(.object([("image_ref", .string(imageRef))]))
        )
    }

    /// `getDockerImageContainers(imageRef)` — which containers a given image reference is running.
    static func imageContainers(_ imageRef: String) async throws -> JSONValue {
        try await call("images/containers", params: [("image_ref", .string(imageRef))])
    }

    /// `pullDockerImageWithBackup(imageRef, backupTag, architecture)` — the safe upgrade path: the
    /// old image is retagged first, so a bad pull can be rolled back.
    @discardableResult
    static func pullImageWithBackup(
        _ imageRef: String,
        backupTag: Bool = true,
        architecture: String = ""
    ) async throws -> JSONValue {
        try await call("images/pull-with-backup", "POST", body: .value(.object([
            ("image_ref", .string(imageRef)),
            ("backup_tag", .bool(backupTag)),
            ("architecture", .string(architecture)),
        ])), timeout: LuckyClientConstants.transferTimeout)
    }

    /// `upgradeDockerImageContainers(imageRef, upgradeCompose, upgradeStandalone, containerIds)` —
    /// recreates everything running the image. `container_ids` defaults to JSON `null`, meaning
    /// "all of them", and `null` is sent rather than omitted.
    @discardableResult
    static func upgradeImageContainers(
        _ imageRef: String,
        upgradeCompose: Bool = true,
        upgradeStandalone: Bool = true,
        containerIds: JSONValue = .null
    ) async throws -> JSONValue {
        try await call("images/upgrade-containers", "POST", body: .value(.object([
            ("image_ref", .string(imageRef)),
            ("upgrade_compose", .bool(upgradeCompose)),
            ("upgrade_standalone", .bool(upgradeStandalone)),
            ("container_ids", containerIds),
        ])), timeout: 300)
    }

    /// `removeDockerImage(reference, force)` — two branches over one argument.
    ///
    /// A bare digest or id goes in the path; anything that looks like a reference (it contains a
    /// `/` or a `:` and is not a hex id) goes to `images/remove` as a `tag` query parameter,
    /// because a path segment cannot carry a slash. `noprune=false` is spelled out in both.
    @discardableResult
    static func removeImage(_ reference: String, force: Bool = false) async throws -> JSONValue {
        let isImageId = looksLikeImageId(reference)
        if !isImageId, reference.contains("/") || reference.contains(":") {
            return try await call("images/remove", "DELETE", params: [
                ("tag", .string(reference)),
                ("force", .bool(force)),
                ("noprune", .bool(false)),
            ])
        }
        return try await call("images/\(LuckyQuery.escape(reference))", "DELETE", params: [
            ("force", .bool(force)),
            ("noprune", .bool(false)),
        ])
    }

    // MARK: - The batch runner

    /// `runDockerBatch(items, task, options)` — four workers pulling from a shared cursor.
    ///
    /// It never throws: a failing item lands in `failed` with its message, and `onProgress` fires
    /// once per completed item whether it succeeded or not (the original puts the callback in a
    /// `finally`). The `isCancelled` hook is consulted **before** an item is consumed, so a
    /// cancelled run leaves the rest untouched and reports `cancelled: true`.
    ///
    /// The original tests `cursor < items.length` before calling `isCancelled`; here the order is
    /// reversed because reading the cursor and consuming an item have to be one atomic step. The
    /// only difference is up to `concurrency` extra calls to a pure predicate.
    static func runBatch<Item: Sendable>(
        _ items: [Item],
        concurrency: Int = 4,
        onProgress: (@Sendable (DockerBatchProgress<Item>) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil,
        task: @escaping @Sendable (Item) async throws -> Void
    ) async -> DockerBatchResult<Item> {
        let state = DockerBatchState(items)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(concurrency, items.count) {
                group.addTask {
                    while true {
                        if isCancelled?() == true { return }
                        guard let item = await state.next() else { return }
                        var failure: String?
                        do {
                            try await task(item)
                        } catch {
                            // `error instanceof Error ? error.message : "请求失败"`
                            failure = error.luckyMessage()
                        }
                        onProgress?(await state.record(item, failure: failure))
                    }
                }
            }
        }
        return await state.result()
    }

    /// `removeDockerImages(references, onProgress)` — a partial failure is reported, never thrown,
    /// because deleting nine of ten images is still worth telling the user about. `force` is
    /// `false` here, unlike the prune fallback.
    @discardableResult
    static func removeImages(
        _ references: [String],
        onProgress: (@Sendable (JSONValue) -> Void)? = nil
    ) async -> JSONValue {
        let items = uniqueTrimmed(references)
        let bridge: (@Sendable (DockerBatchProgress<String>) -> Void)?
        if let onProgress {
            bridge = { progress in
                onProgress(.object([
                    ("completedCount", .int(progress.completedCount)),
                    ("totalCount", .int(progress.totalCount)),
                    ("removedCount", .int(progress.succeeded.count)),
                    ("failedCount", .int(progress.failed.count)),
                ]))
            }
        } else {
            bridge = nil
        }
        let result = await runBatch(items, onProgress: bridge) { reference in
            _ = try await removeImage(reference, force: false)
        }
        return .object([
            ("ret", .int(0)),
            ("removed", .array(result.succeeded.map { .string($0) })),
            ("failed", failureList(result.failed)),
            ("removedCount", .int(result.succeeded.count)),
            ("failedCount", .int(result.failed.count)),
            ("completedCount", .int(result.succeeded.count + result.failed.count)),
            ("totalCount", .int(items.count)),
        ])
    }

    /// `checkDockerImagesUpgrade(imageRefs, onProgress, signal)` — 45 s per image, four at a time.
    ///
    /// `results` accumulates inside the worker but is read from the **synchronous** progress
    /// callback, which is why it lives in a lock-guarded box: an actor could not be read without
    /// making that callback async, and the callback's whole point is to update a view now.
    ///
    /// Total failure escalates — if nothing succeeded, the first error is thrown — so an
    /// unreachable registry surfaces as an error instead of an empty report.
    @discardableResult
    static func checkImagesUpgrade(
        _ imageRefs: [String],
        onProgress: (@Sendable (JSONValue) -> Void)? = nil
    ) async throws -> JSONValue {
        let items = uniqueTrimmed(imageRefs)
        let box = DockerResultBox()
        let bridge: (@Sendable (DockerBatchProgress<String>) -> Void)?
        if let onProgress {
            bridge = { progress in
                onProgress(.object([
                    ("ret", .int(0)),
                    ("checked", .array(box.snapshot)),
                    ("failed", failureList(progress.failed)),
                    ("checkedCount", .int(progress.succeeded.count)),
                    ("failedCount", .int(progress.failed.count)),
                    ("completedCount", .int(progress.completedCount)),
                    ("totalCount", .int(progress.totalCount)),
                    ("inProgress", .bool(progress.completedCount < progress.totalCount)),
                ]))
            }
        } else {
            bridge = nil
        }
        let result = await runBatch(
            items, onProgress: bridge, isCancelled: { Task.isCancelled }
        ) { imageRef in
            let response = try await checkImageUpgrade(imageRef)
            box.append(.object([("imageRef", .string(imageRef)), ("result", response)]))
        }
        if result.succeeded.isEmpty, let first = result.failed.first {
            throw LuckyError(first.error)
        }
        return .object([
            ("ret", .int(0)),
            ("checked", .array(box.snapshot)),
            ("failed", failureList(result.failed)),
            ("checkedCount", .int(result.succeeded.count)),
            ("failedCount", .int(result.failed.count)),
            ("completedCount", .int(result.succeeded.count + result.failed.count)),
            ("totalCount", .int(items.count)),
            ("inProgress", .bool(false)),
        ])
    }

    // MARK: - Image identity

    /// `DOCKER_IMAGE_ID_KEYS` — where a row hides an image **id** or digest.
    private static let imageIdKeys = [
        "ImageID", "ImageId", "imageID", "imageId", "image_id", "Digest", "digest",
    ]

    /// `DOCKER_IMAGE_REFERENCE_KEYS` — where a row hides an image **reference**.
    private static let imageReferenceKeys = [
        "Image", "image", "ImageName", "imageName", "image_ref", "imageRef",
        "RepoTag", "repoTag", "RepoTags", "repoTags",
        "RepoDigest", "repoDigest", "RepoDigests", "repoDigests",
        "Tags", "tags", "Name", "name",
    ]

    /// `DOCKER_IMAGE_RECORD_ID_KEYS` — on an image row, `Id` is the image's own id, so it joins the
    /// id keys; on a container row `Id` is the *container* id and must never be read as one.
    private static let imageRecordIdKeys = ["Id", "ID", "id"] + imageIdKeys

    /// `DOCKER_CONTAINER_IMAGE_REFERENCE_KEYS` — a container's `Name` is the container's own name,
    /// so it is filtered out; on an image row the same key really is a reference.
    private static let containerImageReferenceKeys = imageReferenceKeys.filter {
        $0 != "Name" && $0 != "name"
    }

    /// `stringValues(value)` — strings and numbers only, arrays flattened all the way down. A
    /// boolean, a null or a record contributes nothing, because none of them can be a reference.
    private static func stringValues(_ value: JSONValue) -> [String] {
        switch value {
        case .string(let text):
            return [text]
        case .number:
            return [value.asDisplayString]
        case .array(let entries):
            return entries.flatMap { stringValues($0) }
        default:
            return []
        }
    }

    /// `collectImageValues(item, keys)` — a depth-limited breadth-first sweep with two different
    /// limits: arrays are followed while depth < 3, records only while depth < 2. That is deep
    /// enough for `NetworkSettings.Networks.bridge` style nesting and shallow enough that a full
    /// container inspect payload does not turn every string it contains into an alias.
    private static func collectImageValues(_ item: JSONValue, _ keys: [String]) -> [String] {
        let wanted = Set(keys.map { $0.lowercased() })
        var values: [JSONValue] = []
        var queue: [(value: JSONValue, depth: Int)] = [(item, 0)]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if case .array(let entries) = current.value {
                if current.depth < 3 {
                    queue.append(contentsOf: entries.map { ($0, current.depth + 1) })
                }
                continue
            }
            guard case .object(let object) = current.value else { continue }
            for pair in object.pairs {
                if wanted.contains(pair.key.lowercased()) { values.append(pair.value) }
                if current.depth < 2, pair.value.isRecord || pair.value.isArray {
                    queue.append((pair.value, current.depth + 1))
                }
            }
        }
        return values.flatMap { stringValues($0) }
    }

    /// `imageIdAliases(value)` — a 12-to-64 character hex token yields **both** spellings, bare and
    /// `sha256:`-prefixed, so an id written one way still matches an id written the other.
    private static func imageIdAliases(_ value: String) -> Set<String> {
        var normalized = value.jsTrimmed.lowercased()
        if normalized.hasPrefix("sha256:") { normalized.removeFirst(7) }
        guard isHexToken(normalized, minimum: 12, maximum: 64) else { return [] }
        return ["id:\(normalized)", "id:sha256:\(normalized)"]
    }

    /// `canonicalImageReference(value)` — Docker's implicit prefixes made explicit, so that
    /// `nginx`, `library/nginx` and `docker.io/library/nginx` all compare equal.
    ///
    /// The first segment counts as a registry only when it looks like a host — it contains a dot or
    /// a colon, or it is exactly `localhost` — which is the same test the daemon applies.
    private static func canonicalReference(_ value: String) -> String {
        var reference = String(value.jsTrimmed.drop(while: { $0 == "/" })).lowercased()
        guard !reference.isEmpty else { return "" }
        let parts = reference.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let first = parts[0]
        let hasRegistry = parts.count > 1
            && (first.contains(".") || first.contains(":") || first == "localhost")
        if !hasRegistry {
            reference = parts.count == 1 ? "docker.io/library/\(reference)" : "docker.io/\(reference)"
        }
        return reference
    }

    /// `/(?:^|@)(sha256:[a-f\d]{12,64})$/i` — the digest a pinned reference ends with, which is
    /// either the whole string or the part after the last `@`.
    private static func trailingDigest(_ raw: String) -> String? {
        let candidate: String
        if let at = raw.lastIndex(of: "@") {
            candidate = String(raw[raw.index(after: at)...])
        } else {
            candidate = raw
        }
        guard candidate.hasPrefix("sha256:"),
              isHexToken(String(candidate.dropFirst(7)), minimum: 12, maximum: 64)
        else { return nil }
        return candidate
    }

    /// `imageAliases(value)` — every form one string can be recognised by. `id:` aliases identify an
    /// image by content, `ref:` aliases by name, and the two namespaces never collide.
    private static func imageAliases(_ value: String) -> Set<String> {
        let raw = String(value.jsTrimmed.drop(while: { $0 == "/" })).lowercased()
        guard !raw.isEmpty else { return [] }
        var aliases = imageIdAliases(raw)
        if let digest = trailingDigest(raw) { aliases.formUnion(imageIdAliases(digest)) }
        let reference = canonicalReference(raw)
        guard !reference.isEmpty else { return aliases }
        aliases.insert("ref:\(raw)")
        aliases.insert("ref:\(reference)")
        // A reference whose last segment carries neither a tag nor a digest means `:latest`, so the
        // tagged spelling is added as well.
        let last: String
        if let slash = reference.lastIndex(of: "/") {
            last = String(reference[reference.index(after: slash)...])
        } else {
            last = reference
        }
        if !last.contains(":"), !last.contains("@") { aliases.insert("ref:\(reference):latest") }
        return aliases
    }

    /// The `id:` aliases with their prefixes stripped, keeping only tokens long enough to be
    /// unambiguous.
    private static func shortIds(_ aliases: Set<String>) -> [String] {
        aliases.compactMap { alias -> String? in
            guard alias.hasPrefix("id:") else { return nil }
            var value = String(alias.dropFirst(3))
            if value.hasPrefix("sha256:") { value.removeFirst(7) }
            return value.count >= 12 ? value : nil
        }
    }

    /// `imageAliasesIntersect(left, right)` — exact membership first, then short-id matching, because
    /// Docker's 12-character short id has to match the 64-character digest it abbreviates. Only
    /// tokens of at least 12 characters take part, so a 2-character prefix cannot claim an image.
    private static func aliasesIntersect(_ left: Set<String>, _ right: Set<String>) -> Bool {
        for alias in left where right.contains(alias) { return true }
        let leftIds = shortIds(left)
        guard !leftIds.isEmpty else { return false }
        let rightIds = shortIds(right)
        guard !rightIds.isEmpty else { return false }
        for leftId in leftIds {
            for rightId in rightIds where leftId.hasPrefix(rightId) || rightId.hasPrefix(leftId) {
                return true
            }
        }
        return false
    }

    /// `collectImageAliases(item, isImageRecord)` — every alias a row can be recognised by, plus the
    /// two facts the scan needs: whether the row identified itself at all (`hasIdentity`), and
    /// whether it gave an image **id** rather than only a reference (`hasImageId`).
    ///
    /// A container that reports only `Image: "nginx:latest"` has an identity but no image id, which
    /// is exactly the case that forces the extra image-list lookup.
    private static func collectAliases(
        _ item: JSONValue,
        imageRecord: Bool = false
    ) -> (aliases: Set<String>, hasIdentity: Bool, hasImageId: Bool) {
        let idValues = collectImageValues(item, imageRecord ? imageRecordIdKeys : imageIdKeys)
        let referenceValues = collectImageValues(
            item, imageRecord ? imageReferenceKeys : containerImageReferenceKeys
        )
        var aliases = Set<String>()
        var hasImageId = false
        for value in idValues {
            let found = imageAliases(value)
            aliases.formUnion(found)
            if found.contains(where: { $0.hasPrefix("id:") }) { hasImageId = true }
        }
        for value in referenceValues { aliases.formUnion(imageAliases(value)) }
        return (aliases, !aliases.isEmpty, hasImageId)
    }

    /// The report shape `scanUnusedDockerImages` returns and reports progress with.
    private static func scanResult(
        unused: [String],
        used: [String],
        failed: [DockerBatchFailure<String>],
        totalCount: Int
    ) -> JSONValue {
        .object([
            ("ret", .int(0)),
            ("unused", .array(unused.map { .string($0) })),
            ("used", .array(used.map { .string($0) })),
            ("failed", failureList(failed)),
            ("unusedCount", .int(unused.count)),
            ("usedCount", .int(used.count)),
            ("failedCount", .int(failed.count)),
            ("completedCount", .int(unused.count + used.count + failed.count)),
            ("totalCount", .int(totalCount)),
        ])
    }

    /// `scanUnusedDockerImages(imageIds, onProgress, signal)` — decides usage from **one** container
    /// snapshot instead of one request per image, and errs towards "used" whenever the snapshot is
    /// not trustworthy, because the caller's next step is a bulk delete.
    ///
    /// The messages here are the original's English strings, not the Chinese UI copy: they are
    /// diagnostics attached to individual rows rather than text shown as a heading.
    @discardableResult
    static func scanUnusedImages(
        _ imageIds: [String],
        onProgress: (@Sendable (JSONValue) -> Void)? = nil
    ) async throws -> JSONValue {
        let items = uniqueTrimmed(imageIds)
        var unused: [String] = []
        var used: [String] = []
        var failed: [DockerBatchFailure<String>] = []

        func report() {
            onProgress?(scanResult(unused: unused, used: used, failed: failed, totalCount: items.count))
        }
        /// Every image blamed on the same cause — used when the snapshot itself could not be read.
        func failAll(_ message: String) -> JSONValue {
            failed = items.map { DockerBatchFailure(item: $0, error: message) }
            report()
            return scanResult(unused: unused, used: used, failed: failed, totalCount: items.count)
        }

        guard !items.isEmpty else {
            report()
            return scanResult(unused: unused, used: used, failed: failed, totalCount: 0)
        }

        try Task.checkCancellation()
        let snapshot: LuckyItemList
        do {
            snapshot = try await containers()
            try Task.checkCancellation()
        } catch {
            if Task.isCancelled { throw error }
            return failAll(error.luckyMessage("Unable to read Docker containers"))
        }

        // A missing list is not an empty list: without it nothing can be called unused.
        guard let rows = findArray(snapshot.raw, ["containers", "list"]) else {
            return failAll("Unable to determine image usage safely")
        }
        let records = rows.filter(\.isRecord)
        let hasUnknownRow = records.count != rows.count
        let usage = records.map { collectAliases($0) }
        let hasUnidentifiedContainer = usage.contains { !$0.hasIdentity }
        let hasReferenceOnlyContainer = usage.contains { $0.hasIdentity && !$0.hasImageId }
        let hasImageIdCandidate = items.contains { candidate in
            imageAliases(candidate).contains { $0.hasPrefix("id:") }
        }

        // The image list is only fetched when it can actually change an answer: some container names
        // an image by reference alone *and* some input is a bare id, so the two cannot be compared
        // without the table that maps one to the other. A partial table is refused outright — a row
        // that is not a record could be the very one holding the answer.
        var indexError = "Unable to map image IDs to container references"
        var index: [Set<String>]?
        if hasReferenceOnlyContainer, hasImageIdCandidate {
            do {
                let listed = try await images()
                try Task.checkCancellation()
                if let imageRows = findArray(listed.raw, ["images", "list"]),
                   imageRows.allSatisfy(\.isRecord) {
                    index = imageRows.map { collectAliases($0, imageRecord: true).aliases }
                }
            } catch {
                if Task.isCancelled { throw error }
                let message = error.luckyMessage("")
                if !message.isEmpty { indexError = message }
            }
        }

        for imageId in items {
            try Task.checkCancellation()
            var aliases = imageAliases(imageId)
            // Folding the matching image row's aliases in is what lets a bare id match a container
            // that named only a tag.
            let matched = index?.first { aliasesIntersect(aliases, $0) }
            if let matched { aliases.formUnion(matched) }
            if usage.contains(where: { aliasesIntersect(aliases, $0.aliases) }) {
                used.append(imageId)
            } else if hasUnknownRow || hasUnidentifiedContainer {
                failed.append(
                    DockerBatchFailure(item: imageId, error: "Unable to determine image usage safely")
                )
            } else if hasReferenceOnlyContainer, hasImageIdCandidate, matched == nil {
                failed.append(DockerBatchFailure(item: imageId, error: indexError))
            } else {
                unused.append(imageId)
            }
            report()
        }
        return scanResult(unused: unused, used: used, failed: failed, totalCount: items.count)
    }

    // MARK: - Compose

    /// `listDockerComposeProjects()` — three candidate list keys, because the field name changed
    /// across server versions.
    static func composeProjects() async throws -> LuckyItemList {
        let raw = try await call("compose/projects")
        return LuckyItemList(items: list(raw, ["projects", "list", "composeProjects"]), raw: raw)
    }

    /// `createDockerCompose(data)` — `up-async` returns as soon as the work is queued, so the default
    /// timeout is enough; progress is followed through `tasks/{id}`.
    @discardableResult
    static func createCompose(_ input: DockerComposeCreateInput) async throws -> JSONValue {
        try await call("compose/up-async", "POST", body: .value(input.payload))
    }

    /// `runDockerComposeAction(action, data)`
    enum ComposeAction: String, Sendable, CaseIterable, Identifiable {
        case up, down, start, stop, restart

        var id: String { rawValue }

        /// `up` may pull and build, so it gets 300 s; the other four get 120 s.
        var timeout: TimeInterval { self == .up ? 300 : 120 }
    }

    @discardableResult
    static func composeAction(_ action: ComposeAction, _ data: JSONValue) async throws -> JSONValue {
        try await call(
            "compose/\(action.rawValue)", "POST", body: .value(data), timeout: action.timeout
        )
    }

    /// `getDockerComposeLogs(name, data)` — the body is always sent, as `{}` when no filter is given.
    static func composeLogs(
        _ name: String,
        _ data: JSONValue = .object([])
    ) async throws -> JSONValue {
        try await call("compose/\(LuckyQuery.escape(name))/logs", "POST", body: .value(data))
    }

    /// `readDockerComposeConfig(projectPath)`
    static func readComposeConfig(projectPath: String) async throws -> JSONValue {
        try await call("compose/config", "POST", body: .value(.object([
            ("project_path", .string(projectPath)),
        ])))
    }

    /// `readDockerComposeFile(workingDirectory, filename)`
    static func readComposeFile(workingDirectory: String, filename: String) async throws -> JSONValue {
        try await call("compose/read-file", "POST", body: .value(.object([
            ("working_dir", .string(workingDirectory)),
            ("filename", .string(filename)),
        ])))
    }

    /// `updateDockerComposeConfig(projectPath, content)`
    @discardableResult
    static func updateComposeConfig(projectPath: String, content: String) async throws -> JSONValue {
        try await call("compose/update-config", "POST", body: .value(.object([
            ("project_path", .string(projectPath)),
            ("content", .string(content)),
        ])))
    }

    /// `discoverDockerCompose(scanPath)` — walks a directory for `docker-compose.yml` files.
    static func discoverCompose(scanPath: String) async throws -> JSONValue {
        try await call("compose/discover", "POST", body: .value(.object([
            ("scan_path", .string(scanPath)),
        ])))
    }

    /// `backupDockerCompose(projectPath, projectName)` — archives the project directory, so it gets
    /// the transfer timeout.
    @discardableResult
    static func backupCompose(projectPath: String, projectName: String) async throws -> JSONValue {
        try await call(
            "compose/backup", "POST",
            body: .value(.object([
                ("project_path", .string(projectPath)),
                ("project_name", .string(projectName)),
            ])),
            timeout: LuckyClientConstants.transferTimeout
        )
    }

    /// `listDockerComposeBackups(projectName)`
    static func composeBackups(projectName: String) async throws -> JSONValue {
        try await call("compose/\(LuckyQuery.escape(projectName))/backups")
    }

    /// `uploadDockerComposeBackup(projectName, data)`
    @discardableResult
    static func uploadComposeBackup(projectName: String, _ form: MultipartBody) async throws -> JSONValue {
        try await call(
            "compose/\(LuckyQuery.escape(projectName))/backups/upload", "POST",
            body: .multipart(form), timeout: LuckyClientConstants.transferTimeout
        )
    }

    /// `downloadDockerComposeBackup(projectName, backup)` — the archive itself, so the response is
    /// kept as bytes rather than parsed.
    static func downloadComposeBackup(projectName: String, backup: String) async throws -> JSONValue {
        try await call(
            "compose/\(LuckyQuery.escape(projectName))/backups/download.tar.gz",
            params: [("backup", .string(backup))],
            timeout: LuckyClientConstants.transferTimeout,
            responseKind: .blob
        )
    }

    /// `removeDockerComposeBackup(projectName, backup)` — a DELETE that carries a **JSON body**
    /// rather than a query parameter, unlike the container and image deletions.
    @discardableResult
    static func removeComposeBackup(projectName: String, backup: String) async throws -> JSONValue {
        try await call(
            "compose/\(LuckyQuery.escape(projectName))/backups", "DELETE",
            body: .value(.object([("backup", .string(backup))]))
        )
    }

    /// `clearDockerComposeBackups(projectName)`
    @discardableResult
    static func clearComposeBackups(projectName: String) async throws -> JSONValue {
        try await call("compose/\(LuckyQuery.escape(projectName))/backups/all", "DELETE")
    }

    /// `restoreDockerComposeBackup(projectName, backup)`
    @discardableResult
    static func restoreComposeBackup(projectName: String, backup: String) async throws -> JSONValue {
        try await call(
            "compose/\(LuckyQuery.escape(projectName))/backups/restore", "POST",
            body: .value(.object([("backup", .string(backup))])),
            timeout: LuckyClientConstants.transferTimeout
        )
    }

    /// `restoreDockerCompose(data)` — restores a project from an uploaded archive.
    @discardableResult
    static func restoreCompose(_ form: MultipartBody) async throws -> JSONValue {
        try await call(
            "compose/restore", "POST", body: .multipart(form),
            timeout: LuckyClientConstants.transferTimeout
        )
    }

    /// `cancelDockerComposeBackup(projectName)`
    @discardableResult
    static func cancelComposeBackup(projectName: String) async throws -> JSONValue {
        try await call("compose/\(LuckyQuery.escape(projectName))/backup/cancel", "DELETE")
    }

    /// `getDockerComposeBackupStatus()` — polled while a backup runs.
    static func composeBackupStatus() async throws -> JSONValue {
        try await call("compose/backup/status")
    }

    /// `getDockerComposeContainers(projectName, projectPath)` — an empty `projectPath` produces **no**
    /// query string, because `''` is one of the values `encodeQuery` drops.
    static func composeContainers(
        projectName: String,
        projectPath: String = ""
    ) async throws -> JSONValue {
        try await call(
            "compose/\(LuckyQuery.escape(projectName))/ps",
            params: [("path", .string(projectPath))]
        )
    }

    /// `getDockerComposeContainersForCron()` — the flattened view the scheduled-task editor lists.
    static func composeContainersForCron() async throws -> JSONValue {
        try await call("compose/containers-for-cron")
    }

    /// `readDockerComposeDockerfile(projectPath)`
    static func readComposeDockerfile(projectPath: String) async throws -> JSONValue {
        try await call("compose/dockerfile", "POST", body: .value(.object([
            ("project_path", .string(projectPath)),
        ])))
    }

    /// `updateDockerComposeDockerfile(projectPath, content)`
    @discardableResult
    static func updateComposeDockerfile(projectPath: String, content: String) async throws -> JSONValue {
        try await call("compose/update-dockerfile", "POST", body: .value(.object([
            ("project_path", .string(projectPath)),
            ("content", .string(content)),
        ])))
    }

    // MARK: - Networks

    /// `listDockerNetworks()`
    static func networks() async throws -> LuckyItemList {
        let raw = try await call("networks")
        return LuckyItemList(items: list(raw, ["networks", "list"]), raw: raw)
    }

    /// `createDockerNetwork(data)`
    @discardableResult
    static func createNetwork(_ data: JSONValue) async throws -> JSONValue {
        try await call("networks", "POST", body: .value(data))
    }

    /// `removeDockerNetwork(id)`
    @discardableResult
    static func removeNetwork(_ id: String) async throws -> JSONValue {
        try await call("networks/\(LuckyQuery.escape(id))", "DELETE")
    }

    // MARK: - Volumes

    /// `listDockerVolumes()`
    static func volumes() async throws -> LuckyItemList {
        let raw = try await call("volumes")
        return LuckyItemList(items: list(raw, ["volumes", "list"]), raw: raw)
    }

    /// `createDockerVolume(data)`
    @discardableResult
    static func createVolume(_ data: JSONValue) async throws -> JSONValue {
        try await call("volumes", "POST", body: .value(data))
    }

    /// `removeDockerVolume(name)`
    @discardableResult
    static func removeVolume(_ name: String) async throws -> JSONValue {
        try await call("volumes/\(LuckyQuery.escape(name))", "DELETE")
    }

    /// `backupDockerVolume(name)` — a POST with **no** body; the volume can be large, so it gets the
    /// transfer timeout.
    @discardableResult
    static func backupVolume(_ name: String) async throws -> JSONValue {
        try await call(
            "volumes/\(LuckyQuery.escape(name))/backup", "POST",
            timeout: LuckyClientConstants.transferTimeout
        )
    }

    /// `listDockerVolumeBackups(name)`
    static func volumeBackups(_ name: String) async throws -> JSONValue {
        try await call("volumes/\(LuckyQuery.escape(name))/backups")
    }

    /// `uploadDockerVolumeBackup(name, data)`
    @discardableResult
    static func uploadVolumeBackup(_ name: String, _ form: MultipartBody) async throws -> JSONValue {
        try await call(
            "volumes/\(LuckyQuery.escape(name))/backups/upload", "POST",
            body: .multipart(form), timeout: LuckyClientConstants.transferTimeout
        )
    }

    /// `exportDockerVolume(name)` — the name travels as a query parameter here, not in the path.
    static func exportVolume(_ name: String) async throws -> JSONValue {
        try await call(
            "volumes/export", params: [("name", .string(name))],
            timeout: LuckyClientConstants.transferTimeout, responseKind: .blob
        )
    }

    /// `importDockerVolume(data)`
    @discardableResult
    static func importVolume(_ form: MultipartBody) async throws -> JSONValue {
        try await call(
            "volumes/import", "POST", body: .multipart(form),
            timeout: LuckyClientConstants.transferTimeout
        )
    }

    /// `restoreDockerVolumeBackup(name, backup)`
    @discardableResult
    static func restoreVolumeBackup(_ name: String, backup: String) async throws -> JSONValue {
        try await call(
            "volumes/\(LuckyQuery.escape(name))/backups/restore", "POST",
            body: .value(.object([("backup", .string(backup))])),
            timeout: LuckyClientConstants.transferTimeout
        )
    }

    /// `removeDockerVolumeBackup(name, backup)` — another DELETE with a JSON body.
    @discardableResult
    static func removeVolumeBackup(_ name: String, backup: String) async throws -> JSONValue {
        try await call(
            "volumes/\(LuckyQuery.escape(name))/backups", "DELETE",
            body: .value(.object([("backup", .string(backup))]))
        )
    }

    /// `cancelDockerVolumeBackup(name)`
    @discardableResult
    static func cancelVolumeBackup(_ name: String) async throws -> JSONValue {
        try await call("volumes/\(LuckyQuery.escape(name))/backup/cancel", "DELETE")
    }

    /// `getDockerVolumeBackupStatus()`
    static func volumeBackupStatus() async throws -> JSONValue {
        try await call("volumes/backup/status")
    }

    // MARK: - Tasks

    /// `listDockerTasks()`
    static func tasks() async throws -> LuckyItemList {
        let raw = try await call("tasks")
        return LuckyItemList(items: list(raw, ["tasks", "list"]), raw: raw)
    }

    /// `getDockerTask(id)`
    static func task(_ id: String) async throws -> JSONValue {
        try await call("tasks/\(LuckyQuery.escape(id))")
    }

    /// `removeDockerTask(id)`
    @discardableResult
    static func removeTask(_ id: String) async throws -> JSONValue {
        try await call("tasks/\(LuckyQuery.escape(id))", "DELETE")
    }

    /// `clearDockerTasks()` — drops the whole task history.
    @discardableResult
    static func clearTasks() async throws -> JSONValue {
        try await call("tasks", "DELETE")
    }

    /// `waitForDockerTask(id, options)` — polls `tasks/{id}` until it reaches a terminal state.
    ///
    /// The elapsed check happens **before** each poll, so a task is always polled at least once and
    /// the loop may overshoot the budget by one request plus one interval. `onProgress` fires on
    /// every poll including the terminal one, which is what lets a progress bar reach 100 % before
    /// the sheet closes.
    @discardableResult
    static func waitForTask(
        _ id: String,
        timeout: TimeInterval = 600,
        interval: TimeInterval = 1.2,
        onProgress: (@Sendable (JSONValue) -> Void)? = nil
    ) async throws -> JSONValue {
        // A caller asking for a 10 ms interval would hammer the server, so 500 ms is the floor.
        let poll = max(0.5, interval)
        let startedAt = Date()
        var last: JSONValue?
        while Date().timeIntervalSince(startedAt) < timeout {
            try Task.checkCancellation()
            let snapshot = try await Self.task(id)
            last = snapshot
            onProgress?(snapshot)
            let status = (preferredTaskScalar(snapshot, ["status", "state"])?.asDisplayString ?? "")
                .jsTrimmed
                .lowercased()
            if ["completed", "complete", "success", "succeeded"].contains(status) { return snapshot }
            if ["failed", "error", "cancelled", "canceled"].contains(status) {
                // `String(detail || …)` — `0` and `false` are falsy, so they fall back too.
                let detail = preferredTaskScalar(snapshot, ["error", "message", "output", "msg"])
                if let detail, detail.isTruthy { throw LuckyError(detail.asDisplayString) }
                throw LuckyError("Docker 任务 \(status)")
            }
            try await Task.sleep(for: .seconds(poll))
        }
        // Not trimmed or lower-cased here, unlike the comparison above: this is the server's own
        // spelling being quoted back to the user.
        let status = last.flatMap { preferredTaskScalar($0, ["status", "state"])?.asDisplayString } ?? ""
        let suffix = status.isEmpty ? "" : "，状态：\(status)"
        throw LuckyError("Docker 任务等待超时（任务 ID：\(id)\(suffix)），任务可能仍在后台执行")
    }

    // MARK: - System

    /// `getDockerInfo()`
    static func info() async throws -> JSONValue { try await call("info") }

    /// `getDockerVersion()`
    static func version() async throws -> JSONValue { try await call("version") }

    /// `getDockerDiskUsage()` — `docker system df`, which the daemon computes lazily and can be slow
    /// on a large install; it still uses the default timeout, as the original does.
    static func diskUsage() async throws -> JSONValue { try await call("disk-usage") }

    /// `getDockerMonitorStatus()`
    static func monitorStatus() async throws -> JSONValue { try await call("monitor/status") }

    /// `getDockerSelfContainerInfo()` — the container Lucky itself runs in, when it is containerised.
    static func selfContainerInfo() async throws -> JSONValue { try await call("self-container") }

    /// `getDockerConfig()`
    static func config() async throws -> JSONValue { try await call("config") }

    /// `updateDockerConfig(data)`
    @discardableResult
    static func updateConfig(_ data: JSONValue) async throws -> JSONValue {
        try await call("config", "POST", body: .value(data))
    }

    /// `getDockerLogs(pageSize, page)` — the module's own log, paged.
    static func logs(pageSize: Int = 200, page: Int = 1) async throws -> JSONValue {
        try await call("logs", params: [("pageSize", .int(pageSize)), ("page", .int(page))])
    }

    // MARK: - Registry mirrors

    /// `getDockerRegistryMirrors()`
    static func registryMirrors() async throws -> JSONValue { try await call("registry/mirrors") }

    /// `addDockerRegistryMirror(mirror)`
    @discardableResult
    static func addRegistryMirror(_ mirror: String) async throws -> JSONValue {
        try await call("registry/mirrors", "POST", body: .value(.object([
            ("mirror", .string(mirror)),
        ])))
    }

    /// `removeDockerRegistryMirror(mirror)` — the third DELETE that carries a JSON body.
    @discardableResult
    static func removeRegistryMirror(_ mirror: String) async throws -> JSONValue {
        try await call("registry/mirrors", "DELETE", body: .value(.object([
            ("mirror", .string(mirror)),
        ])))
    }

    // MARK: - Aggregates

    /// `optionalDockerRequest(request, signal)` — a failure becomes `nil` instead of propagating, so
    /// one dead endpoint cannot blank the whole overview. Cancellation still propagates.
    private static func optional<Value: Sendable>(
        _ work: @Sendable () async throws -> Value
    ) async throws -> Value? {
        do {
            return try await work()
        } catch {
            if Task.isCancelled { throw error }
            return nil
        }
    }

    /// The same shape for the settled fan-out: a rejection becomes the error record the screen shows
    /// in place of that one card.
    private static func settled(_ work: @Sendable () async throws -> JSONValue) async -> JSONValue {
        do {
            return try await work()
        } catch {
            return .object([("error", .string(error.luckyMessage("接口请求失败")))])
        }
    }

    /// `getDockerOverview()` — six requests at once, each allowed to fail on its own.
    ///
    /// The counts stay optional so the screen can tell "unavailable" from "zero": when a list
    /// endpoint failed, the count falls back to `info`'s own tally, and when that is missing or not
    /// finite it stays `nil` and the card shows a dash instead of a wrong `0`.
    static func overview() async throws -> DockerOverview {
        async let infoTask = optional { try await info() }
        async let containersTask = optional { try await containers() }
        async let imagesTask = optional { try await images() }
        async let composeTask = optional { try await composeProjects() }
        async let networksTask = optional { try await networks() }
        async let volumesTask = optional { try await volumes() }

        let (infoResult, containersResult, imagesResult) =
            try await (infoTask, containersTask, imagesTask)
        let (composeResult, networksResult, volumesResult) =
            try await (composeTask, networksTask, volumesTask)
        try Task.checkCancellation()
        if infoResult == nil, containersResult == nil, imagesResult == nil,
           composeResult == nil, networksResult == nil, volumesResult == nil {
            throw LuckyError("Docker 总览接口均不可用")
        }

        var result = DockerOverview()
        // `findRecord` falls back to the whole payload, so a flat `info` response still works.
        result.info = findRecord(infoResult ?? .object([]), ["info", "dockerInfo", "data", "result"])
        result.containers = containersResult?.items ?? []
        result.containersAvailable = containersResult != nil
        let imageRows = imagesResult?.items ?? []
        if containersResult != nil {
            result.containerCount = Double(result.containers.count)
        } else {
            result.containerCount = finiteNumber(findScalar(result.info, ["Containers", "containers"]))
        }
        if imagesResult != nil {
            result.imageCount = Double(imageRows.count)
            result.imageSize = imageRows.reduce(into: 0.0) { total, image in
                let size = findScalar(image, ["Size", "size", "VirtualSize", "virtualSize"])
                total += finiteNumber(size) ?? 0
            }
        } else {
            result.imageCount = finiteNumber(findScalar(result.info, ["Images", "images"]))
        }
        result.composeCount = composeResult?.items.count
        result.networkCount = networksResult?.items.count
        result.volumeCount = volumesResult?.items.count
        return result
    }

    /// `getDockerMaintenanceStatus()` — the seven background-state endpoints the Docker screen polls
    /// together. Individual failures never throw: each becomes `{ error }` under its own key, so a
    /// server without, say, the image-upgrade tracker still shows the other six. All seven start
    /// before the first await, and the key order is the original's.
    static func maintenanceStatus() async throws -> JSONValue {
        async let labelsTask = settled { try await labels() }
        async let groupsTask = settled { try await containerGroups() }
        async let collapsedTask = settled { try await containerGroupCollapsedStates() }
        async let orderTask = settled { try await containerOrderMapping() }
        async let upgradesTask = settled { try await imageUpgradeStatus() }
        async let composeTask = settled { try await composeBackupStatus() }
        async let volumeTask = settled { try await volumeBackupStatus() }

        var status = JSONObject()
        status["labels"] = await labelsTask
        status["containerGroups"] = await groupsTask
        status["collapsedStates"] = await collapsedTask
        status["orderMapping"] = await orderTask
        status["imageUpgrades"] = await upgradesTask
        status["composeBackup"] = await composeTask
        status["volumeBackup"] = await volumeTask
        // Cancellation is reported after the fan-out, exactly like the original's `throwIfAborted`
        // after `Promise.allSettled`.
        try Task.checkCancellation()
        return .object(status)
    }

    // MARK: - Prune

    /// `pruneDocker(data)` — the plain call, with a compatibility fallback for daemons that reject the
    /// `dangling` filter Lucky sends when pruning images.
    ///
    /// The fallback only triggers on that specific complaint and only when images were actually
    /// requested; anything else is rethrown untouched, so a permission error is not quietly turned
    /// into a slow client-side sweep.
    @discardableResult
    static func prune(_ data: JSONValue) async throws -> JSONValue {
        do {
            return try await call("prune", "POST", body: .value(data))
        } catch {
            guard matchesDanglingFilter(error.luckyMessage()),
                  data["images"]?.boolValue == true
            else { throw error }
            var remaining = data.record
            remaining["images"] = .bool(false)
            let hasOtherCleanup = ["containers", "networks", "volumes", "build_cache"].contains {
                remaining[$0]?.boolValue == true
            }
            var system = JSONValue.object([])
            if hasOtherCleanup {
                system = try await call("prune", "POST", body: .value(.object(remaining)))
            }
            let images = try await pruneUnusedImages()
            return .object([
                ("ret", .int(0)),
                ("msg", .string("已使用兼容模式清理未使用镜像")),
                ("system", system),
                ("images", images),
            ])
        }
    }

    /// `pruneUnusedDockerImages()` — the fallback body: list every image, let the scan decide which are
    /// unused, then force-delete exactly those. Uncertain images are skipped rather than deleted, and
    /// a row that carried no usable id is counted as `未知镜像` so the totals still add up.
    private static func pruneUnusedImages() async throws -> JSONValue {
        let listed = try await images()
        var ids: [String] = []
        var missingIdCount = 0
        for image in listed.items {
            // The first of `Id`, `ID`, `id` that is a non-blank **string**, kept untrimmed.
            let id = ["Id", "ID", "id"].lazy
                .compactMap { image[$0]?.stringValue }
                .first { !$0.jsTrimmed.isEmpty }
            if let id { ids.append(id) } else { missingIdCount += 1 }
        }
        let scan = try await scanUnusedImages(ids)
        let unused = (scan["unused"]?.arrayValue ?? []).map(\.asDisplayString)
        // `force = true` here: these images are known unused, and an untagged parent layer needs it.
        let removal = await runBatch(unused, concurrency: 4) { id in
            _ = try await removeImage(id, force: true)
        }
        let used = (scan["used"]?.arrayValue ?? []).map(\.asDisplayString)
        let uncertain = (scan["failed"]?.arrayValue ?? []).compactMap { entry -> String? in
            guard entry.isRecord, case .string(let text)? = entry["item"] else { return nil }
            return text
        }
        var skipped = Array(repeating: "未知镜像", count: missingIdCount)
        skipped.append(contentsOf: used)
        skipped.append(contentsOf: uncertain)
        skipped.append(contentsOf: removal.failed.map(\.item))
        return .object([
            ("removed", .array(removal.succeeded.map { .string($0) })),
            ("skipped", .array(skipped.map { .string($0) })),
            ("removedCount", .int(removal.succeeded.count)),
            ("skippedCount", .int(
                used.count + uncertain.count + removal.failed.count + missingIdCount
            )),
        ])
    }
}
