import Foundation
import Observation

/// Credentials snapshot handed to the networking actor.
struct LuckyCredentials: Sendable, Equatable {
    var baseUrl: String = ""
    var account: String = ""
    var password: String = ""
    var token: String = ""
}

/// Replacement for the valtio `luckySessionState` proxy plus its SecureStore helpers.
///
/// The account password is persisted deliberately: Lucky issues short-lived admin
/// tokens and the original app re-logs in silently when one expires, which is the
/// behaviour the whole error-handling path is built around.
@MainActor
@Observable
final class LuckySession {
    static let shared = LuckySession()

    private static let storageKey = "lucky_app_session"

    var baseUrl: String = ""
    var account: String = ""
    var password: String = ""
    var token: String = ""
    var hydrated: Bool = false

    private init() {}

    /// `isLuckyAuthenticated()`
    var isAuthenticated: Bool { !baseUrl.isEmpty && !token.isEmpty }

    var credentials: LuckyCredentials {
        LuckyCredentials(baseUrl: baseUrl, account: account, password: password, token: token)
    }

    /// `hydrateLuckySession()`
    func hydrate() async {
        if let raw = Keychain.read(Self.storageKey) {
            if let saved = JSONParser.tryParse(raw) {
                baseUrl = (saved["baseUrl"]?.stringValue ?? "").jsTrimmed.withoutTrailingSlashes
                account = saved["account"]?.stringValue ?? ""
                password = saved["password"]?.stringValue ?? ""
                token = saved["token"]?.stringValue ?? ""
            } else {
                // Unreadable payload: drop it rather than keep failing to parse.
                Keychain.delete(Self.storageKey)
            }
        }
        hydrated = true
        await syncClient()
    }

    /// `saveLuckySession(session)`
    func save(baseUrl: String, account: String, password: String, token: String) async {
        self.baseUrl = baseUrl.jsTrimmed.withoutTrailingSlashes
        self.account = account
        self.password = password
        self.token = token
        persist()
        await syncClient()
    }

    /// `saveLuckyToken(token)`
    func saveToken(_ token: String) async {
        self.token = token
        persist()
        await syncClient()
    }

    /// `endLuckySession()`
    func end() async {
        token = ""
        persist()
        await syncClient()
    }

    private func persist() {
        let payload = JSONObject([
            ("baseUrl", .string(baseUrl)),
            ("account", .string(account)),
            ("password", .string(password)),
            ("token", .string(token)),
        ])
        Keychain.write(Self.storageKey, value: JSONSerializer.stringify(.object(payload)))
    }

    private func syncClient() async {
        await LuckyClient.shared.apply(credentials)
    }
}
