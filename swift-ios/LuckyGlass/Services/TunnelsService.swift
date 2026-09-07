import Foundation

/// `TunnelKind` — the three tunnelling modules that share one screen.
enum TunnelKind: String, Sendable, CaseIterable, Identifiable {
    case stun, cloudflared, frp

    var id: String { rawValue }

    /// `tunnelTitles[kind]`
    var title: String {
        switch self {
        case .stun: return "STUN 内网穿透"
        case .cloudflared: return "Cloudflared"
        case .frp: return "FRP 内网穿透"
        }
    }

    /// Only Cloudflared and FRP have child collections.
    var supportsChildren: Bool { self != .stun }
}

/// `TunnelCollection` — a tunnel's child list. Cloudflared exposes `ingress`, FRP exposes
/// `proxies` and `visitors`.
enum TunnelCollection: String, Sendable, CaseIterable, Identifiable {
    case ingress, proxies, visitors

    var id: String { rawValue }

    /// `tunnelItems(raw, collection === 'ingress' ? 'rules' : collection)` — the ingress list
    /// arrives under `rules`, the other two under their own name.
    var responseField: String { self == .ingress ? "rules" : rawValue }
}

/// Port of `src/services/tunnels.ts`.
///
/// This module is the one place that builds query strings with `URLSearchParams`, so spaces
/// become `+` and empty values are kept — a hostname with a space would be encoded
/// differently by the other two builders. `LuckyQuery.form` reproduces it, and every call
/// site here writes its own `?` because the original does.
enum TunnelsService {
    private static var client: LuckyClient { .shared }

    // MARK: - Payload unwrapping

    /// `tunnelData(payload, field)` — the config object, wherever the envelope put it.
    static func data(_ payload: JSONValue, field: String) throws -> JSONValue {
        for source in [payload, payload["data"] ?? .null, payload["result"] ?? .null] {
            guard let candidate = source[field], candidate.isRecord else { continue }
            return candidate
        }
        throw LuckyError("服务端未返回完整配置，请刷新后重试")
    }

    /// `tunnelItems(payload, field)` — an explicit `null` list means "none yet" and is
    /// accepted; a missing list means the server did not answer the question and throws.
    static func items(_ payload: JSONValue, field: String = "list") throws -> [JSONValue] {
        for source in [payload, payload["data"] ?? .null, payload["result"] ?? .null] {
            guard let candidate = source[field] else { continue }
            if case .array(let entries) = candidate { return entries.filter(\.isRecord) }
            if candidate.isNull { return [] }
        }
        throw LuckyError("服务端未返回列表数据")
    }

    /// `keyPath(key)` — an empty key means the list on screen is stale, and hitting the
    /// endpoint without one would act on the wrong rule.
    private static func keyPath(_ key: String) throws -> String {
        guard !key.jsTrimmed.isEmpty else { throw LuckyError("规则标识缺失，请刷新列表") }
        return LuckyQuery.escape(key)
    }

    /// `write(path, method, value?)` — `undefined` sends no body at all, which matters for
    /// the DELETE calls: an empty JSON body makes some builds reject the request.
    @discardableResult
    private static func write(_ path: String, _ method: String, _ value: JSONValue? = nil) async throws -> JSONValue {
        try await client.fetch(path, method: method, body: value.map { LuckyBody.value($0) })
    }

    // MARK: - Rules

    /// `listTunnels(kind)`. A build without the module answers 404, which would otherwise
    /// surface as a bare HTTP error; the original rewrites it into module-specific advice.
    static func list(_ kind: TunnelKind) async throws -> LuckyItemList {
        do {
            let raw = try await client.fetch(kind == .stun ? "/api/stunrulelist" : "/api/\(kind.rawValue)/list")
            return LuckyItemList(items: try items(raw), raw: raw)
        } catch {
            guard looksMissing(error.luckyMessage()) else { throw error }
            throw LuckyError("当前 Lucky 服务端未提供 \(kind.title) 模块，请确认服务端版本和模块支持情况")
        }
    }

    /// `/(?:404|Request URL .*not found)/i`
    private static func looksMissing(_ message: String) -> Bool {
        let lowered = message.lowercased()
        if lowered.contains("404") { return true }
        guard let marker = lowered.range(of: "request url ") else { return false }
        return lowered[marker.upperBound...].contains("not found")
    }

    /// `value.field ?? fallback` — `??` skips an explicit null as well as a missing key.
    private static func present(_ value: JSONValue, _ field: String) -> JSONValue? {
        guard let found = value[field], !found.isNull else { return nil }
        return found
    }

    /// `getTunnel(kind, key)` — one rule, with the defaults the editor needs so its form does
    /// not have to special-case a server that omits them.
    static func get(_ kind: TunnelKind, key: String) async throws -> JSONValue {
        let safeKey = try keyPath(key)
        let path = kind == .stun ? "/api/stun/\(safeKey)" : "/api/\(kind.rawValue)/list/\(safeKey)"
        let raw = try await client.fetch(path)
        var value = try data(raw, field: kind == .stun ? "rule" : "instance").record
        switch kind {
        case .stun:
            // `value.DiaglogShowMode || 'simple'` — the server's own spelling, and an empty
            // string falls back too, which `??` would not.
            if !(value["DiaglogShowMode"]?.isTruthy ?? false) {
                value["DiaglogShowMode"] = .string("simple")
            }
        case .frp:
            let instance = JSONValue.object(value)
            value["Proxies"] = present(instance, "Proxies") ?? present(instance, "proxies") ?? .array([])
            value["Visitors"] = present(instance, "Visitors") ?? present(instance, "visitors") ?? .array([])
        case .cloudflared:
            break
        }
        return .object(value)
    }

    /// `saveTunnel(kind, value, editing)` — the same path creates and updates.
    @discardableResult
    static func save(_ kind: TunnelKind, value: JSONValue, editing: Bool) async throws -> JSONValue {
        try await write(
            kind == .stun ? "/api/stunrule" : "/api/\(kind.rawValue)/list",
            editing ? "PUT" : "POST",
            value
        )
    }

    /// STUN takes the key as a query parameter, the other two in the path.
    @discardableResult
    static func delete(_ kind: TunnelKind, key: String) async throws -> JSONValue {
        let safeKey = try keyPath(key)
        let path = kind == .stun
            ? "/api/stunrule?" + LuckyQuery.form([("key", .string(key))])
            : "/api/\(kind.rawValue)/list/\(safeKey)"
        return try await write(path, "DELETE")
    }

    /// Enabling is a GET everywhere: STUN puts the flag in the query, the other two append it
    /// to the path as `/true` or `/false`.
    @discardableResult
    static func setEnabled(_ kind: TunnelKind, key: String, enable: Bool) async throws -> JSONValue {
        let safeKey = try keyPath(key)
        let path = kind == .stun
            ? "/api/stunrule/enable?" + LuckyQuery.form([("key", .string(key)), ("enable", .bool(enable))])
            : "/api/\(kind.rawValue)/list/\(safeKey)/\(enable)"
        return try await client.fetch(path)
    }

    @discardableResult
    static func reorder(_ kind: TunnelKind, keys: [String]) async throws -> JSONValue {
        try await write(
            kind == .stun ? "/api/stun/ruleorderadjustment" : "/api/\(kind.rawValue)/orderadjustment",
            "PUT",
            .array(keys.map { .string($0) })
        )
    }

    // MARK: - STUN module settings

    static func stunSettings() async throws -> JSONValue {
        try data(try await client.fetch("/api/stun/configure"), field: "configure")
    }

    @discardableResult
    static func saveStunSettings(_ value: JSONValue) async throws -> JSONValue {
        try await write("/api/stun/configure", "PUT", value)
    }

    /// `testStunWebhook(key, value)` — a rule that has not been saved has no key yet, and the
    /// server accepts the placeholder `666` for a dry run.
    @discardableResult
    static func testStunWebhook(key: String, value: JSONValue) async throws -> JSONValue {
        try await write(
            "/api/stunrule/webhooktest?" + LuckyQuery.form([("key", .string(key.isEmpty ? "666" : key))]),
            "POST",
            value
        )
    }

    // MARK: - Logs and status

    /// An empty key asks for the module-wide log, which is the only case where the missing-key
    /// guard is skipped rather than throwing.
    static func logs(_ kind: TunnelKind, key: String, page: Int) async throws -> JSONValue {
        var prefix = ""
        if !key.isEmpty { prefix = try keyPath(key) + "/" }
        return try await client.fetch(
            "/api/\(kind.rawValue)/\(prefix)logs?"
                + LuckyQuery.form([("pageSize", .int(100)), ("page", .int(page))])
        )
    }

    static func lastLogs(_ kind: TunnelKind, key: String) async throws -> JSONValue {
        let safeKey = try keyPath(key)
        return try await client.fetch("/api/\(kind.rawValue)/\(safeKey)/lastlogs")
    }

    /// `getFrpStatus(key)` — the connection state table shown under an FRP instance.
    static func frpStatus(key: String) async throws -> JSONValue {
        let safeKey = try keyPath(key)
        return try await client.fetch("/api/frp/\(safeKey)/status")
    }

    // MARK: - Child collections

    /// `listTunnelChildren(kind, key, collection)`. Only Cloudflared and FRP reach this; the
    /// original types the parameter to exclude STUN, and the screens honour that.
    static func children(
        _ kind: TunnelKind,
        key: String,
        collection: TunnelCollection
    ) async throws -> [JSONValue] {
        let safeKey = try keyPath(key)
        let raw = try await client.fetch("/api/\(kind.rawValue)/\(safeKey)/\(collection.rawValue)")
        return try items(raw, field: collection.responseField)
    }

    /// `saveTunnelChild(...)`. Editing sends the identity the entry had *before* the edit
    /// alongside the new one, because these collections have no stable id — the server matches
    /// an ingress rule on hostname plus path and a proxy or visitor on name.
    @discardableResult
    static func saveChild(
        _ kind: TunnelKind,
        key: String,
        collection: TunnelCollection,
        value: JSONValue,
        previous: JSONValue? = nil
    ) async throws -> JSONValue {
        let safeKey = try keyPath(key)
        var payload = value
        if let previous {
            switch collection {
            case .ingress:
                payload = .object([
                    ("oldHostname", present(previous, "hostname") ?? .string("")),
                    ("oldPath", present(previous, "path") ?? .string("")),
                    ("newRule", value),
                ])
            case .proxies, .visitors:
                var object = JSONObject()
                // `{ oldName: previous.name, … }` — a missing name is dropped by
                // `JSON.stringify`, while an explicit null is sent as null.
                if let name = previous["name"] { object["oldName"] = name }
                object[collection == .proxies ? "newProxy" : "newVisitor"] = value
                payload = .object(object)
            }
        }
        return try await write(
            "/api/\(kind.rawValue)/\(safeKey)/\(collection.rawValue)",
            previous == nil ? "POST" : "PUT",
            payload
        )
    }

    /// Ingress rules are deleted by hostname and path, proxies and visitors by name.
    @discardableResult
    static func deleteChild(
        _ kind: TunnelKind,
        key: String,
        collection: TunnelCollection,
        value: JSONValue
    ) async throws -> JSONValue {
        let safeKey = try keyPath(key)
        let suffix: String
        if collection == .ingress {
            suffix = "?" + LuckyQuery.form([
                ("hostname", present(value, "hostname") ?? .string("")),
                ("path", present(value, "path") ?? .string("")),
            ])
        } else {
            suffix = "/" + (try keyPath((present(value, "name") ?? .string("")).asDisplayString))
        }
        return try await write("/api/\(kind.rawValue)/\(safeKey)/\(collection.rawValue)\(suffix)", "DELETE")
    }

    // MARK: - Cloudflare DNS

    /// `cloudflareDns(key, hostname, action)` — checks, creates or deletes the CNAME that
    /// points a hostname at the tunnel. Creation always asks for Cloudflare's proxy.
    enum DnsAction: String, Sendable, CaseIterable, Identifiable {
        case check, create, delete

        var id: String { rawValue }
    }

    @discardableResult
    static func cloudflareDns(key: String, hostname: String, action: DnsAction) async throws -> JSONValue {
        let safeKey = try keyPath(key)
        let path = "/api/cloudflared/\(safeKey)/cname/\(action.rawValue)"
        let hostnameQuery = LuckyQuery.form([("hostname", .string(hostname))])
        switch action {
        case .create:
            return try await write(path, "POST", .object([
                ("hostname", .string(hostname)), ("proxied", .bool(true)),
            ]))
        case .delete:
            return try await write("\(path)?\(hostnameQuery)", "DELETE")
        case .check:
            return try await client.fetch("\(path)?\(hostnameQuery)")
        }
    }

    // MARK: - Log flattening

    /// `tunnelLogLines(value)` — the tunnel modules answer with a string, an array, a
    /// `{ LogTime, LogContent }` record, or any of those behind one of eight wrapper keys.
    /// This is deliberately separate from `LuckyLog.lines`: it keeps the timestamp on the line
    /// and stops at the first wrapper it recognises.
    static func logLines(_ value: JSONValue?) -> [String] {
        guard let value, !value.isNull else { return [] }
        switch value {
        case .string(let text):
            // `.filter(Boolean)` drops empty lines but keeps whitespace-only ones.
            return text.jsLines.filter { !$0.isEmpty }
        case .array(let entries):
            return entries.flatMap { logLines($0) }
        case .object(let object):
            if let content = object["LogContent"], !content.isNull {
                let time = present(value, "LogTime")?.asDisplayString ?? ""
                return ["\(time) \(content.asDisplayString)".jsTrimmed]
            }
            for key in ["logs", "lastLogs", "LastLogs", "data", "result", "Response", "message", "output"]
            where object.has(key) {
                return logLines(object[key])
            }
            return []
        default:
            return []
        }
    }
}
