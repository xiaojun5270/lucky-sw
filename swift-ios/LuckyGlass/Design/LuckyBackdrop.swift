import SwiftUI

/// Neutral operational canvas under the content and floating Liquid Glass command layer.
///
/// The old ambient aurora made every screen decorative in the same way. The cockpit background is
/// now deliberately quiet: real telemetry supplies movement and colour, while a subtle top rail gives
/// the system chrome enough luminance variation to refract. `animated` remains for source compatibility.
struct LuckyBackdrop: View {
    var animated: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [LuckyTheme.canvasTop, LuckyTheme.canvasBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [LuckyTheme.accent.opacity(0.10), LuckyTheme.info.opacity(0.025), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 112)
            .blur(radius: 28)
            .offset(y: -54)
            Rectangle()
                .fill(LuckyTheme.hairline.opacity(0.46))
                .frame(height: LuckyTheme.strokeWidth)
                .offset(y: 1)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
