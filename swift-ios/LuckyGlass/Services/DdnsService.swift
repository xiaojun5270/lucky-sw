import Foundation

/// Port of `src/services/ddns.ts`.
///
/// Every path here uses the `compact` query builder — the DDNS module ignores parameters
/// that arrive empty, so the original drops `null` and `''` before building the string.
enum DdnsService {
    private static var client: LuckyClient { .shared }

    /// `taskScore(value)` — the fields that make a record look like a DDNS task.
    private static let taskKeys = [
        "TaskKey", "taskKey", "DDNSTaskKey", "Key", "key", "TaskName", "taskName",
        "DDNSTaskName", "Name", "name", "Records", "records", "DNSProvider", "dnsProvider",
    ]

    /// `getDdnsTasks()` — `/api/ddnstasklist` has moved the task array between keys and
    /// nesting levels across versions, and some builds return a map keyed by task id, so the
    /// best-scoring group of task-shaped records wins instead of a key lookup.
    static func tasks() async throws -> LuckyItemList {
        let raw = try await client.fetch("/api/ddnstasklist")
        return LuckyItemList(
            items: JSONUnwrap.bestScoredRecords(raw, keys: taskKeys, includeRecordValues: true),
            raw: raw
        )
    }

    static func task(_ key: String) async throws -> JSONValue {
        try await client.fetch("/api/ddns/task/\(LuckyQuery.escape(key))")
    }

    @discardableResult
    static func create(_ value: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/ddns", method: "POST", body: .value(value))
    }

    @discardableResult
    static func update(_ key: String, _ value: JSONValue) async throws -> JSONValue {
        try await client.fetch(
            "/api/ddns" + LuckyQuery.compact([("key", .string(key))]),
            method: "PUT",
            body: .value(value)
        )
    }

    @discardableResult
    static func delete(_ key: String) async throws -> JSONValue {
        try await client.fetch("/api/ddns" + LuckyQuery.compact([("key", .string(key))]), method: "DELETE")
    }

    // MARK: - Task state

    /// The three toggles are plain GETs with the flag in the query string, which is how the
    /// Lucky console calls them.
    @discardableResult
    static func setTaskEnabled(_ key: String, _ enable: Bool) async throws -> JSONValue {
        try await client.fetch(
            "/api/ddns/enable" + LuckyQuery.compact([("enable", .bool(enable)), ("key", .string(key))])
        )
    }

    @discardableResult
    static func setTaskExpanded(_ key: String, _ expanded: Bool) async throws -> JSONValue {
        try await client.fetch(
            "/api/ddns/expanded" + LuckyQuery.compact([("expanded", .bool(expanded)), ("key", .string(key))])
        )
    }

    @discardableResult
    static func setIpSectionExpanded(_ key: String, _ expanded: Bool) async throws -> JSONValue {
        try await client.fetch(
            "/api/ddns/ipsectionexpanded"
                + LuckyQuery.compact([("expanded", .bool(expanded)), ("key", .string(key))])
        )
    }

    /// `syncDdnsTask(key)` — note the camel-cased path segment, which the server is strict about.
    @discardableResult
    static func syncTask(_ key: String) async throws -> JSONValue {
        try await client.fetch("/api/ddns/manualSync/\(LuckyQuery.escape(key))")
    }

    // MARK: - Module settings

    static func configure() async throws -> JSONValue {
        try await client.fetch("/api/ddns/configure")
    }

    @discardableResult
    static func updateConfigure(_ value: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/ddns/configure", method: "PUT", body: .value(value))
    }

    static func odhcpdClients() async throws -> JSONValue {
        try await client.fetch("/api/ddns/odhcpdclients")
    }

    /// `testDdnsIpCommand(iptype, command)` — runs a shell command on the server and returns
    /// the address it printed, used by the "get IP from command" editor.
    static func testIpCommand(iptype: String, command: String) async throws -> JSONValue {
        try await client.fetch(
            "/api/ddns/getipfromcmdtest"
                + LuckyQuery.compact([("iptype", .string(iptype)), ("command", .string(command))])
        )
    }

    @discardableResult
    static func testWebhook(_ key: String, _ value: JSONValue) async throws -> JSONValue {
        try await client.fetch(
            "/api/ddns/webhooktest" + LuckyQuery.compact([("key", .string(key))]),
            method: "POST",
            body: .value(value)
        )
    }

    // MARK: - Ordering and records

    /// The reorder endpoints take a bare JSON array of keys as the body, not an envelope.
    @discardableResult
    static func reorderTasks(_ keys: JSONValue) async throws -> JSONValue {
        try await client.fetch("/api/ddns/taskorderadjustment", method: "PUT", body: .value(keys))
    }

    @discardableResult
    static func reorderRecords(taskKey: String, keys: JSONValue) async throws -> JSONValue {
        try await client.fetch(
            "/api/ddns/recordOrderadjustment/\(LuckyQuery.escape(taskKey))",
            method: "PUT",
            body: .value(keys)
        )
    }

    @discardableResult
    static func deleteRecord(taskKey: String, recordKey: String) async throws -> JSONValue {
        try await client.fetch(
            "/api/ddns/\(LuckyQuery.escape(taskKey))/\(LuckyQuery.escape(recordKey))",
            method: "DELETE"
        )
    }

    @discardableResult
    static func setRecordOption(taskKey: String, recordKey: String, option: String) async throws -> JSONValue {
        try await client.fetch(
            "/api/ddns/\(LuckyQuery.escape(taskKey))/\(LuckyQuery.escape(recordKey))"
                + "/option/\(LuckyQuery.escape(option))",
            method: "PUT"
        )
    }

    // MARK: - Logs

    static func logs(pageSize: Int = 100, page: Int = 1) async throws -> JSONValue {
        try await client.fetch(
            "/api/ddns/logs" + LuckyQuery.compact([("pageSize", .int(pageSize)), ("page", .int(page))])
        )
    }

    static func lastLogs() async throws -> JSONValue {
        try await client.fetch("/api/ddns/lastlogs")
    }
}
