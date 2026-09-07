import SwiftUI

// MARK: - 单个动作

/// One row of §19's drawer: an icon, a label, and the thing they do.
///
/// The label is the identity because no drawer repeats one, and because a conditional entry —
/// §19.5's 暂停容器 — must not shift the rows below it when it appears.
struct DockerActionItem: Identifiable {
    var label: String
    var symbol: String
    var tint: Color
    var action: () -> Void

    var id: String { label }

    init(_ label: String, _ symbol: String, _ tint: Color, _ action: @escaping () -> Void) {
        self.label = label
        self.symbol = symbol
        self.tint = tint
        self.action = action
    }
}

// MARK: - 动作抽屉

/// §19's `DockerActionSheet` — the drawer behind 镜像高级工具, 镜像操作 and 容器操作.
///
/// The original is a bottom-anchored `Modal` over a dimmed backdrop with its own handle and header;
/// a `.sheet` already draws both, so the plate's `maxWidth: 720` / `maxHeight: "84%"` become
/// presentation detents and the header becomes the real navigation bar.
///
/// Chrome is hand-built rather than `ServiceSheet` because the drawer has no primary verb, and
/// `luckyActionBar` would draw an empty glass bar for one — the same reason `WebToolsSheet` builds
/// its own.
struct DockerActionSheet: View {
    var title: String
    var subtitle: String = ""
    var close: () -> Void
    var items: [DockerActionItem]

    var body: some View {
        NavigationStack {
            ZStack {
                LuckyBackdrop()
                ScrollView {
                    // `flexBasis: 145` with `flexGrow: 1` and `gap: 7` — a wrapping row of equal
                    // buttons, two to a line on a phone, which is what the adaptive grid draws.
                    LuckyTileGrid(minimum: 145, spacing: 7) {
                        ForEach(items) { item in
                            DockerActionRow(item: item, close: close)
                        }
                    }
                    .padding(.horizontal, LuckyTheme.Space.gutter)
                    .padding(.top, LuckyTheme.Space.s)
                    .padding(.bottom, LuckyTheme.Space.xl)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollIndicators(.hidden)
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .presentationDetents(detents)
    }

    /// `maxHeight: "84%"` on a plate that otherwise sizes itself to its rows. A four-entry drawer
    /// opens at half height and 容器操作's eighteen fill the sheet, which is as close as a fixed set
    /// of detents gets to that.
    private var detents: Set<PresentationDetent> {
        items.count > 6 ? [.large] : [.medium, .large]
    }
}

// MARK: - 抽屉里的一行

private struct DockerActionRow: View {
    var item: DockerActionItem
    var close: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        Button {
            // `onPress={() => { close(); action(); }}` — the drawer goes away first, so a form or
            // an alert the action opens is never presented behind it.
            close()
            item.action()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(item.label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The label takes the icon's colour too, which is what makes 删除容器 read as a warning
            // at a glance rather than only on inspection.
            .foregroundStyle(item.tint)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(shape.fill(LuckyTheme.surfaceRaised))
            .overlay(shape.strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}
