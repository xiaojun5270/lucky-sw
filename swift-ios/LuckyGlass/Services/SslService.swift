import Foundation

/// Port of `src/services/ssl.ts`.
///
/// The SSL module is inconsistent about where the key goes: some endpoints take it in the
/// path, some as a query parameter, and `enable` combines both. The split is reproduced
/// exactly, because sending it the other way silently affects the wrong certificate.
enum SslService {
    private static var client: LuckyClient { .shared }

    /// `certificateScore(item)` — the fields that make a record look like a certificate.
    private static let certificateKeys = [
        "Key", "key", "Remark", "remark", "AddFrom", "CertsInfo", "ExtParams", "SyncInfo",
    ]

    /// `getSslCertificates()`. Unlike the DDNS search this one never treats an object's values
    /// as the list, so a certificate map would not be found — that matches the original.
    static func certificates() async throws -> LuckyItemList {
        let raw = try await client.fetch("/api/ssl")
        return LuckyItemList(items: JSONUnwrap.bestScoredRecords(raw, keys: certificateKeys), raw: raw)
    }

    static func certificate(_ key: String) async throws -> JSONValue {
        try await client.fetch("/api/ssl/\(LuckyQuery.escape(key))")
    }

    @discardableResult
    static func create(_ value: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/ssl", method: "POST", body: .value(value))
    }

    /// The update endpoint carries the key inside the body, so there is no path or query key.
    @discardableResult
    static func update(_ value: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/ssl", method: "PUT", body: .value(value))
    }

    @discardableResult
    static func delete(_ key: String) async throws -> JSONValue {
        try await client.fetch("/api/ssl" + LuckyQuery.compact([("key", .string(key))]), method: "DELETE")
    }

    /// Key in the path *and* the flag in the query — `PUT /api/ssl/<key>?enable=<bool>`.
    @discardableResult
    static func setCertificateEnabled(_ key: String, _ enable: Bool) async throws -> JSONValue {
        try await client.fetch(
            "/api/ssl/\(LuckyQuery.escape(key))" + LuckyQuery.compact([("enable", .bool(enable))]),
            method: "PUT"
        )
    }

    /// `flushSslCertificate(key)` — forces a renewal check.
    @discardableResult
    static func flushCertificate(_ key: String) async throws -> JSONValue {
        try await client.fetch("/api/ssl/flush" + LuckyQuery.compact([("key", .string(key))]), method: "PUT")
    }

    /// `syncSslCertificate(key)` — pushes the certificate to the sync clients. The server
    /// reports a missing permission with an untranslated sentinel in `msg`, which would reach
    /// the toast verbatim, so it is replaced with the Chinese copy the original substitutes.
    @discardableResult
    static func syncCertificate(_ key: String) async throws -> JSONValue {
        do {
            return try await client.fetch("/api/ssl/manualsync/\(LuckyQuery.escape(key))")
        } catch {
            if JSRegex.containsAny(error.luckyMessage(), ["PermissionDeniedCannotUseSyncFunction"]) {
                throw LuckyError("当前账号没有证书分发同步权限")
            }
            throw error
        }
    }

    @discardableResult
    static func reorderCertificates(_ keys: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/ssl/sslorderadjustment", method: "PUT", body: .value(keys))
    }

    // MARK: - Sync clients

    static func syncClients() async throws -> JSONValue {
        try await client.fetch("/api/ssl/syncclients")
    }

    /// `getSslSyncClientOptions()` — the same scoring search as the certificate list, with the
    /// client identity fields. Used to populate the distribution picker.
    static func syncClientOptions() async throws -> [LuckyListItem] {
        JSONUnwrap.bestScoredRecords(
            try await syncClients(),
            keys: ["Key", "ClientKey", "Name", "ClientName", "DeviceName"]
        )
    }

    // MARK: - Module settings and logs

    static func setting() async throws -> JSONValue {
        try await client.fetch("/api/ssl/setting")
    }

    @discardableResult
    static func updateSetting(_ value: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/ssl/setting", method: "PUT", body: .value(value))
    }

    /// `cancelSslAcme(key)` — aborts an in-flight ACME order.
    @discardableResult
    static func cancelAcme(_ key: String) async throws -> JSONValue {
        try await client.fetch("/api/ssl/\(LuckyQuery.escape(key))/acmecancel", method: "DELETE")
    }

    /// An empty `key` asks for the module-wide log instead of one certificate's, and the
    /// compact builder drops it, so the same call serves both screens.
    static func logs(key: String = "", pageSize: Int = 100, page: Int = 1) async throws -> JSONValue {
        try await client.fetch(
            "/api/ssl/logs" + LuckyQuery.compact([
                ("key", .string(key)), ("pageSize", .int(pageSize)), ("page", .int(page)),
            ])
        )
    }

    static func lastLogs(key: String = "") async throws -> JSONValue {
        try await client.fetch("/api/ssl/lastlogs" + LuckyQuery.compact([("key", .string(key))]))
    }
}
