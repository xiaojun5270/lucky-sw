import SwiftUI

/// Shared field for live measurements. The field is one surface; its cells align to the same datum
/// and never become a grid of decorative cards.
struct LuckyTelemetryDeck<Content: View>: View {
    var title: String
    var subtitle: String?
    var tone: LuckyTone = .brand
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.l) {
            HStack(alignment: .firstTextBaseline, spacing: LuckyTheme.Space.s) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tone.tint)
                Text(title)
                    .font(LuckyTheme.Text.sectionTitle)
                    .foregroundStyle(LuckyTheme.textPrimary)
                Spacer(minLength: LuckyTheme.Space.s)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(LuckyTheme.Text.codeSmall)
                        .foregroundStyle(LuckyTheme.textTertiary)
                }
            }
            content()
        }
        .padding(LuckyTheme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LuckyTheme.Radius.hero, style: .continuous)
                .fill(LuckyTheme.surface)
        )
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [tone.tint.opacity(0.62), tone.tint.opacity(0.08), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 2)
            .clipShape(Capsule())
            .padding(.horizontal, LuckyTheme.Space.l)
        }
        .overlay(
            RoundedRectangle(cornerRadius: LuckyTheme.Radius.hero, style: .continuous)
                .strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth)
        )
        .containerShape(.rect(cornerRadius: LuckyTheme.Radius.hero))
    }
}

/// A single reading aligned to the deck's shared baseline.
struct LuckyTelemetryReading: View {
    var label: String
    var value: String
    var detail: String?
    var symbol: String
    var tone: LuckyTone = .brand

    var body: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.xs) {
            HStack(spacing: LuckyTheme.Space.xs) {
                Circle().fill(tone.tint).frame(width: 5, height: 5)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tone.tint)
                Text(label)
                    .font(LuckyTheme.Text.captionMedium)
                    .foregroundStyle(LuckyTheme.textSecondary)
            }
            Text(value)
                .font(LuckyTheme.Text.metricSmall)
                .foregroundStyle(LuckyTheme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textTertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
