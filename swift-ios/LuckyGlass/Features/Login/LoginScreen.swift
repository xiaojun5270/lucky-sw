import SwiftUI

/// `app/login.tsx`.
///
/// The zod schema becomes `validate()` below — same four rules, same Chinese messages, same
/// behaviour of validating every field before the first request goes out. The one visual change is
/// that the 登录 button moved from inside the card to a glass bar in the bottom safe area: the card
/// scrolls, and glass must not.
struct LoginScreen: View {
    private enum Field: Hashable { case baseUrl, account, password, twoFACode }

    @State private var input = LuckyLoginInput()
    @State private var errors: [Field: String] = [:]
    @State private var failure = ""
    @State private var submitting = false
    @State private var seeded = false

    private var scene: LuckySceneDescriptor {
        let health: LuckyHealthState
        if !failure.isEmpty { health = .critical }
        else if submitting { health = .attention }
        else { health = .unknown }
        return LuckySceneDescriptor(
            module: .login,
            title: "Lucky",
            subtitle: "管理控制台",
            symbol: LuckySymbol.login,
            tone: .brand,
            health: health
        )
    }

    var body: some View {
        ZStack {
            LuckyBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: LuckyTheme.Space.xl) {
                    header
                    card
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, LuckyTheme.Space.xl)
                .padding(.vertical, LuckyTheme.Space.xxl)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            // `contentContainerStyle={{ flexGrow: 1, justifyContent: 'center' }}`.
            .scrollClipDisabled()
            .defaultScrollAnchor(.center)
        }
        .luckyScene(scene)
        .safeAreaBar(edge: .bottom) { commandDeck }
        .task {
            // `defaultValues: { baseUrl: luckySessionState.baseUrl, … }` — read once, so typing is
            // never overwritten by a later store update.
            guard !seeded else { return }
            seeded = true
            let session = LuckySession.shared
            input.baseUrl = session.baseUrl
            input.account = session.account
            input.password = session.password
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.l) {
            LuckyMark(size: 72)
            LuckySceneStrip(scene)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var card: some View {
        LuckyDataRail(title: "会话凭据", subtitle: "Lucky 管理端", tone: .brand) {
            VStack(alignment: .leading, spacing: LuckyTheme.Space.l) {
                field(.baseUrl, "服务地址", "http://192.168.1.2:16601", "link",
                      keyboard: .URL, contentType: .URL)
                field(.account, "管理员账号", "admin", "person",
                      contentType: .username)
                field(.password, "密码", "输入密码", "lock",
                      contentType: .password, secure: true)
                field(.twoFACode, "2FA 验证码（可选）", "6位动态验证码", "key",
                      keyboard: .numberPad, contentType: .oneTimeCode)
                if !failure.isEmpty {
                    Text(failure)
                        .font(LuckyTheme.Text.body)
                        .foregroundStyle(LuckyTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(LuckyTheme.Space.m)
                        .background(ConcentricRectangle().fill(LuckyTheme.dangerSoft))
                }
            }
            .padding(LuckyTheme.Space.l)
        }
    }

    private var commandDeck: some View {
        LuckyCommandDeck(context: nil) {
            LuckyPillButton(
                title: submitting ? "正在登录" : "登录",
                symbol: "arrow.right.to.line",
                prominent: true,
                loading: submitting,
                action: submit
            )
        }
    }

    @ViewBuilder
    private func field(
        _ field: Field,
        _ label: String,
        _ placeholder: String,
        _ symbol: String,
        keyboard: UIKeyboardType = .default,
        contentType: UITextContentType? = nil,
        secure: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.xs) {
            LuckyTextField(
                label: label,
                text: binding(field),
                placeholder: placeholder,
                symbol: symbol,
                secure: secure,
                keyboard: keyboard,
                contentType: contentType,
                submitLabel: field == .twoFACode ? .go : .next,
                tone: errors[field] == nil ? nil : .danger,
                onSubmit: field == .twoFACode ? submit : nil
            )
            if let message = errors[field] {
                Text(message)
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.danger)
            }
        }
    }

    private func binding(_ field: Field) -> Binding<String> {
        switch field {
        case .baseUrl: $input.baseUrl
        case .account: $input.account
        case .password: $input.password
        // `onChangeText={(value) => field.onChange(value.replace(/\D/g, '').slice(0, 6))}`.
        case .twoFACode: Binding(
            get: { input.twoFACode },
            set: { input.twoFACode = String($0.filter(\.isASCIIDigit).prefix(6)) }
        )
        }
    }

    /// The zod schema. `z.string().url()` defers to the WHATWG URL parser, which requires a scheme
    /// and a non-empty authority — `URL(string:)` alone accepts `"admin"` as a relative reference,
    /// so the shape is checked explicitly.
    private func validate() -> [Field: String] {
        var found: [Field: String] = [:]
        if !isAbsoluteURL(input.baseUrl) {
            found[.baseUrl] = "请输入完整地址，例如 http://192.168.1.2:16601"
        }
        if input.account.isEmpty { found[.account] = "请输入管理员账号" }
        if input.password.isEmpty { found[.password] = "请输入密码" }
        if !input.twoFACode.isEmpty,
           !(input.twoFACode.count == 6 && input.twoFACode.allSatisfy(\.isASCIIDigit)) {
            found[.twoFACode] = "请输入6位数字验证码"
        }
        return found
    }

    private func isAbsoluteURL(_ text: String) -> Bool {
        guard let separator = text.range(of: "://") else { return false }
        let scheme = text[text.startIndex..<separator.lowerBound]
        guard let first = scheme.first, first.isLetter else { return false }
        let validScheme = scheme.allSatisfy { $0.isLetter || $0.isNumber || "+-.".contains($0) }
        let authority = text[separator.upperBound...].prefix { !"/?#".contains($0) }
        return validScheme && !authority.isEmpty
    }

    private func submit() {
        guard !submitting else { return }
        failure = ""
        let found = validate()
        errors = found
        guard found.isEmpty else { return }
        submitting = true
        Task {
            defer { submitting = false }
            do {
                let token = try await LuckyClient.shared.signIn(input)
                await LuckySession.shared.save(
                    baseUrl: input.baseUrl,
                    account: input.account,
                    password: input.password,
                    token: token
                )
                // `queryClient.clear()` then `router.replace('/monitor')`: there is no cache to
                // clear here, and the root view swaps to the tabs as soon as the token lands.
            } catch {
                failure = error.luckyMessage("登录失败")
            }
        }
    }
}

extension Character {
    /// `/\D/` and `/^\d{6}$/` match ASCII digits only — `isNumber` would also accept 一 and ٤.
    var isASCIIDigit: Bool { isASCII && isNumber }
}
