import Foundation

/// Port of `src/lib/lucky-fetch.ts`.
///
/// Kept as an actor because the original module holds two pieces of shared mutable
/// state — the session snapshot it reads on every call and the single-flight
/// `tokenRefreshPromise` — and because response decoding should stay off the main
/// actor: Docker payloads can be large.
actor LuckyClient {
    static let shared = LuckyClient()

    private var credentials = LuckyCredentials()
    private var refreshTask: Task<String, Error>?
    /// Not `private` only because `signIn` lives in `LuckyClient+Login.swift`, and a `private`
    /// member is unreachable from an extension in another file.
    let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        // Deadlines are enforced per request by `withDeadline`; these only stop a
        // dead connection from hanging a task forever.
        configuration.timeoutIntervalForRequest = LuckyClientConstants.transferTimeout + 30
        configuration.timeoutIntervalForResource = LuckyClientConstants.transferTimeout + 60
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    func apply(_ credentials: LuckyCredentials) { self.credentials = credentials }

    var snapshot: LuckyCredentials { credentials }

    // MARK: - Cache buster

    /// `createLuckyRequestNonce()` — the millisecond clock minus its last digit, with a
    /// digit-sum checksum appended. Lucky's web console does the same, and some builds
    /// reject requests without it.
    static func nonce(millis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> String {
        var timestamp = String(millis)
        if !timestamp.isEmpty { timestamp.removeLast() }
        let checksum = timestamp.reduce(0) { $0 + ($1.wholeNumberValue ?? 0) } % 8
        return "\(timestamp)\(checksum)"
    }

    /// `withLuckyRequestNonce(path)`
    static func withNonce(_ path: String, millis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> String {
        let separator = path.contains("?") ? "&" : "?"
        return "\(path)\(separator)_=\(nonce(millis: millis))"
    }

    static func url(base: String, path: String) throws -> URL {
        let root = base.jsTrimmed.withoutTrailingSlashes
        let suffix = path.hasPrefix("/") ? path : "/\(path)"
        let combined = root + suffix
        if let url = URL(string: combined) { return url }
        // `fetch` tolerates a few characters that `URL(string:)` rejects.
        let escaped = combined.replacingOccurrences(of: " ", with: "%20")
        guard let url = URL(string: escaped) else { throw LuckyError("服务地址无效，请检查地址格式") }
        return url
    }

    // MARK: - Request

    @discardableResult
    func fetch(_ request: LuckyRequest) async throws -> JSONValue {
        let base = (request.baseUrl ?? credentials.baseUrl).jsTrimmed.withoutTrailingSlashes
        guard !base.isEmpty else { throw LuckyError("请输入 Lucky 服务地址") }
        let token = request.token ?? credentials.token

        var urlRequest = URLRequest(url: try Self.url(base: base, path: Self.withNonce(request.path)))
        urlRequest.httpMethod = request.method
        for (field, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        if urlRequest.value(forHTTPHeaderField: "Accept") == nil {
            urlRequest.setValue(request.responseKind == .blob
                ? "application/octet-stream, application/json;q=0.8, text/plain;q=0.6"
                : "application/json", forHTTPHeaderField: "Accept")
        }
        if let body = request.body {
            urlRequest.httpBody = body.data
            if let contentType = body.contentType, urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }
        if !token.isEmpty { urlRequest.setValue(token, forHTTPHeaderField: "Lucky-Admin-Token") }

        let (data, response) = try await send(urlRequest, timeout: request.timeout)
        let payload = try Self.envelope(data: data, response: response, kind: request.responseKind)
        return try await resolve(payload: payload, request: request, response: response, token: token)
    }

    /// Convenience matching the many `luckyFetch('/api/...')` call sites.
    @discardableResult
    func fetch(_ path: String, method: String = "GET", body: LuckyBody? = nil) async throws -> JSONValue {
        try await fetch(LuckyRequest(path, method: method, body: body))
    }

    private func send(_ urlRequest: URLRequest, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await withDeadline(timeout) { [session] in
                let (data, response) = try await session.data(for: urlRequest)
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

    // MARK: - Auth recovery

    private func resolve(
        payload: JSONValue,
        request: LuckyRequest,
        response: HTTPURLResponse,
        token: String
    ) async throws -> JSONValue {
        let ret = payload.ret
        if response.statusCode == 401 || ret == -1 {
            if request.retryAuth {
                do {
                    // Another in-flight request may already have refreshed the token.
                    let latest: String
                    if !token.isEmpty, !credentials.token.isEmpty, token != credentials.token {
                        latest = credentials.token
                    } else {
                        latest = try await refreshToken()
                    }
                    var retry = request
                    retry.token = latest
                    retry.retryAuth = false
                    return try await fetch(retry)
                } catch {
                    await LuckySession.shared.end()
                    if let authError = error as? LuckyAuthError { throw authError }
                }
            }
            throw LuckyAuthError(payload.msg)
        }
        let ok = (200..<300).contains(response.statusCode)
        if !ok || ret != 0 {
            let message = payload.msg ?? ""
            throw LuckyError(message.isEmpty ? "请求失败（HTTP \(response.statusCode)）" : message)
        }
        return payload
    }

    /// `refreshLuckyToken()` — single flight, so a burst of 401s triggers one login.
    func refreshToken() async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        let pending = credentials
        let urlSession = session
        let task = Task<String, Error> {
            try await Self.login(
                baseUrl: pending.baseUrl,
                account: pending.account,
                password: pending.password,
                twoFACode: "",
                session: urlSession,
                asRefresh: true
            )
        }
        refreshTask = task
        defer { refreshTask = nil }
        let token = try await task.value
        await LuckySession.shared.saveToken(token)
        return token
    }
}
