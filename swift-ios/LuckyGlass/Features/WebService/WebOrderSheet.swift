import SwiftUI

/// §7.5 `GroupOrderEditor` — 子规则排序. Reorders a rule's sub-rules by key.
///
/// The list is local state seeded from the rule's current keys (`initialKeys.slice()`); nothing is
/// sent until 保存排序, and the module's own order is untouched until then. Every row is a key the
/// rule already carries, so there is no add or remove — only the two arrows.
struct WebOrderSheet: View {
    var request: WebOrderRequest
    var busy: Bool
    var close: () -> Void
    var save: ([String]) -> Void

    @State private var keys: [String]

    init(request: WebOrderRequest, busy: Bool, close: @escaping () -> Void,
         save: @escaping ([String]) -> Void) {
        self.request = request
        self.busy = busy
        self.close = close
        self.save = save
        _keys = State(initialValue: request.keys)
    }

    /// `groupName || groupKey` — an unnamed group is recognised by its key.
    private var subtitle: String {
        request.name.isEmpty ? request.key : request.name
    }

    var body: some View {
        ServiceSheet(title: "子规则排序", subtitle: subtitle,
                     close: { if !busy { close() } }) {
            LuckyPillButton(title: busy ? "保存中..." : "保存排序",
                            symbol: "square.and.arrow.down", prominent: true, loading: busy) {
                save(keys)
            }
        } content: {
            LuckyCard(spacing: LuckyTheme.Space.m) {
                Text("调整顺序后保存，应用顺序与此列表一致。")
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                rows
            }
        }
    }
}

extension WebOrderSheet {
    /// `borderTopWidth: index ? 1 : 0` with `paddingTop 10` — the hairline separates the rows
    /// rather than boxing them, so the first one has none.
    @ViewBuilder
    private var rows: some View {
        ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
            VStack(alignment: .leading, spacing: 0) {
                if index > 0 {
                    LuckyHairline()
                        .padding(.bottom, 10)
                }
                row(index, key)
            }
        }
    }

    private func row(_ index: Int, _ key: String) -> some View {
        HStack(spacing: LuckyTheme.Space.s) {
            Text(verbatim: "\(index + 1)")
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textSecondary)
                .frame(width: 24)
            Text(key)
                .font(LuckyTheme.Text.codeSmall)
                .foregroundStyle(LuckyTheme.textPrimary)
                .lineLimit(1)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LuckyTheme.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth)
                )
            arrow("arrow.up", name: "上移子规则", disabled: index == 0) { move(index, -1) }
            arrow("arrow.down", name: "下移子规则", disabled: index == keys.count - 1) {
                move(index, 1)
            }
        }
    }

    /// 36×36 rather than §7.1's pill: the label lives in the accessibility layer, since a row this
    /// dense has no room for 上移 next to the key it moves.
    private func arrow(_ symbol: String, name: String, disabled: Bool,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(disabled ? LuckyTheme.textTertiary : LuckyTheme.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(disabled ? LuckyTheme.surfaceSunken : LuckyTheme.accentSoft)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(name)
    }

    /// Local only — `onSave` is what tells the module.
    private func move(_ index: Int, _ offset: Int) {
        keys = WebRecord.move(keys, index, offset)
    }
}
