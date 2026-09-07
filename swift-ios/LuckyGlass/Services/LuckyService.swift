import Foundation

/// `{ items, raw }` — a list plus the untouched payload, which the list screens keep so the
/// raw-JSON drawer can show what the server actually sent.
struct LuckyItemList: Sendable {
    var items: [LuckyListItem] = []
    var raw: JSONValue = .object([])
}

/// Port of the request half of `src/services/lucky.ts`; the log parsing lives in
/// `LogExtraction.swift`.
///
/// Every `signal?: AbortSignal` parameter in the original is dropped: structured concurrency
/// cancels the underlying `URLSession` task when the enclosing task is cancelled, which is
/// the only thing the call sites used the signal for.
enum LuckyService {
    private static var client: LuckyClient { .shared }

    // MARK: - Modules

    /// `luckyModuleItems(modules)` — `Modules` and `extraModules` concatenated, string
    /// entries promoted to records, then deduplicated by identity.
    static func moduleItems(_ modules: JSONValue) -> [LuckyModule] {
        let standard = JSONUnwrap.findArray(modules, keys: ["Modules", "modules"]) ?? []
        let extra = JSONUnwrap.findArray(modules, keys: ["extraModules", "ExtraModules"]) ?? []
        let items: [LuckyModule] = (standard + extra).compactMap { value in
            if case .string(let name) = value {
                // A module listed by name only is one the server is running, so it is enabled.
                return .object([("Key", .string(name)), ("Name", .string(name)), ("Enable", .bool(true))])
            }
            return value.isRecord ? value : nil
        }
        // Older builds answer with a flat `list`, which the two keyed lookups above miss.
        guard !items.isEmpty else {
            return JSONUnwrap.recordArray(
                modules,
                keys: ["list", "Modules", "modules", "moduleList", "extraModules"]
            )
        }
        var seen = Set<String>()
        return items.enumerated().compactMap { index, item in
            // `String(item.Key ?? item.key ?? item.Name ?? item.name ?? index)` — `??` skips
            // null as well as a missing field, so a null `Key` falls through to `key`.
            var identity: String?
            for field in ["Key", "key", "Name", "name"] {
                guard let value = item[field], !value.isNull else { continue }
                identity = value.asDisplayString
                break
            }
            return seen.insert(identity ?? String(index)).inserted ? item : nil
        }
    }

    /// `getLuckyModules()`
    static func modules() async throws -> [LuckyModule] {
        moduleItems(try await client.fetch("/api/modules/list"))
    }

    /// `getLuckyDashboard()` — four calls at once. `Promise.all` rejects with whichever call
    /// fails first in time; awaiting a tuple surfaces the first *listed* failure and cancels
    /// the others, which is what the dashboard wants either way.
    static func dashboard() async throws -> LuckyDashboard {
        async let status = client.fetch("/api/status")
        async let info = client.fetch("/api/info")
        async let modules = client.fetch("/api/modules/list")
        async let version = client.fetch("/version")
        let (statusPayload, infoPayload, modulePayload, versionPayload) =
            try await (status, info, modules, version)
        return LuckyDashboard(
            status: statusPayload,
            // `{ ...info, ...version }` — `/version` wins on the keys both return.
            info: .object(infoPayload.record.merging(versionPayload.record)),
            modules: moduleItems(modulePayload)
        )
    }

    // MARK: - Service lists and details

    /// `serviceEndpoints[kind]` — the list path and the keys the array hides under.
    private static func listEndpoint(_ kind: LuckyServiceKind) -> (path: String, keys: [String]) {
        switch kind {
        case .webservice:
            return ("/api/webservice/rules", ["rules", "ruleList", "list"])
        case .ddns:
            return ("/api/ddnstasklist", ["taskList", "list", "ddnsTaskList"])
        case .docker:
            return (
                "/api/docker/containers?all=true&includeStats=true&includeNetworkMode=true",
                ["containers", "list", "data"]
            )
        case .ssl:
            return ("/api/ssl", ["list", "sslList", "certificates"])
        }
    }

    /// `getServiceItems(kind)` — DDNS and SSL are scored rather than keyed, so they go
    /// through their own service. The `serviceEndpoints` entries for those two kinds are
    /// therefore unreachable in the original as well, and are kept above for the same reason:
    /// they document the paths the other screens use.
    static func items(_ kind: LuckyServiceKind) async throws -> LuckyItemList {
        switch kind {
        case .ddns: return try await DdnsService.tasks()
        case .ssl: return try await SslService.certificates()
        case .webservice, .docker:
            let endpoint = listEndpoint(kind)
            let payload = try await client.fetch(endpoint.path)
            return LuckyItemList(items: JSONUnwrap.recordArray(payload, keys: endpoint.keys), raw: payload)
        }
    }

    /// `getServiceDetail(kind, key)` — `detailPaths[kind](encodeURIComponent(key))`.
    static func detail(_ kind: LuckyServiceKind, key: String) async throws -> JSONValue {
        switch kind {
        case .ddns: return try await DdnsService.task(key)
        case .ssl: return try await SslService.certificate(key)
        case .webservice: return try await client.fetch("/api/webservice/rule/\(LuckyQuery.escape(key))")
        case .docker: return try await client.fetch("/api/docker/containers/\(LuckyQuery.escape(key))")
        }
    }

    // MARK: - Logs

    /// `getLogs(module)` — the whole payload flattened into lines, with no paging.
    static func logs(module: LuckyServiceKind? = nil) async throws -> [String] {
        let path = module.map { "/api/\($0.rawValue)/logs" } ?? "/api/logs"
        return LuckyLog.lines(try await client.fetch(path))
    }

    /// `getGlobalLogBatch(pre)` — an empty cursor is omitted rather than sent as `pre=`,
    /// which is what `query({ pre: pre || undefined })` does.
    static func globalLogBatch(pre: String = "") async throws -> LuckyLogBatch {
        let cursor: JSONValue? = pre.isEmpty ? nil : .string(pre)
        let payload = try await client.fetch("/api/logs" + LuckyQuery.loose([("pre", cursor)]))
        return LuckyLogBatch(payload, previousCursor: pre)
    }

    /// `getServiceLogs(kind, key, signal, page)`. A container's logs come back as a `tail`
    /// with no paging metadata, so that one case is marked unpaged — otherwise a full first
    /// page would make the screen offer a "load more" that returns the same lines.
    ///
    /// An empty `key` is falsy in JavaScript, so it behaves like a missing one.
    static func serviceLogs(
        _ kind: LuckyServiceKind,
        key: String? = nil,
        page: Int = 1
    ) async throws -> LuckyLogPage {
        switch kind {
        case .ddns:
            return LuckyLogPage(try await DdnsService.logs(pageSize: 100, page: page), page: page)
        case .ssl:
            return LuckyLogPage(try await SslService.logs(key: key ?? "", pageSize: 100, page: page), page: page)
        case .webservice, .docker:
            let safeKey = key.flatMap { $0.isEmpty ? nil : LuckyQuery.escape($0) }
            let path: String
            if kind == .docker, let safeKey {
                path = "/api/docker/containers/\(safeKey)/logs"
                    + LuckyQuery.loose([("tail", .int(100)), ("timestamps", .bool(true))])
            } else {
                path = "/api/\(kind.rawValue)/logs"
                    + LuckyQuery.loose([("pageSize", .int(100)), ("page", .int(page))])
            }
            let payload = try await client.fetch(path)
            return LuckyLogPage(
                payload,
                page: page,
                requestedPageSize: 100,
                paged: !(kind == .docker && safeKey != nil)
            )
        }
    }

    /// `getServiceLastLogs(kind, key)` — the "recent activity" tail shown on detail screens.
    /// Docker has no `lastlogs` endpoint and reuses the paged one.
    static func serviceLastLogs(_ kind: LuckyServiceKind, key: String? = nil) async throws -> LuckyLogPage {
        switch kind {
        case .ddns:
            return LuckyLogPage(try await DdnsService.lastLogs(), requestedPageSize: 100, paged: false)
        case .ssl:
            return LuckyLogPage(try await SslService.lastLogs(key: key ?? ""), requestedPageSize: 100, paged: false)
        case .docker:
            return try await serviceLogs(kind, key: key, page: 1)
        case .webservice:
            let payload = try await client.fetch("/api/\(kind.rawValue)/lastlogs")
            return LuckyLogPage(payload, requestedPageSize: 100, paged: false)
        }
    }

    // MARK: - Actions

    /// `setServiceEnabled(kind, key, enabled)` — only DDNS and SSL expose a switch; the
    /// other two screens surface the refusal as a toast.
    @discardableResult
    static func setEnabled(_ kind: LuckyServiceKind, key: String, enabled: Bool) async throws -> JSONValue {
        switch kind {
        case .ddns: return try await DdnsService.setTaskEnabled(key, enabled)
        case .ssl: return try await SslService.setCertificateEnabled(key, enabled)
        case .webservice, .docker: throw LuckyError("该模块不支持直接启停")
        }
    }

    /// `runServiceAction(kind, key, action)`. Docker's `stop` and `restart` carry a
    /// ten-second grace period; every other container action posts an empty object. The
    /// action name is interpolated unescaped, as in the original — it is never user input.
    @discardableResult
    static func runAction(_ kind: LuckyServiceKind, key: String, action: String) async throws -> JSONValue {
        let safeKey = LuckyQuery.escape(key)
        switch (kind, action) {
        case (.docker, _):
            let payload: JSONValue = action == "stop" || action == "restart"
                ? .object([("timeout", .int(10))])
                : .object([])
            return try await client.fetch(
                "/api/docker/containers/\(safeKey)/\(action)",
                method: "POST",
                body: .value(payload)
            )
        case (.ddns, "sync"): return try await DdnsService.syncTask(key)
        case (.ssl, "sync"): return try await SslService.syncCertificate(key)
        case (.ssl, "flush"): return try await SslService.flushCertificate(key)
        default: throw LuckyError("不支持的操作")
        }
    }

    /// `logoutLucky()` — `PUT /api/logout` with the literal `'{}'` body.
    @discardableResult
    static func logout() async throws -> JSONValue {
        try await client.fetch("/api/logout", method: "PUT", body: .emptyObject)
    }
}
