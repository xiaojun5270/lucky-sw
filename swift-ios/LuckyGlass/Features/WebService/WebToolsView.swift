import SwiftUI

/// §17 — 工具. The two calls that answer something the other five panes have no room for: the rules
/// list without its sub-rules, and the module's own tip payload.
///
/// Whatever they answer lands in the drawer at the bottom, which is also where a 刷新目录缓存, a
/// 轻面板配置模板 request and every folder-update call put their result.
struct WebToolsView: View {
    var tips: JSONValue?
    /// `output` — `nil` is the original's falsy `""`: nothing has been requested yet.
    var output: JSONValue?
    var loading: Bool
    var busy: Bool
    var refresh: @Sendable () async -> Void
    var lite: @Sendable () async -> Void
    var showTips: () -> Void
    var markTip: () -> Void
    var template: () -> Void

    var body: some View {
        WebPaneScroll(refresh: refresh) {
            LuckySectionHeader(title: WebPane.tools.title, symbol: WebPane.tools.symbol)
            rulesPanel
            templatePanel
            if let output {
                LuckyCard {
                    StructuredDataView(value: output)
                }
            }
        }
    }
}

extension WebToolsView {
    private var rulesPanel: some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            Text("规则轻量列表与提示")
                .font(LuckyTheme.Text.bodyMedium)
                .foregroundStyle(LuckyTheme.textPrimary)
            HStack(spacing: LuckyTheme.Space.s) {
                ServiceActionButton(title: "读取轻量列表", symbol: "list.bullet.rectangle",
                                    tone: .brand, fill: .tinted, height: 40, radius: 10) {
                    Task { await lite() }
                }
                // The original leaves this live and lets it answer `{}` while the tip read is still
                // in flight; disabling it instead keeps the drawer from opening on an empty record.
                ServiceActionButton(title: "查看提示信息", symbol: "info.circle",
                                    tone: .brand, fill: .tinted, height: 40, radius: 10,
                                    disabled: loading, action: showTips)
            }
            if hasTipVersion {
                // `typeof tips.data?.version === "string"` — no version, no button, and a numeric
                // one would not be sent either.
                ServiceActionButton(title: "标记当前提示为已读", symbol: "checkmark.circle",
                                    tone: .brand, fill: .plain, height: 38, radius: 10,
                                    disabled: busy, action: markTip)
            }
        }
    }

    private var templatePanel: some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            Text("轻面板配置模板")
                .font(LuckyTheme.Text.bodyMedium)
                .foregroundStyle(LuckyTheme.textPrimary)
            ServiceActionButton(title: "填写请求参数", symbol: LuckySymbol.edit, tone: .brand,
                                fill: .solid, height: 40, radius: 10, action: template)
        }
    }

    private var hasTipVersion: Bool {
        if case .string = tips?["version"] { return true }
        return false
    }
}
