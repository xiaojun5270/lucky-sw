import Foundation

extension LuckyClient {
    /// `POST /api/login`, shared by the login screen (`loginToLucky`) and the silent
    /// refresh (`refreshLuckyToken`). The request is identical in both paths — only the
    /// error copy and the error type differ — so they must not drift apart.
    ///
    /// `asRefresh` selects the refresh behaviour: every failure becomes a
    /// `LuckyAuthError`, which is the signal the caller uses to end the session.
    static func login(
        baseUrl: String,
        account: String,
        password: String,
        twoFACode: String,
        session: URLSession,
        asRefresh: Bool
    ) async throws -> String {
        // The refresh path has no UI to validate against, so it checks the stored
        // credentials itself before spending a request.
        if asRefresh, baseUrl.isEmpty || account.isEmpty || password.isEmpty {
            throw LuckyAuthError()
        }

        do {
            return try await withDeadline(LuckyClientConstants.defaultTimeout) {
                try await performLogin(
                    baseUrl: baseUrl,
                    account: account,
                    password: password,
                    twoFACode: twoFACode,
                    session: session,
                    asRefresh: asRefresh
                )
            }
        } catch let error as LuckyAuthError {
            throw error
        } catch {
            if asRefresh {
                if error is DeadlineExceeded { throw LuckyAuthError("重新登录超时，请检查服务器连接") }
                if error.isCancellation { throw LuckyAuthError("重新登录请求已取消") }
                throw LuckyAuthError("重新登录失败，请检查服务器连接")
            }
            if error is DeadlineExceeded { throw LuckyError("登录超时，请检查服务器地址") }
            // A transport failure surfaces verbatim, as it does in the original.
            throw error
        }
    }

    private static func performLogin(
        baseUrl: String,
        account: String,
        password: String,
        twoFACode: String,
        session: URLSession,
        asRefresh: Bool
    ) async throws -> String {
        var request = URLRequest(url: try url(base: baseUrl, path: withNonce("/api/login")))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Lucky expects these four fields in this order; `TwoFA` is always empty and the
        // code is only ever sent from the login screen.
        request.httpBody = JSONSerializer.data(.object([
            ("Account", .string(account.jsTrimmed)),
            ("Password", .string(password)),
            ("TwoFA", .string("")),
            ("TwoFACode", .string(twoFACode.jsTrimmed)),
        ]))

        let (data, rawResponse) = try await session.data(for: request)
        let response = rawResponse as? HTTPURLResponse
        let status = response?.statusCode ?? 0
        let ok = (200..<300).contains(status)

        // Only an unparseable body takes this branch: a well-formed body that happens not
        // to be an object falls through and fails the `ret` check below, as it does in JS.
        guard let payload = JSONParser.tryParse(data) else {
            throw failure(
                ok ? (asRefresh ? "重新登录失败：服务器返回了无法识别的数据" : "登录失败：服务器返回了无法识别的数据")
                   : (asRefresh ? "重新登录失败（HTTP \(status)）" : "登录失败（HTTP \(status)）"),
                asRefresh: asRefresh
            )
        }

        if !ok || payload.retValue != 0 {
            if asRefresh { throw LuckyAuthError(payload.msg) }
            throw LuckyError(payload.msg ?? "登录失败")
        }

        guard let token = token(in: payload, header: response?.value(forHTTPHeaderField: "Lucky-Admin-Token")) else {
            throw failure(
                asRefresh ? "重新登录成功但未返回 Token" : "登录成功但响应中没有 Token，请在联调环境确认登录响应字段",
                asRefresh: asRefresh
            )
        }
        return token
    }

    /// Lucky has shipped the admin token under several names across versions, and some
    /// builds only return it as a response header. The candidate order is the original's.
    private static func token(in payload: JSONValue, header: String?) -> String? {
        // `record(payload.data)` — a non-object `data` yields `{}`, whose fields are all
        // absent, so the nested lookups below simply miss.
        let nested = payload["data"] ?? .null
        var candidates: [JSONValue?] = [
            payload["token"], payload["Token"], payload["AdminToken"], payload["LuckyAdminToken"],
        ]
        if let data = payload["data"], data.isString { candidates.append(data) }
        candidates.append(contentsOf: [
            nested["token"], nested["Token"], nested["AdminToken"], nested["LuckyAdminToken"],
        ])
        for candidate in candidates {
            if let text = candidate?.stringValue, !text.jsTrimmed.isEmpty { return text }
        }
        if let header, !header.jsTrimmed.isEmpty { return header }
        return nil
    }

    private static func failure(_ message: String, asRefresh: Bool) -> Error {
        asRefresh ? LuckyAuthError(message) : LuckyError(message)
    }

    /// `loginToLucky(input)` — the interactive path. An instance method so the login screen
    /// reuses the actor's `URLSession` (ephemeral, no cookies, no cache) instead of the
    /// shared one, exactly as every other request does.
    func signIn(_ input: LuckyLoginInput) async throws -> String {
        try await Self.login(
            baseUrl: input.baseUrl.jsTrimmed.withoutTrailingSlashes,
            account: input.account.jsTrimmed,
            password: input.password,
            twoFACode: input.twoFACode.jsTrimmed,
            session: session,
            asRefresh: false
        )
    }
}
