import SwiftUI

/// §14 — CGI. The module's CGI instances, each a program the reverse proxy can hand a request to.
///
/// Structurally §13's twin with two differences: the glyph is cyan rather than accent, and the row
/// fronts an enable switch — a CGI instance is a service, where a group is only a label.
struct WebCgiView: View {
    var items: [LuckyListItem]
    var loading: Bool
    var busy: Bool
    var refresh: @Sendable () async -> Void
    var setEnabled: (String, Bool) -> Void
    var edit: (LuckyListItem, String) -> Void
    var remove: (String, String) -> Void

    var body: some View {
        WebPaneScroll(refresh: refresh) {
            LuckySectionHeader(title: WebPane.cgi.title, symbol: WebPane.cgi.symbol) {
                LuckyChip(text: "\(items.count) 项", tone: .idle)
            }
            if loading {
                LuckyLoadingView(text: "正在读取 CGI 实例")
            } else if items.isEmpty {
                LuckyEmptyState(symbol: WebPane.cgi.symbol, title: "暂无 CGI 实例")
                    .padding(.vertical, LuckyTheme.Space.xl)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    WebCgiCard(item: item, index: index, busy: busy, setEnabled: setEnabled,
                               edit: edit, remove: remove)
                }
            }
        }
    }
}

// MARK: - CGI 卡片

private struct WebCgiCard: View {
    var item: LuckyListItem
    var index: Int
    var busy: Bool
    var setEnabled: (String, Bool) -> Void
    var edit: (LuckyListItem, String) -> Void
    var remove: (String, String) -> Void

    private var key: String { WebRecord.key(item, index) }
    private var name: String { WebRecord.pick(item, ["Name"], key) }
    private var enabled: Bool { WebRecord.isEnabled(item) }

    /// `` `${CGIType} · ${Network} · ${Address}` `` — each with `pick`'s empty-string fallback, so
    /// a field the module left out renders as nothing between the middots instead of as `--`.
    private var summary: String {
        let type = WebRecord.pick(item, ["CGIType"])
        let network = WebRecord.pick(item, ["Network"])
        let address = WebRecord.pick(item, ["Address"])
        return "\(type) · \(network) · \(address)"
    }

    var body: some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            header
            verbs
        }
    }
}

extension WebCgiCard {
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: WebPane.cgi.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LuckyTheme.info)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(LuckyTheme.Text.cardTitle)
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .lineLimit(1)
                Text(summary)
                    .font(LuckyTheme.Text.codeSmall)
                    .foregroundStyle(LuckyTheme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            WebEnableSwitch(isOn: enabled, disabled: busy, name: "启用 CGI 实例") { on in
                setEnabled(key, on)
            }
            .fixedSize()
        }
    }

    private var verbs: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            WebIconButton(symbol: "pencil", name: "编辑", text: nil, tint: LuckyTheme.accent) {
                edit(item, key)
            }
            WebIconButton(symbol: LuckySymbol.delete, name: "删除", text: nil,
                          tint: LuckyTheme.danger, disabled: busy) {
                remove(key, name)
            }
        }
    }
}
