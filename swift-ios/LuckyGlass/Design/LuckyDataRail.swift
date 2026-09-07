import SwiftUI

/// One continuous operational ledger. Records share a surface and alignment rails instead of each
/// becoming a floating card; this is the cockpit's default language for services and resources.
struct LuckyDataRail<Rows: View>: View {
    var title: String?
    var subtitle: String?
    var tone: LuckyTone = .brand
    @ViewBuilder var rows: () -> Rows

    init(title: String? = nil, subtitle: String? = nil, tone: LuckyTone = .brand,
         @ViewBuilder rows: @escaping () -> Rows) {
        self.title = title
        self.subtitle = subtitle
        self.tone = tone
        self.rows = rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: LuckyTheme.Space.s) {
                    Capsule()
                        .fill(tone.tint)
                        .frame(width: 3, height: 16)
                    Text(title)
                        .font(LuckyTheme.Text.sectionTitle)
                        .foregroundStyle(LuckyTheme.textPrimary)
                    Spacer(minLength: LuckyTheme.Space.s)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(LuckyTheme.Text.caption)
                            .foregroundStyle(LuckyTheme.textTertiary)
                    }
                }
                .padding(.horizontal, LuckyTheme.Space.m)
                .padding(.vertical, LuckyTheme.Space.s)
                LuckyHairline()
            }
            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LuckyTheme.Radius.panel, style: .continuous)
                .fill(LuckyTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LuckyTheme.Radius.panel, style: .continuous)
                .strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth)
        )
        .containerShape(.rect(cornerRadius: LuckyTheme.Radius.panel))
    }
}

/// A branch marker used where parent-child relationships are real: listeners to rules, tunnels to
/// proxies and the Lucky host to its Web and Docker subsystems.
struct LuckyRailMarker: View {
    var tone: LuckyTone
    var active: Bool = false
    var symbol: String?

    var body: some View {
        ZStack {
            Capsule()
                .fill(tone.tint.opacity(active ? 0.55 : 0.18))
                .frame(width: 2)
            Circle()
                .fill(active ? tone.tint : LuckyTheme.surface)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(tone.tint, lineWidth: 2))
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(active ? LuckyTheme.textOnAccent : tone.tint)
            }
        }
        .frame(width: 24)
        .frame(minHeight: 42)
        .accessibilityHidden(true)
    }
}
