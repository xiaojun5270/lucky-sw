import SwiftUI

/// The in-card action button used across the 服务 screens.
///
/// The four service screens are built out of `Pressable`s that live *inside* scrolling cards, and
/// glass may not go there — `LuckyPillButton` and `LuckyGlassIconButton` are reserved for the
/// floating bars. So this is a plain button whose seven fills map one-to-one onto the seven inline
/// `Pressable` styles the original uses, which is what keeps 同步 reading as the primary action and
/// 删除 as the dangerous one without either of them borrowing the glass layer's vocabulary.
struct ServiceActionButton: View {
    /// The original's inline styles, named for what they mean rather than what they draw.
    enum Fill {
        /// A solid accent surface. The primary verb of a row: 添加, 同步, 刷新.
        case solid
        /// Tinted surface *and* a tinted border — one step below `solid`: 模块设置.
        case tinted
        /// Tinted surface, no border. 删除 (with `tone: .danger`) and the active 最近日志.
        case soft
        /// The neutral raised surface. 编辑, 更多操作, 查看模块日志, the inactive 分页日志.
        case muted
        /// Hairline outline on nothing, with a neutral label. The five Docker verbs.
        case outline
        /// The card fill with a hairline border, for a control that must read as a surface: 排序.
        case card
        /// No background at all: 查看日志.
        case plain
    }

    var title: String
    var symbol: String?
    var tone: LuckyTone = .brand
    var fill: Fill = .soft
    var height: CGFloat = 40
    var radius: CGFloat = 8
    /// `flex: 1` in the original. `false` is a control sized by its own content.
    var expands: Bool = true
    var disabled: Bool = false
    /// The glyph becomes a spinner. Docker's batch verbs print their own progress in the label and
    /// swap `RefreshCw` / `PackageSearch` / `Trash2` for an `ActivityIndicator` while they run.
    var busy: Bool = false
    /// What VoiceOver reads, when it differs from the visible text — 升级状态 announces itself as
    /// 查看镜像升级状态, 全选 as 选择当前显示的全部镜像.
    var name: String?
    var glyph: CGFloat = 13
    /// `false` keeps a disabled button at full contrast. Docker's 删除所选 prints its progress in
    /// its own label while the batch runs, and a dimmed counter is unreadable.
    var dim: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(label)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: glyph, weight: .semibold))
                }
                Text(title)
                    .font(LuckyTheme.Text.captionMedium)
                    .lineLimit(1)
            }
            .foregroundStyle(label)
            .padding(.horizontal, expands ? LuckyTheme.Space.s : 10)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(height: height)
            .background(background)
            .overlay(border)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled && dim ? 0.45 : 1)
        .accessibilityLabel(name ?? title)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    private var label: Color {
        switch fill {
        case .solid: LuckyTheme.textOnAccent
        // Both of the neutral surfaces carry a neutral label: the tone is what the *border* means,
        // not the text. Docker's 镜像高级工具 and the inactive 批量操作 are exactly this.
        case .outline, .card: LuckyTheme.textPrimary
        default: tone.tint
        }
    }

    @ViewBuilder
    private var background: some View {
        switch fill {
        case .solid: shape.fill(tone.tint)
        case .tinted, .soft: shape.fill(tone.fill)
        case .muted: shape.fill(LuckyTheme.surfaceRaised)
        case .card: shape.fill(LuckyTheme.surface)
        case .outline, .plain: shape.fill(.clear)
        }
    }

    @ViewBuilder
    private var border: some View {
        switch fill {
        case .tinted:
            shape.strokeBorder(tone.tint.opacity(0.45), lineWidth: LuckyTheme.strokeWidth)
        case .outline, .card:
            shape.strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth)
        default:
            EmptyView()
        }
    }
}
