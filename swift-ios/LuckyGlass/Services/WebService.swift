import Foundation
import UniformTypeIdentifiers

/// Port of `src/services/webservice.ts`.
///
/// The two unwrapping helpers this module defines — `list()` (depth 5, a top-level array
/// counts, wrapper keys explored first) and `record()` (per-key breadth-first search, then
/// `ret`/`msg` stripped) — already live in `JSONUnwrap` as `list` and `nestedRecord`, so the
/// only local scraping left is the sub-rule count. Query strings go through the loose
/// builder, which is what this module's own `query()` does.
enum WebService {
    private static var client: LuckyClient { .shared }

    /// `WEB_SERVICE_GROUP_COUNT_CONCURRENCY = 4`
    private static let groupCountConcurrency = 4

    /// `WEB_SERVICE_GROUP_COUNT_KEYS` — already lower-case in the original.
    private static let groupCountKeys: Set<String> = [
        "subrulecount", "subrulenum", "subrulescount", "rulecount", "rulescount", "count",
    ]

    // MARK: - Factories

    /// `newWebServiceDefaultProxy()` — the default proxy a new rule starts with. Key order is
    /// preserved throughout this section because the editor's raw-JSON drawer shows the object
    /// as it was built.
    static func newDefaultProxy() -> JSONValue {
        .object([
            ("Key", .string("default")),
            ("GroupKey", .string("")),
            ("WebServiceType", .string("reverseproxy")),
            ("Locations", .array([])),
            ("CorazaWAFInstance", .string("")),
            ("SafeIPMode", .string("blacklist")),
            ("EasyLucky", .bool(false)),
            ("LocationInsecureSkipVerify", .bool(true)),
            ("UseTargetHost", .bool(false)),
            ("AutoProxyLocation", .bool(false)),
            ("AutoProxyLocationWithoutSameHost", .bool(false)),
            ("EnableAccessLog", .bool(true)),
            ("LogLevel", .int(4)),
            ("AccessLogMaxNum", .int(256)),
            ("WebListShowLastLogMaxCount", .int(10)),
            ("RequestInfoLogFormat", .string("[#{clientIP}][#{remoteIP}]#{tab}[#{method}][#{host}#{url}]")),
            ("RemoteIPHeaders", .array([.string("X-Forwarded-For"), .string("X-Real-IP")])),
            ("EnableBasicAuth", .bool(false)),
            ("BasicAuthUserList", .string("")),
            ("UseRuleGlobalAuthSettings", .bool(false)),
            ("OtherParams", .object([("WebAuth", .bool(false))])),
        ])
    }

    /// `newWebServiceRule()`
    static func newRule() -> JSONValue {
        .object([
            ("RuleName", .string("")),
            ("RuleKey", .string("")),
            ("DiaglogShowMode", .string("simple")),
            ("Enable", .bool(true)),
            ("Network", .string("tcp6")),
            ("ListenIP", .string("")),
            ("ListenPort", .int(16666)),
            ("IPFilterRule", .string("disable")),
            ("CorazaWAFInstance", .string("")),
            ("AutoOptionsFirewall", .bool(true)),
            ("EnableTLS", .bool(false)),
            ("TLSMinVersion", .int(2)),
            ("MaxHeaderKBytes", .int(32)),
            ("Http3", .bool(false)),
            ("DefaultProxy", newDefaultProxy()),
            ("ProxyList", .array([])),
        ])
    }

    /// `newWebServiceSubRule()`. It differs from the default proxy in four ways: it carries
    /// `Remark` and `Domains`, `EasyLucky` starts on, there is no `Key: "default"`, and
    /// `Locations` starts with one empty string rather than empty.
    static func newSubRule() -> JSONValue {
        .object([
            ("Enable", .bool(true)),
            ("Key", .string("")),
            ("Remark", .string("")),
            ("GroupKey", .string("")),
            ("WebServiceType", .string("reverseproxy")),
            ("Domains", .array([.string("")])),
            ("Locations", .array([.string("")])),
            ("CorazaWAFInstance", .string("")),
            ("SafeIPMode", .string("blacklist")),
            ("LocationInsecureSkipVerify", .bool(true)),
            ("UseTargetHost", .bool(false)),
            ("AutoProxyLocation", .bool(false)),
            ("AutoProxyLocationWithoutSameHost", .bool(false)),
            ("EnableAccessLog", .bool(true)),
            ("LogLevel", .int(4)),
            ("AccessLogMaxNum", .int(256)),
            ("WebListShowLastLogMaxCount", .int(10)),
            ("RequestInfoLogFormat", .string("[#{clientIP}][#{remoteIP}]#{tab}[#{method}][#{host}#{url}]")),
            ("RemoteIPHeaders", .array([.string("X-Forwarded-For"), .string("X-Real-IP")])),
            ("EasyLucky", .bool(true)),
            ("EnableBasicAuth", .bool(false)),
            ("BasicAuthUserList", .string("")),
            ("UseRuleGlobalAuthSettings", .bool(false)),
            ("OtherParams", .object([("WebAuth", .bool(false))])),
        ])
    }

    /// `newWebServiceGroup()`
    static func newGroup() -> JSONValue {
        .object([("Key", .string("")), ("Name", .string(""))])
    }

    /// `newWebServiceCgi()` — the trailing newline in `DefaultIndexNames` is deliberate: the
    /// field is a newline-separated list and the editor shows it in a multi-line box.
    static func newCgi() -> JSONValue {
        .object([
            ("Key", .string("")),
            ("Name", .string("")),
            ("Enable", .bool(true)),
            ("CGIType", .string("php")),
            ("Network", .string("tcp")),
            ("Address", .string("127.0.0.1:9000")),
            ("MaxConns", .int(10)),
            ("ConnectTimeout", .int(30)),
            ("ForbiddenPaths", .string("")),
            ("DefaultDocRoot", .string("")),
            ("DefaultIndexNames", .string("index.php\n")),
            ("FileExtensions", .string(".php")),
        ])
    }

    // MARK: - Sub-rule counts

    /// `Math.max(0, Math.trunc(value))`. `Int.max` stands in for a number too large to hold,
    /// which only a nonsense payload would produce — the value is a badge on a group card.
    private static func truncated(_ value: Double) -> Int {
        guard value > 0 else { return 0 }
        return value >= Double(Int.max) ? .max : Int(value.rounded(.towardZero))
    }

    /// `toCount(value)` — a finite number, or a non-blank string that `Number()` accepts.
    /// A blank string is rejected even though `Number('')` is 0, and `Number` is used rather
    /// than a digit scrape, so `"1e3"` reads as 1000 and `"12 条"` is not a count at all.
    private static func count(_ value: JSONValue) -> Int? {
        switch value {
        case .number(let number):
            return number.isFinite ? truncated(number) : nil
        case .string(let text):
            guard !text.jsTrimmed.isEmpty else { return nil }
            let parsed = JSCompat.number(text)
            return parsed.isFinite ? truncated(parsed) : nil
        default:
            return nil
        }
    }

    /// `webServiceGroupSubRuleCount(value)` — breadth-first, depth ≤ 4. Each node is first
    /// tried as a count itself, so a bare `5` in a wrapper is accepted, then its count-named
    /// keys are read. Arrays are enqueued and then skipped, exactly as in the original, where
    /// the `isRecord` guard drops them: a list of sub-rules is never counted by length.
    private static func subRuleCount(in value: JSONValue) -> Int? {
        var queue: [(value: JSONValue, depth: Int)] = [(value, 0)]
        var head = 0
        while head < queue.count {
            let (current, depth) = queue[head]
            head += 1
            if let direct = count(current) { return direct }
            guard case .object(let object) = current else { continue }
            for (key, raw) in object.pairs where groupCountKeys.contains(key.lowercased()) {
                if let found = count(raw) { return found }
            }
            if depth >= 4 { continue }
            for (_, candidate) in object.pairs where candidate.isRecord || candidate.isArray {
                queue.append((candidate, depth + 1))
            }
        }
        return nil
    }

    /// `typeof item.Key === "string" ? item.Key : typeof item.key === "string" ? item.key : ""`
    /// — a numeric key does not count, which is why this tests the case rather than coercing.
    private static func stringField(_ item: JSONValue, _ keys: [String]) -> String {
        for key in keys {
            if case .string(let text)? = item[key] { return text }
        }
        return ""
    }

    // MARK: - Supporting lists

    /// `getWebServiceCorazaInstances()` — the WAF instances the rule editor offers.
    static func corazaInstances() async throws -> [JSONValue] {
        JSONUnwrap.list(try await client.fetch("/api/coraza/instancelist"), keys: ["list", "instanceList", "instances"])
    }

    /// `getWebServiceIpFilterRules()`. The path really is `/api/ipfliter/list` — the server's
    /// own typo, and correcting it returns 404.
    static func ipFilterRules() async throws -> [JSONValue] {
        JSONUnwrap.list(try await client.fetch("/api/ipfliter/list"), keys: ["list", "rules", "ruleList"])
    }

    // MARK: - Rules

    /// `getWebServiceRules(lite)` — the lite endpoint leaves out each rule's sub-rule bodies,
    /// which is what the pickers ask for.
    static func rules(lite: Bool = false) async throws -> LuckyItemList {
        let payload = try await client.fetch(lite ? "/api/webservice/rules_lite" : "/api/webservice/rules")
        return LuckyItemList(items: JSONUnwrap.list(payload, keys: ["rules", "ruleList", "list"]), raw: payload)
    }

    static func rule(_ key: String) async throws -> JSONValue {
        JSONUnwrap.nestedRecord(
            try await client.fetch("/api/webservice/rule/\(LuckyQuery.escape(key))"),
            keys: ["rule", "data"]
        )
    }

    @discardableResult
    static func createRule(_ value: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/webservice/rules", method: "POST", body: .value(value))
    }

    @discardableResult
    static func updateRule(key: String, value: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/webservice/rule/\(LuckyQuery.escape(key))", method: "PUT", body: .value(value))
    }

    @discardableResult
    static func deleteRule(_ key: String) async throws -> JSONValue {
        try await client.fetch("/api/webservice/rule/\(LuckyQuery.escape(key))", method: "DELETE")
    }

    /// The body is a bare JSON array of keys, not an envelope.
    @discardableResult
    static func reorderRules(_ keys: [String]) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/ruleorderadjustment",
            method: "PUT",
            body: .value(.array(keys.map { .string($0) }))
        )
    }

    /// `getWebServiceSubRuleOption(ruleKey, subKey, option)` — one GET behind several
    /// operations; the option segment carries `true`/`false` when a sub-rule is toggled.
    @discardableResult
    static func subRuleOption(ruleKey: String, subKey: String, option: String) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/rule/\(LuckyQuery.escape(ruleKey))"
                + "/\(LuckyQuery.escape(subKey))/\(LuckyQuery.escape(option))"
        )
    }

    /// `setWebServiceSubRuleEnabled` — `String(enabled)`, so the segment is `true` or `false`.
    @discardableResult
    static func setSubRuleEnabled(ruleKey: String, subKey: String, enabled: Bool) async throws -> JSONValue {
        try await subRuleOption(ruleKey: ruleKey, subKey: subKey, option: enabled ? "true" : "false")
    }

    // MARK: - Groups

    /// `getWebServiceGroups({ includeCounts })`. Without counts this is a plain list; with them,
    /// the groups whose payload does not already carry a count are filled in from
    /// `/groups/subrulecount` by a four-worker pool.
    static func groups(includeCounts: Bool = false) async throws -> LuckyItemList {
        let payload = try await client.fetch("/api/webservice/groups")
        let items = JSONUnwrap.list(payload, keys: ["groups", "groupList", "list"])
        guard includeCounts else { return LuckyItemList(items: items, raw: payload) }
        var enriched = items.map { withCount($0, subRuleCount(in: $0)) }
        // A group with no key cannot be queried, so it keeps whatever the list said.
        let targets: [GroupTarget] = enriched.enumerated().compactMap { index, item in
            let key = stringField(item, ["Key", "key"])
            guard !key.isEmpty, subRuleCount(in: item) == nil else { return nil }
            return GroupTarget(index: index, key: key)
        }
        for found in try await fillCounts(targets) {
            enriched[found.index] = withCount(enriched[found.index], found.value)
        }
        return LuckyItemList(items: enriched, raw: payload)
    }

    /// `{ ...item, subRuleCount: count }` — a new key is appended, and an existing one keeps
    /// its position, which is what the object spread does.
    private static func withCount(_ item: JSONValue, _ count: Int?) -> JSONValue {
        guard let count else { return item }
        var object = item.record
        object["subRuleCount"] = .int(count)
        return .object(object)
    }

    private struct GroupTarget: Sendable {
        var index: Int
        var key: String
    }

    private struct GroupCount: Sendable {
        var index: Int
        var value: Int
    }

    /// The original's pool: `Math.min(4, missing.length)` loops sharing one cursor, so a slow
    /// group does not stall the others. A failed count leaves that group without a badge
    /// instead of failing the whole list — only cancellation propagates, which is what
    /// `if (signal?.aborted) throw error` amounts to here.
    private static func fillCounts(_ targets: [GroupTarget]) async throws -> [GroupCount] {
        guard !targets.isEmpty else { return [] }
        let cursor = WebServiceCountCursor(targets.count)
        return try await withThrowingTaskGroup(of: [GroupCount].self) { group in
            for _ in 0..<min(groupCountConcurrency, targets.count) {
                group.addTask {
                    var found: [GroupCount] = []
                    while let position = await cursor.next() {
                        let target = targets[position]
                        do {
                            let response = try await groupSubRuleCount(groupKey: target.key)
                            if let value = subRuleCount(in: response) {
                                found.append(GroupCount(index: target.index, value: value))
                            }
                        } catch {
                            if Task.isCancelled { throw error }
                        }
                    }
                    return found
                }
            }
            var all: [GroupCount] = []
            for try await chunk in group { all.append(contentsOf: chunk) }
            return all
        }
    }

    /// `getWebServiceGroupOptions()` — the same endpoint as `groups`, searched with the keys in
    /// a different order, which is enough to pick a different array out of an odd payload.
    static func groupOptions() async throws -> [JSONValue] {
        JSONUnwrap.list(try await client.fetch("/api/webservice/groups"), keys: ["list", "groups", "groupList"])
    }

    /// Only `Name` is sent — the server assigns the key, and posting one is rejected. A missing
    /// `Name` is dropped rather than sent as null, because that is what `JSON.stringify` does
    /// with an `undefined` value.
    @discardableResult
    static func createGroup(_ value: JSONValue) async throws -> JSONValue {
        var body = JSONObject()
        if let name = value["Name"] { body["Name"] = name }
        return try await client.fetch("/api/webservice/groups", method: "POST", body: .value(.object(body)))
    }

    /// The update sends the whole group, key included, and takes no query parameter.
    @discardableResult
    static func updateGroup(_ value: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/webservice/groups", method: "PUT", body: .value(value))
    }

    @discardableResult
    static func deleteGroup(_ key: String) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/groups" + LuckyQuery.loose([("key", .string(key))]),
            method: "DELETE"
        )
    }

    /// `getWebServiceGroupSubRuleCount(groupKey)` — the raw envelope; the count is scraped out
    /// of it by `subRuleCount(in:)`, because builds disagree on where they put it.
    static func groupSubRuleCount(groupKey: String) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/groups/subrulecount" + LuckyQuery.loose([("groupKey", .string(groupKey))])
        )
    }

    @discardableResult
    static func reorderGroups(_ keys: [String]) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/groups/orderadjustment",
            method: "PUT",
            body: .value(.array(keys.map { .string($0) }))
        )
    }

    // MARK: - CGI

    static func cgiList() async throws -> LuckyItemList {
        let payload = try await client.fetch("/api/webservice/cgi/list")
        return LuckyItemList(items: JSONUnwrap.list(payload, keys: ["list", "cgiList", "instances"]), raw: payload)
    }

    @discardableResult
    static func createCgi(_ value: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/webservice/cgi", method: "POST", body: .value(value))
    }

    @discardableResult
    static func updateCgi(key: String, value: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/webservice/cgi/\(LuckyQuery.escape(key))", method: "PUT", body: .value(value))
    }

    @discardableResult
    static func deleteCgi(_ key: String) async throws -> JSONValue {
        try await client.fetch("/api/webservice/cgi/\(LuckyQuery.escape(key))", method: "DELETE")
    }

    /// The flag is a path segment here (`/enable` or `/disable`), unlike the sub-rule toggle,
    /// which spells the boolean out.
    @discardableResult
    static func setCgiEnabled(_ key: String, _ enabled: Bool) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/cgi/\(LuckyQuery.escape(key))/\(enabled ? "enable" : "disable")",
            method: "PUT"
        )
    }

    // MARK: - Module settings

    /// The read and the write use different paths: `/modulesettings/frontend` returns the
    /// settings the console shows, `/modulesettings` accepts them back.
    static func settings() async throws -> JSONValue {
        JSONUnwrap.nestedRecord(
            try await client.fetch("/api/webservice/modulesettings/frontend"),
            keys: ["settings", "data"]
        )
    }

    @discardableResult
    static func updateSettings(_ value: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/webservice/modulesettings", method: "PUT", body: .value(value))
    }

    // MARK: - Logs

    static func logs(pageSize: Int = 100, page: Int = 1) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/logs" + LuckyQuery.loose([("pageSize", .int(pageSize)), ("page", .int(page))])
        )
    }

    static func lastLogs() async throws -> JSONValue {
        try await client.fetch("/api/webservice/lastlogs")
    }

    /// Per-sub-rule logs. Note the shape of these paths: the rule key sits directly under
    /// `/api/webservice/`, without the `/rule/` segment the editor endpoints use.
    static func ruleLogs(
        ruleKey: String,
        subKey: String,
        pageSize: Int = 100,
        page: Int = 1
    ) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/\(LuckyQuery.escape(ruleKey))/\(LuckyQuery.escape(subKey))/logs"
                + LuckyQuery.loose([("pageSize", .int(pageSize)), ("page", .int(page))])
        )
    }

    static func ruleLastLogs(ruleKey: String, subKey: String) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/\(LuckyQuery.escape(ruleKey))/\(LuckyQuery.escape(subKey))/lastlogs"
        )
    }

    /// `getWebServiceAccessDetails` — the live connection table behind a sub-rule's log rows,
    /// which is where the "断开" button gets its client keys.
    static func accessDetails(
        ruleKey: String,
        subKey: String,
        pageSize: Int = 100,
        page: Int = 1
    ) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/\(LuckyQuery.escape(ruleKey))/\(LuckyQuery.escape(subKey))/accessdetail"
                + LuckyQuery.loose([("pageSize", .int(pageSize)), ("page", .int(page))])
        )
    }

    static func corazaLogs(
        ruleKey: String,
        subKey: String,
        pageSize: Int = 100,
        page: Int = 1
    ) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/\(LuckyQuery.escape(ruleKey))/\(LuckyQuery.escape(subKey))/corazalogs"
                + LuckyQuery.loose([("pageSize", .int(pageSize)), ("page", .int(page))])
        )
    }

    /// The HTTP server's own log, which belongs to the rule rather than a sub-rule.
    static func httpLogs(ruleKey: String, pageSize: Int = 100, page: Int = 1) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/\(LuckyQuery.escape(ruleKey))/httpserver/logs"
                + LuckyQuery.loose([("pageSize", .int(pageSize)), ("page", .int(page))])
        )
    }

    // MARK: - Tools

    @discardableResult
    static func disconnectClient(ruleKey: String, clientKey: String) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/\(LuckyQuery.escape(ruleKey))/disconnect/\(LuckyQuery.escape(clientKey))",
            method: "DELETE"
        )
    }

    /// `flushWebServiceCache` — a GET despite being a mutation, as in the original.
    @discardableResult
    static func flushCache(ruleKey: String, subKey: String) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/\(LuckyQuery.escape(ruleKey))/\(LuckyQuery.escape(subKey))/flushcachedirspaceinfo"
        )
    }

    // MARK: - Folder update

    /// `uploadWebServiceFolder(ruleKey, subKey, mountIndex, file)` — the static-site upload,
    /// carrying the ten-minute budget the original sets with `timeoutMs: 600000`. The parts are
    /// appended in the original's order, `file` before `mountIndex`.
    ///
    /// The original throws `当前运行环境不支持文件上传` when the runtime has no `FormData`;
    /// `MultipartBody` is built by hand here, so that guard has nothing left to test.
    @discardableResult
    static func uploadFolder(
        ruleKey: String,
        subKey: String,
        mountIndex: Int,
        file: WebServiceUpload
    ) async throws -> JSONValue {
        var form = MultipartBody()
        form.append("file", filename: file.filename, mimeType: file.mimeType, content: file.content)
        form.append("mountIndex", value: String(mountIndex))
        var request = LuckyRequest(
            "/api/webservice/\(LuckyQuery.escape(ruleKey))/\(LuckyQuery.escape(subKey))/updatefolder/upload",
            method: "POST",
            body: .multipart(form)
        )
        request.timeout = LuckyClientConstants.transferTimeout
        return try await client.fetch(request)
    }

    /// The upload answers with a temporary id: the new folder only goes live once it is
    /// confirmed, and cancelling discards the staged copy.
    @discardableResult
    static func confirmFolderUpdate(ruleKey: String, subKey: String, tempId: String) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/\(LuckyQuery.escape(ruleKey))/\(LuckyQuery.escape(subKey))/updatefolder/confirm",
            method: "POST",
            body: .value(.object([("tempId", .string(tempId))]))
        )
    }

    @discardableResult
    static func cancelFolderUpdate(ruleKey: String, subKey: String, tempId: String) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/\(LuckyQuery.escape(ruleKey))/\(LuckyQuery.escape(subKey))"
                + "/updatefolder/cancel/\(LuckyQuery.escape(tempId))",
            method: "DELETE"
        )
    }

    // MARK: - Tips and templates

    static func tipInfo() async throws -> JSONValue {
        try await client.fetch("/api/webservice/tipinfo")
    }

    @discardableResult
    static func markTipRead(_ version: String) async throws -> JSONValue {
        try await client.fetch(
            "/api/webservice/tipread",
            method: "PUT",
            body: .value(.object([("version", .string(version))]))
        )
    }

    /// `getLightPanelConfigTemplate(value)` — asks the server to render a light-panel config
    /// from the posted description; the screen shows the answer in its output pane.
    static func lightPanelConfigTemplate(_ value: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/webservice/lightpanel/configtemplate", method: "POST", body: .value(value))
    }
}

/// The shared cursor behind the count pool: `while (cursor < missingIndexes.length)` with
/// `cursor++`, which four concurrent loops ran against the same variable.
private actor WebServiceCountCursor {
    private var index = 0
    private let limit: Int

    init(_ limit: Int) { self.limit = limit }

    func next() -> Int? {
        guard index < limit else { return nil }
        defer { index += 1 }
        return index
    }
}

/// `WebServiceUploadFile` — a `Blob` on web, a `{ uri, name, type }` descriptor under React
/// Native. iOS hands over a file URL instead, so the bytes and the metadata are read once,
/// here, and travel together.
struct WebServiceUpload: Sendable {
    var filename: String
    var mimeType: String?
    var content: Data

    init(filename: String, mimeType: String? = nil, content: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.content = content
    }

    /// A file the document picker returned. An unknown extension leaves `mimeType` nil, which
    /// makes the multipart builder send `application/octet-stream` — what a browser does for a
    /// `Blob` with no type of its own.
    init(url: URL) throws {
        filename = url.lastPathComponent
        mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        content = try Data(contentsOf: url)
    }
}
