import SwiftUI

/// A card that folds. The endpoint browser groups 328 endpoints under 45 modules, and the detail
/// screens hide the raw record behind 原始数据 — both need the same behaviour, and neither may keep the
/// hidden content in the layout while collapsed.
struct LuckyDisclosureCard<Content: View>: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    var tone: LuckyTone
    var count: Int?
    @ViewBuilder var content: () -> Content

    @State private var expanded: Bool

    init(title: String, subtitle: String? = nil, symbol: String? = nil, tone: LuckyTone = .brand,
         count: Int? = nil, expanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tone = tone
        self.count = count
        self.content = content
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            Button {
                withAnimation(LuckyTheme.Motion.snap) { expanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(expanded ? "收起" : "展开")
            if expanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var header: some View {
        HStack(spacing: LuckyTheme.Space.m) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tone.tint)
                    .frame(width: 30, height: 30)
                    .background(ConcentricRectangle().fill(tone.fill))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(LuckyTheme.Text.cardTitle)
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(LuckyTheme.Text.caption)
                        .foregroundStyle(LuckyTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let count { LuckyCountBadge(count: count, tone: tone) }
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LuckyTheme.textTertiary)
                .rotationEffect(.degrees(expanded ? 0 : -90))
        }
        .contentShape(.rect)
    }
}
