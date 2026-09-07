import SwiftUI

/// The brand mark: a stylised port forward — one fixed edge, two hops onward.
///
/// Drawn as a `Path` rather than an image so the login screen, the empty states and the app icon
/// all come from one definition. `Icon/make_icon.py` reproduces exactly this geometry in the
/// 1024×1024 asset, which is why the coordinates below are normalised to a unit square.
struct LuckyMark: View {
    var size: CGFloat = 82
    /// The plate is dropped when the mark sits on top of an already-tinted surface.
    var plate: Bool = true

    var body: some View {
        ZStack {
            if plate {
                RoundedRectangle(cornerRadius: size * 0.2315, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [LuckyTheme.bloomTeal, LuckyTheme.accent, LuckyTheme.violet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.2315, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: size * 0.012)
                    )
            }
            glyph
                .stroke(
                    plate ? Color.white : LuckyTheme.accent,
                    style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Lucky")
    }

    /// Unit-square geometry, shared with the icon generator: a vertical bar at x = 0.29 and two
    /// chevrons at x = 0.46 / 0.63 pointing right.
    private var glyph: Path {
        Path { path in
            let s = size
            path.move(to: CGPoint(x: 0.290 * s, y: 0.290 * s))
            path.addLine(to: CGPoint(x: 0.290 * s, y: 0.710 * s))
            for start in [0.455, 0.635] as [CGFloat] {
                path.move(to: CGPoint(x: start * s, y: 0.335 * s))
                path.addLine(to: CGPoint(x: (start + 0.165) * s, y: 0.500 * s))
                path.addLine(to: CGPoint(x: start * s, y: 0.665 * s))
            }
        }
    }
}
