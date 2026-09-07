import SwiftUI

/// The scroll shell all six panes of `WebServiceScreen` are built in.
///
/// The original mounts a `FlatList` for 规则 / 分组 / CGI / 日志 and puts 设置 and 工具 inside the
/// page's own `ScrollView` — a split forced by the fact that a `FlatList` cannot virtualise when it
/// is nested in a `ScrollView`. `LazyVStack` has no such conflict, so all six share one container.
/// The visible consequence is that the `SectionHeader` scrolls with the rows where the `FlatList`'s
/// stayed put; the pane picker above it is pinned instead, which keeps the six views one tap apart.
struct WebPaneScroll<Content: View>: View {
    var refresh: @Sendable () async -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LuckyTheme.Space.m, content: content)
                .padding(.horizontal, LuckyTheme.Space.gutter)
                .padding(.top, LuckyTheme.Space.xs)
                .padding(.bottom, LuckyTheme.Space.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollIndicators(.hidden)
        .refreshable { await refresh() }
    }
}

/// §7.1 `IconButton` — the compact verb chip that fills the action row of every list pane.
///
/// `ServiceActionButton` cannot stand in for it: these rows carry a *different* accessibility label
/// from their visible text (`复制完整网址` reads as 复制网址, `子规则排序` as 排序), and dropping
/// that distinction would leave the two 复制 buttons of an expanded rule indistinguishable to
/// VoiceOver. The surface is always the neutral raised one, exactly as in the original — only the
/// glyph and label colour carry meaning.
struct WebIconButton: View {
    var symbol: String
    /// `label` — what VoiceOver reads.
    var name: String
    /// `visibleLabel` — what is drawn. `nil` covers the rows where the original passes one string
    /// for both.
    var text: String?
    var tint: Color = LuckyTheme.textPrimary
    var disabled: Bool = false
    var action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(text ?? name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, LuckyTheme.Space.s)
            .frame(minWidth: 58, minHeight: 36)
            .background(shape.fill(LuckyTheme.surfaceRaised))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(name)
    }
}

/// The switch that fronts a rule, a sub-rule or a CGI instance. `Toggle` with no label of its own,
/// so the row decides what sits beside it.
struct WebEnableSwitch: View {
    var isOn: Bool
    var disabled: Bool
    var name: String
    var change: (Bool) -> Void

    var body: some View {
        Toggle("", isOn: Binding(get: { isOn }, set: change))
            .labelsHidden()
            .disabled(disabled)
            .accessibilityLabel(name)
    }
}
