import Foundation

/// `LuckyEndpointResult` — what the debugger shows after a call. Unlike the rest of the port this
/// keeps the transport details (status, content type, filename, byte length) because the whole
/// point of the screen is to show them.
struct LuckyEndpointResult: Sendable {
    /// `kind: 'json' | 'text' | 'binary' | 'empty'`
    enum Kind: String, Sendable {
        case json, text, binary, empty
    }

    var status: Int
    var contentType: String
    var filename: String?
    var kind: Kind
    /// The parsed envelope for `.json`, the raw string for `.text`, nothing otherwise.
    var data: JSONValue?
    var byteLength: Int?
    var blob: Data?

    init(
        status: Int,
        contentType: String,
        filename: String? = nil,
        kind: Kind,
        data: JSONValue? = nil,
        byteLength: Int? = nil,
        blob: Data? = nil
    ) {
        self.status = status
        self.contentType = contentType
        self.filename = filename
        self.kind = kind
        self.data = data
        self.byteLength = byteLength
        self.blob = blob
    }
}

/// Port of `src/services/lucky-endpoints.ts` — the runner behind the 45-module / 328-endpoint
/// browser.
///
/// The registry lookups (`getLuckyModules`, `getLuckyEndpoints`, `getLuckyEndpoint`) live in
/// `LuckyEndpointRegistry`; everything else in that module is here.
///
/// This is the one caller that does **not** go through `LuckyClient.fetch`: the debugger has to
/// surface the status line, the content type, the `Content-Disposition` filename and the raw byte
/// count, it picks its own 20 s / 600 s deadline from the path, and it runs its own 401 /
/// `ret === -1` recovery. Reusing the envelope decoder would collapse all of that into a
/// `JSONValue`.
enum EndpointRunner {
    // MARK: - Action classification

    /// The literal alternatives of
    /// `/\/(reboot_program|restoreconfigureconfirm|update\/comfire|manualsync|[^/]*flush[^/]*|enable|expanded|ipsectionexpanded|wakeup|shutdown|restart|start|stop|down|up|prune|remove|build|pull|push|import|export|load|dojobs|cancel|[^/]*test|[^/]*orderadjustment)(\/|$)/i`,
    /// minus the three wildcard ones and `update/comfire`, which are handled separately below.
    private static let dangerousSegments: Set<String> = [
        "reboot_program", "restoreconfigureconfirm", "manualsync", "enable", "expanded",
        "ipsectionexpanded", "wakeup", "shutdown", "restart", "start", "stop", "down", "up",
        "prune", "remove", "build", "pull", "push", "import", "export", "load", "dojobs", "cancel",
    ]

    /// `/\/(upload|import|load|restore|export|build|pull|push|backup|download)(?:[/?]|$)/i`
    private static let longRunningSegments: Set<String> = [
        "upload", "import", "load", "restore", "export", "build", "pull", "push", "backup",
        "download",
    ]

    /// Both regexes require a `/` on the left of the alternative, so the first component of a
    /// string that does not start with `/` is not eligible. Splitting keeps empty components so
    /// `//` behaves the same way it does in the regex engine.
    private static func delimitedSegments(_ path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .dropFirst()
            .map { $0.lowercased() }
    }

    /// `dangerousGetActions.test(path)`. The right delimiter is `/` or end-of-string only, so a
    /// segment that carries a query (`stop?x=1`) does not match — which is why the caller tests the
    /// path before the query is appended.
    private static func matchesDangerousAction(_ path: String) -> Bool {
        let segments = delimitedSegments(path)
        for (offset, segment) in segments.enumerated() {
            if dangerousSegments.contains(segment) { return true }
            // `[^/]*flush[^/]*` — `[^/]*` also swallows a query, so "contains" is the right test.
            if segment.contains("flush") { return true }
            // `[^/]*test` and `[^/]*orderadjustment` still need the delimiter right after.
            if segment.hasSuffix("test") || segment.hasSuffix("orderadjustment") { return true }
            // The upstream typo, and the only alternative that spans two segments.
            if segment == "update", offset + 1 < segments.count, segments[offset + 1] == "comfire" {
                return true
            }
        }
        return false
    }

    /// `longRunningActions.test(path)` — `?` counts as a delimiter here, so this still fires once
    /// the query string is in place.
    private static func matchesLongRunningAction(_ path: String) -> Bool {
        delimitedSegments(path).contains { segment in
            longRunningSegments.contains(String(segment.prefix { $0 != "?" }))
        }
    }

    /// `isDangerousLuckyRequest(endpoint, method, dynamicPath = '')` — everything that is not a GET
    /// is dangerous; a GET is judged by its path. The candidate is built with the endpoint's
    /// trailing slashes stripped and the dynamic part's leading slashes stripped, and the dynamic
    /// part is tested for blankness *trimmed* but appended **untrimmed**.
    static func isDangerous(
        _ endpoint: LuckyEndpointDefinition,
        method: LuckyHttpMethod,
        dynamicPath: String = ""
    ) -> Bool {
        guard method == .get else { return true }
        let candidate = dynamicPath.jsTrimmed.isEmpty
            ? endpoint.path
            : endpoint.path.withoutTrailingSlashes + "/"
                + String(dynamicPath.drop(while: { $0 == "/" }))
        return matchesDangerousAction(candidate)
    }

    // MARK: - Query serialisation

    /// `entry.field ?? …` — `??` falls through a missing key *and* an explicit null, but not `''`.
    private static func present(_ value: JSONValue, _ field: String) -> JSONValue? {
        guard let found = value[field], !found.isNull else { return nil }
        return found
    }

    /// `appendQueryValue(params, key, value)`. An empty key, `undefined`, `null` and the empty
    /// *string* are dropped; `0` and `false` are kept. An array repeats the key once per element,
    /// recursively, so nested arrays flatten under the same key. A record is `JSON.stringify`d.
    private static func appendQueryValue(
        _ params: inout [String],
        _ key: String,
        _ value: JSONValue?
    ) {
        guard !key.isEmpty, let value, !value.isNull else { return }
        if case .array(let entries) = value {
            for entry in entries { appendQueryValue(&params, key, entry) }
            return
        }
        let text: String
        if value.isRecord {
            text = JSONSerializer.stringify(value)
        } else {
            text = value.asDisplayString
            guard !text.isEmpty else { return }
        }
        params.append("\(JSCompat.encodeURIComponent(key))=\(JSCompat.encodeURIComponent(text))")
    }

    /// `appendQuery(path, query)` — a record contributes its pairs in insertion order with verbatim
    /// keys; an array contributes one pair per element, each taking its key from the first present of
    /// `key`/`Key`/`name`/`Name` (trimmed) and its value from `value ?? Value`. Elements that are
    /// not records are emitted under the literal key `value`.
    ///
    /// Divergence: the original would happily walk a *string* query through `Object.entries` and
    /// emit `0=a&1=b`; neither screen can produce that, so a scalar query is ignored here.
    private static func appendQuery(_ path: String, _ query: JSONValue?) -> String {
        guard let query else { return path }
        var params: [String] = []
        switch query {
        case .array(let entries):
            guard !entries.isEmpty else { return path }
            for entry in entries {
                guard entry.isRecord else {
                    appendQueryValue(&params, "value", entry)
                    continue
                }
                let key = (present(entry, "key") ?? present(entry, "Key")
                    ?? present(entry, "name") ?? present(entry, "Name") ?? .string(""))
                    .asDisplayString.jsTrimmed
                appendQueryValue(&params, key, present(entry, "value") ?? present(entry, "Value"))
            }
        case .object(let object):
            guard !object.keys.isEmpty else { return path }
            for pair in object.pairs { appendQueryValue(&params, pair.key, pair.value) }
        default:
            return path
        }
        let text = params.joined(separator: "&")
        guard !text.isEmpty else { return path }
        return "\(path)\(path.contains("?") ? "&" : "?")\(text)"
    }

    // MARK: - Path resolution

    /// `encodePathSuffix(value)` — trim, split on `/`, drop the empty segments (so leading, trailing
    /// and doubled slashes collapse), reject `.` and `..`, then encode each segment. Encoding is
    /// per-segment on purpose: an inner `/` the user typed stays a real separator while spaces and
    /// non-ASCII become `%xx`.
    private static func encodePathSuffix(_ value: String) throws -> String {
        let parts = value.jsTrimmed.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { throw LuckyError("请填写资源 Key / 路径后缀") }
        guard !parts.contains(where: { $0 == "." || $0 == ".." }) else {
            throw LuckyError("路径后缀不能包含 . 或 ..")
        }
        return parts.map { JSCompat.encodeURIComponent($0) }.joined(separator: "/")
    }

    /// `resolveLuckyEndpointPath(call)`. Three steps, in this order:
    ///
    /// 1. every `${variable}` is replaced — all of its occurrences — by the trimmed, encoded value
    ///    from `pathValues[variable] ?? suffix`. A `[String: String]` dictionary reproduces the `??`
    ///    exactly: a *present* empty entry does not fall back to the suffix, it just fails the blank
    ///    check below.
    /// 2. a path that still ends in `/` gets the encoded suffix appended, but only when the suffix is
    ///    not blank — so an endpoint whose variables consumed the suffix does not get it twice.
    /// 3. the query is appended last. The nonce comes later still, in `run`.
    static func resolvePath(_ call: LuckyEndpointCall) throws -> String {
        var path = call.endpoint.path
        for variable in call.endpoint.pathVariables {
            let raw = (call.pathValues[variable] ?? call.suffix).jsTrimmed
            guard !raw.isEmpty else { throw LuckyError("请填写路径参数 \(variable)") }
            path = path.replacingOccurrences(
                of: "${\(variable)}",
                with: JSCompat.encodeURIComponent(raw)
            )
        }
        if path.hasSuffix("/"), !call.suffix.jsTrimmed.isEmpty {
            let encoded = try encodePathSuffix(call.suffix)
            path += encoded
        }
        return appendQuery(path, call.query)
    }

    // MARK: - Private helpers

    /// `getFilename(header)` — RFC 5987 first, then the plain form. Only the first branch is
    /// percent-decoded (with the raw capture as the fallback, matching the original's `try/catch`);
    /// the plain `filename="…"` form is deliberately left encoded, which is why this cannot reuse
    /// `LuckyClient.decodeFilename`.
    private static func filename(from header: String?) -> String? {
        guard let header, !header.isEmpty else { return nil }
        if let marker = header.range(of: "filename*=UTF-8''", options: .caseInsensitive) {
            let captured = String(header[marker.upperBound...].prefix { $0 != ";" })
            if !captured.isEmpty { return JSCompat.decodeURIComponent(captured) }
        }
        // `([^";]+)` needs at least one character, so the regex engine keeps scanning when a
        // `filename=` yields nothing: `filename=; filename="a.txt"` still resolves to the second.
        var cursor = header.startIndex
        while let marker = header.range(
            of: "filename=", options: .caseInsensitive, range: cursor..<header.endIndex
        ) {
            var tail = header[marker.upperBound...]
            if tail.hasPrefix("\"") { tail = tail.dropFirst() }
            let captured = String(tail.prefix { $0 != "\"" && $0 != ";" })
            if !captured.isEmpty { return captured }
            cursor = marker.upperBound
        }
        return nil
    }

    /// `numericRet(value)` — a number is taken as-is (there is **no** finiteness check on this
    /// branch), a non-blank string only when it parses finite, anything else means "absent", and an
    /// absent `ret` on a 2xx counts as success.
    private static func numericRet(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        if case .number(let number) = value { return number }
        if case .string(let text) = value, !text.jsTrimmed.isEmpty {
            let parsed = JSCompat.number(text)
            if parsed.isFinite { return parsed }
        }
        return nil
    }

    /// `getBody(call.body)` plus step 7's content-type rule. A string body is sent verbatim yet
    /// still declared `application/json`; only multipart and binary bodies pick their own type.
    private static func requestBody(_ call: LuckyEndpointCall) -> LuckyBody? {
        if let form = call.form { return .multipart(form) }
        guard let body = call.body, !body.isNull else { return nil }
        switch body {
        case .string(let text): return .text(text)
        case .binary(let data): return .binary(data)
        default: return .json(body)
        }
    }

    // MARK: - Execution

    /// The debugger keeps its own session. `LuckyClient`'s is tuned for the app's 12 s requests,
    /// while this one has to carry a 600 s upload without the configuration-level timeout firing
    /// first; the per-call deadline is enforced by `withDeadline`, exactly as in the original.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 660
        configuration.timeoutIntervalForResource = 660
        return URLSession(configuration: configuration)
    }()

    /// Step 15. An internal timeout is reported as a timeout precisely because the original never
    /// touches the external signal, so cancellation is the only thing that yields `请求已取消`.
    private static func send(
        _ request: URLRequest,
        timeout: TimeInterval
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await withDeadline(timeout) {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw LuckyError("服务器返回了无法识别的响应")
                }
                return (data, http)
            }
        } catch is DeadlineExceeded {
            throw LuckyError("请求超时，请检查服务器连接")
        } catch {
            if error.isCancellation { throw LuckyError("请求已取消") }
            throw error
        }
    }

    /// `/\/(?:download|export|backup|file|[^/]*\.tar\.gz)(?:[/?]|$)/i` — decides whether a response
    /// with no content type should be read as a file instead of parsed as JSON.
    private static func matchesLikelyBinary(_ path: String) -> Bool {
        delimitedSegments(path).contains { segment in
            let head = String(segment.prefix { $0 != "?" })
            if ["download", "export", "backup", "file"].contains(head) { return true }
            return head.hasSuffix(".tar.gz")
        }
    }

    /// `callLuckyEndpoint(call)` — steps 1 to 8. The credentials are re-read from the client on
    /// every attempt, which is what lets the post-refresh replay pick up the new token.
    static func run(_ call: LuckyEndpointCall) async throws -> LuckyEndpointResult {
        guard call.endpoint.methods.contains(call.method) else {
            throw LuckyError("该端点不支持所选请求方法")
        }
        let credentials = await LuckyClient.shared.snapshot
        let base = credentials.baseUrl.jsTrimmed.withoutTrailingSlashes
        guard !base.isEmpty else { throw LuckyError("请输入 Lucky 服务地址") }

        let path = try resolvePath(call)
        let url = try LuckyClient.url(base: base, path: LuckyClient.withNonce(path))
        var request = URLRequest(url: url)
        request.httpMethod = call.method.rawValue
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if !credentials.token.isEmpty {
            request.setValue(credentials.token, forHTTPHeaderField: "Lucky-Admin-Token")
        }
        // `['GET','HEAD'].includes(method)` — GET is the only one of the two the registry offers.
        if call.method != .get, let body = requestBody(call) {
            request.httpBody = body.data
            if let contentType = body.contentType {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }

        let (data, response) = try await send(
            request,
            timeout: matchesLongRunningAction(path) ? 600 : 20
        )
        return try await decode(data, response, path: path, call: call)
    }

    /// Steps 10 and 12 share one recovery path: refresh once, replay with `retryAuth` cleared, and
    /// end the session if either the refresh or the replay fails. A `LuckyAuthError` from that
    /// attempt is rethrown as-is so the original message survives.
    private static func recover(
        _ call: LuckyEndpointCall,
        message: String? = nil
    ) async throws -> LuckyEndpointResult {
        if call.retryAuth {
            do {
                _ = try await LuckyClient.shared.refreshToken()
                var retry = call
                retry.retryAuth = false
                return try await run(retry)
            } catch {
                await LuckySession.shared.end()
                if let authError = error as? LuckyAuthError { throw authError }
            }
        }
        throw LuckyAuthError(message)
    }

    /// Steps 9 to 14 — the response branches, in the original's order. Reordering them changes
    /// which endpoints break: the 401 test has to precede the empty-body test, and the JSON test has
    /// to precede the text test even though a JSON body is also text.
    private static func decode(
        _ data: Data,
        _ response: HTTPURLResponse,
        path: String,
        call: LuckyEndpointCall
    ) async throws -> LuckyEndpointResult {
        // The original never lower-cases the header, so all four content-type tests below are
        // case-sensitive. A server that answered `Application/JSON` would reach the blob branch
        // there, and has to reach it here too.
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        let name = filename(from: response.value(forHTTPHeaderField: "Content-Disposition"))
        let status = response.statusCode
        let ok = (200..<300).contains(status)
        let httpFailure = "请求失败（HTTP \(status)）"

        // Step 10. The original drains the body first; `URLSession` has already done that.
        if status == 401 { return try await recover(call) }

        // Step 11.
        if status == 204 || response.value(forHTTPHeaderField: "Content-Length") == "0" {
            guard ok else { throw LuckyError(httpFailure) }
            return LuckyEndpointResult(
                status: status, contentType: contentType, filename: name, kind: .empty
            )
        }

        // Step 12. A missing content type only means JSON when nothing else suggests a file.
        if contentType.contains("application/json") || contentType.contains("+json")
            || (contentType.isEmpty && name == nil && !matchesLikelyBinary(path)) {
            return try await json(
                data, status: status, contentType: contentType, filename: name,
                ok: ok, httpFailure: httpFailure, call: call
            )
        }

        // Step 13.
        if contentType.hasPrefix("text/") || contentType.contains("xml")
            || contentType.contains("yaml") {
            let raw = String(decoding: data, as: UTF8.self)
            guard ok else { throw LuckyError(raw.isEmpty ? httpFailure : raw) }
            return LuckyEndpointResult(
                status: status, contentType: contentType, filename: name,
                kind: .text, data: .string(raw)
            )
        }

        // Step 14.
        guard ok else {
            // A large body is not worth decoding just to build an error message.
            let detail = data.count <= 65_536 ? String(decoding: data, as: UTF8.self).jsTrimmed : ""
            throw LuckyError(detail.isEmpty ? httpFailure : detail)
        }
        if data.isEmpty {
            return LuckyEndpointResult(
                status: status, contentType: contentType, filename: name, kind: .empty
            )
        }
        return LuckyEndpointResult(
            status: status, contentType: contentType, filename: name,
            kind: .binary, byteLength: data.count, blob: data
        )
    }

    /// The JSON branch of step 12. A parse failure is not fatal on a 2xx: the response is shown as
    /// text, or as nothing when it is blank. A parsed value that is not a record is wrapped, so the
    /// screen always renders an object.
    private static func json(
        _ data: Data,
        status: Int,
        contentType: String,
        filename name: String?,
        ok: Bool,
        httpFailure: String,
        call: LuckyEndpointCall
    ) async throws -> LuckyEndpointResult {
        guard let parsed = JSONParser.tryParse(data) else {
            let raw = String(decoding: data, as: UTF8.self)
            guard ok else { throw LuckyError(raw.isEmpty ? httpFailure : raw) }
            guard !raw.jsTrimmed.isEmpty else {
                return LuckyEndpointResult(
                    status: status, contentType: contentType, filename: name, kind: .empty
                )
            }
            return LuckyEndpointResult(
                status: status, contentType: contentType, filename: name,
                kind: .text, data: .string(raw)
            )
        }
        let envelope = parsed.isRecord ? parsed : .object([("data", parsed)])
        let ret = numericRet(envelope["ret"])
        // `ret === -1` is Lucky's own "token rejected", which arrives with a 200.
        if ret == -1 { return try await recover(call, message: envelope["msg"]?.stringValue) }
        // A **missing** `ret` on a 2xx counts as success — several endpoints answer without one.
        if !ok || (ret != nil && ret != 0) {
            throw LuckyError(envelope["msg"]?.stringValue ?? httpFailure)
        }
        return LuckyEndpointResult(
            status: status, contentType: contentType, filename: name,
            kind: .json, data: envelope
        )
    }
}
