import Foundation

struct DeadlineExceeded: Error {}

/// Absolute request deadline, matching the original's `AbortController` + `setTimeout`
/// pair. `URLSession`'s own timeouts are idle timeouts, which is not the same thing.
func withDeadline<T: Sendable>(
    _ seconds: TimeInterval,
    _ operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            throw DeadlineExceeded()
        }
        guard let result = try await group.next() else { throw DeadlineExceeded() }
        group.cancelAll()
        return result
    }
}

extension LuckyClient {
    /// Lucky normally returns a JSON envelope, but file and log endpoints can return
    /// plain text, an empty response, or binary data. This reproduces the original
    /// branch order exactly — reordering it changes which endpoints break.
    static func envelope(
        data: Data,
        response: HTTPURLResponse,
        kind: LuckyRequest.ResponseKind
    ) throws -> JSONValue {
        let rawContentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        let contentType = rawContentType.lowercased()
        let filename = decodeFilename(response.value(forHTTPHeaderField: "Content-Disposition"))
        let ok = (200..<300).contains(response.statusCode)
        let httpFailure = "请求失败（HTTP \(response.statusCode)）"

        // An auth failure must not be swallowed by the binary branch below; the token
        // refresh path still applies even when the response has no content type.
        if response.statusCode == 401 { return .object([("ret", .number(-1))]) }

        if response.statusCode == 204 || response.value(forHTTPHeaderField: "Content-Length") == "0" {
            return .object([("ret", .number(0))])
        }

        if kind == .blob, !contentType.contains("application/json"), !contentType.contains("+json") {
            if !ok {
                let detail = data.count <= 65_536 ? String(decoding: data, as: UTF8.self).jsTrimmed : ""
                throw LuckyError(detail.isEmpty ? httpFailure : detail)
            }
            // A small body may still be an error envelope rather than a file.
            if data.count <= 1_048_576, let parsed = JSONParser.tryParse(data) {
                return payloadFromJson(parsed)
            }
            return binaryPayload(data, contentType: rawContentType, filename: filename)
        }

        if kind == .text || contentType.hasPrefix("text/")
            || contentType.contains("xml") || contentType.contains("yaml") {
            let raw = String(decoding: data, as: UTF8.self)
            if !ok { throw LuckyError(raw.isEmpty ? httpFailure : raw) }
            return textPayload(raw)
        }

        if kind == .json || contentType.contains("application/json")
            || contentType.contains("+json") || contentType.isEmpty {
            if let parsed = JSONParser.tryParse(data) { return payloadFromJson(parsed) }
            let raw = String(decoding: data, as: UTF8.self)
            if !ok { throw LuckyError(raw.isEmpty ? httpFailure : raw) }
            // Some proxies omit Content-Type for text responses.
            return textPayload(raw)
        }

        if !ok { throw LuckyError(httpFailure) }
        return binaryPayload(data, contentType: rawContentType, filename: filename)
    }

    /// `payloadFromJson` — keep the server's own fields and normalise `ret`.
    static func payloadFromJson(_ parsed: JSONValue) -> JSONValue {
        if case .object(var object) = parsed {
            let normalised = JSONValue.object(object).retValue ?? 0
            object["ret"] = .number(Double(normalised))
            return .object(object)
        }
        return .object([("ret", .number(0)), ("data", parsed)])
    }

    private static func textPayload(_ raw: String) -> JSONValue {
        raw.jsTrimmed.isEmpty
            ? .object([("ret", .number(0))])
            : .object([("ret", .number(0)), ("data", .string(raw))])
    }

    private static func binaryPayload(_ data: Data, contentType: String, filename: String?) -> JSONValue {
        var object = JSONObject([
            ("ret", .number(0)),
            ("data", .binary(data)),
            ("contentType", .string(contentType)),
        ])
        if let filename { object["filename"] = .string(filename) }
        object["byteLength"] = .number(Double(data.count))
        return .object(object)
    }

    /// `decodeFilename` — `/filename\*=UTF-8''([^;]+)/i` first, then
    /// `/filename="?([^";]+)"?/i`. A malformed escape falls back to the raw capture,
    /// which is what `decodeURIComponent`'s `try/catch` does in the original.
    static func decodeFilename(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        var raw: String?

        if let marker = value.range(of: "filename*=UTF-8''", options: .caseInsensitive) {
            let captured = String(value[marker.upperBound...].prefix { $0 != ";" })
            if !captured.isEmpty { raw = captured }
        }
        if raw == nil, let marker = value.range(of: "filename=", options: .caseInsensitive) {
            var tail = value[marker.upperBound...]
            if tail.hasPrefix("\"") { tail = tail.dropFirst() }
            let captured = String(tail.prefix { $0 != "\"" && $0 != ";" })
            if !captured.isEmpty { raw = captured }
        }

        guard let raw else { return nil }
        return JSCompat.decodeURIComponent(raw)
    }
}
