import SwiftUI

/// Context carried by the floating command layer. Glass now explains what is being controlled rather
/// than merely frosting a row of buttons.
struct LuckyCommandContext {
    var title: String
    var detail: String = ""
    var symbol: String
    var tone: LuckyTone = .brand
}

struct LuckyCommandDeck<Actions: View>: View {
    var context: LuckyCommandContext?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        LuckyGlassBar {
            if let context {
                HStack(spacing: LuckyTheme.Space.s) {
                    Image(systemName: context.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(context.tone.tint)
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.title)
                            .font(LuckyTheme.Text.captionMedium)
                            .foregroundStyle(LuckyTheme.textPrimary)
                            .lineLimit(1)
                        if !context.detail.isEmpty {
                            Text(context.detail)
                                .font(LuckyTheme.Text.codeSmall)
                                .foregroundStyle(LuckyTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            actions()
        }
    }
}
