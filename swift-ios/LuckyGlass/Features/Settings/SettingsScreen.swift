import SwiftUI

/// `app/(tabs)/settings.tsx`.
struct SettingsScreen: View {
    @State private var session = LuckySession.shared
    @State private var busy = false
    @State private var confirming = false

    private var scene: LuckySceneDescriptor {
        LuckySceneDescriptor(
            module: .settings,
            title: "当前 Lucky 连接",
            subtitle: session.baseUrl,
            symbol: LuckySymbol.settings,
            tone: .idle,
            health: .unknown
        )
    }

    var body: some View {
        LuckyPage {
            LuckySceneStrip(scene)
            connection
            security
        }
        .luckyTitle("设置", "当前 Lucky 连接")
        .luckyScene(scene)
        .safeAreaBar(edge: .bottom) { commandDeck }
        // `Alert.alert('退出登录', '确定结束当前 Lucky 会话吗？', …)` — a decision, so it stays an
        // alert rather than becoming a toast.
        .alert("退出登录", isPresented: $confirming) {
            Button("取消", role: .cancel) {}
            Button("退出", role: .destructive) { leave() }
        } message: {
            Text("确定结束当前 Lucky 会话吗？")
        }
    }

    private var connection: some View {
        LuckyDataRail(title: "会话", subtitle: "已保存", tone: .idle) {
            VStack(spacing: 0) {
                HStack(spacing: LuckyTheme.Space.m) {
                    LuckyIconTile(symbol: "server.rack", size: 46, glyph: 22)
                    VStack(alignment: .leading, spacing: LuckyTheme.Space.xs) {
                        Text(session.account.isEmpty ? "管理员" : session.account)
                            .font(LuckyTheme.Text.bodyMedium)
                            .foregroundStyle(LuckyTheme.textPrimary)
                        Text(session.baseUrl)
                            .font(LuckyTheme.Text.caption)
                            .foregroundStyle(LuckyTheme.textSecondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: LuckyTheme.Space.s)
                }
                .padding(LuckyTheme.Space.m)
                LuckyHairline()
                VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
                    note("person", "账号已保存")
                    note("key", "凭据由设备安全存储保护")
                }
                .padding(LuckyTheme.Space.m)
            }
        }
    }

    private func note(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 9) {
            LuckyIconTile(symbol: symbol, size: 28, glyph: 14, tone: .idle)
            Text(text)
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textSecondary)
        }
    }

    private var security: some View {
        LuckyDataRail(title: "连接安全", subtitle: "设备侧会话保护", tone: .ok) {
            HStack(alignment: .top, spacing: 9) {
                LuckyIconTile(symbol: "checkmark.shield", tone: .ok)
                Text("公网访问时应在 Lucky 前配置 HTTPS 与访问控制。管理 Token 不会写入 Web 的持久存储。")
                    .font(LuckyTheme.Text.body)
                    .foregroundStyle(LuckyTheme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(LuckyTheme.Space.m)
        }
    }

    private var commandDeck: some View {
        LuckyCommandDeck(
            context: LuckyCommandContext(
                title: busy ? "正在退出" : "当前会话",
                detail: session.account.isEmpty ? "管理员" : session.account,
                symbol: LuckySymbol.settings,
                tone: busy ? .warning : .ok
            )
        ) {
            logout
        }
    }

    private var logout: some View {
        LuckyPillButton(
            title: busy ? "正在退出" : "退出登录",
            symbol: "rectangle.portrait.and.arrow.right",
            tone: .danger,
            loading: busy,
            fills: false
        ) {
            guard !busy else { return }
            confirming = true
        }
    }

    /// `leave()`: tell the server, then drop the local session whatever the server said — a failed
    /// `/api/logout` must not trap the user in a session they asked to end. The root view swaps to
    /// the login screen as soon as the token clears, which is `router.replace('/login')`.
    private func leave() {
        guard !busy else { return }
        busy = true
        Task {
            do { _ = try await LuckyService.logout() } catch {}
            await session.end()
            busy = false
        }
    }
}
