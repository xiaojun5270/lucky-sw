import SwiftUI

/// §15 — 设置. The module's own configuration, which has no schema this screen knows.
///
/// So the pane does not try to render it: it counts the fields and offers one button that opens the
/// whole record in the structured editor. The original mounts this pane inside the page's own
/// `ScrollView` rather than a `FlatList`; `WebPaneScroll` serves both.
struct WebSettingsView: View {
    var value: JSONValue?
    var loading: Bool
    var refresh: @Sendable () async -> Void
    var edit: () -> Void

    var body: some View {
        WebPaneScroll(refresh: refresh) {
            LuckySectionHeader(title: WebPane.settings.title, symbol: WebPane.settings.symbol)
            if loading {
                LuckyLoadingView(text: "正在读取模块设置")
            } else if let value {
                card(value)
            } else {
                LuckyEmptyState(symbol: WebPane.settings.symbol, title: "暂无模块设置")
                    .padding(.vertical, LuckyTheme.Space.xl)
            }
        }
    }
}

extension WebSettingsView {
    private func card(_ value: JSONValue) -> some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            // Rendered as three chunks in the original — `当前设置包含 `, the count, ` 个字段。` —
            // which is one sentence once it reaches the screen.
            Text("当前设置包含 \(fieldCount(value)) 个字段。")
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            ServiceActionButton(title: "编辑全部设置", symbol: "doc.badge.gearshape",
                                tone: .brand, fill: .solid, height: 42, radius: 10,
                                action: edit)
        }
    }

    /// `Object.keys(settings.data).filter(key => !["ret","msg"].includes(key)).length` — the two
    /// envelope keys every Lucky response carries are not settings.
    ///
    /// `getWebServiceSettings` answers a record, so the other branch is unreachable; `Object.keys`
    /// of anything that is not one would count array indices or string positions instead.
    private func fieldCount(_ value: JSONValue) -> Int {
        guard let record = value.objectValue else { return value.arrayValue?.count ?? 0 }
        return record.keys.filter { $0 != "ret" && $0 != "msg" }.count
    }
}
