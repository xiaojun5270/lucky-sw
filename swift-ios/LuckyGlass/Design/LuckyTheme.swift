import SwiftUI
import UIKit

/// The visual language of Lucky's infrastructure control cockpit.
///
/// Content is organised as instruments, routes, ledgers and evidence. Colour denotes a verified
/// state or data direction rather than decorating a card; Liquid Glass belongs only to the floating
/// command layer. Every screen consumes these tokens so light, dark and high-contrast appearances
/// remain one coherent system.
enum LuckyTheme {
    // MARK: - Palette

    /// Dynamic sRGB colour with explicit Increase Contrast values. The fallback pair keeps old call
    /// sites source-compatible while cockpit-critical colours provide tuned high-contrast variants.
    static func dynamic(light: UInt32, dark: UInt32, lightHigh: UInt32? = nil,
                        darkHigh: UInt32? = nil) -> Color {
        Color(UIColor { traits in
            let darkMode = traits.userInterfaceStyle == .dark
            let high = traits.accessibilityContrast == .high
            let normal = darkMode ? dark : light
            let contrasted = darkMode ? darkHigh : lightHigh
            return UIColor(rgb: high ? contrasted ?? normal : normal)
        })
    }

    /// Control blue: current focus, the latest telemetry segment and the primary command.
    static let accent = dynamic(light: 0x006F95, dark: 0x58C8EA,
                                lightHigh: 0x005778, darkHigh: 0x7BDBF4)
    static let accentSoft = dynamic(light: 0xD9EFF5, dark: 0x10343E,
                                    lightHigh: 0xC5E6EF, darkHigh: 0x174956)
    /// Compatibility hue. New views use `info` for ingress rather than a decorative purple.
    static let violet = dynamic(light: 0x315DA8, dark: 0x7CA9F2)
    static let violetSoft = dynamic(light: 0xE1EAF8, dark: 0x182A47)

    static let success = dynamic(light: 0x147854, dark: 0x5DDAA4,
                                 lightHigh: 0x0B6041, darkHigh: 0x78F0BA)
    static let successSoft = dynamic(light: 0xDDF2E9, dark: 0x123B2E)
    static let warning = dynamic(light: 0x8D5B00, dark: 0xF0B652,
                                 lightHigh: 0x714700, darkHigh: 0xFFD078)
    static let warningSoft = dynamic(light: 0xF6EAD2, dark: 0x3E2F13)
    static let danger = dynamic(light: 0xB62D46, dark: 0xFF7188,
                                lightHigh: 0x921D35, darkHigh: 0xFF98A8)
    static let dangerSoft = dynamic(light: 0xF7E1E6, dark: 0x421C26)
    /// Ingress and informational data. Egress uses `warning` so direction never relies on text alone.
    static let info = dynamic(light: 0x315DA8, dark: 0x7CA9F2,
                              lightHigh: 0x234B91, darkHigh: 0x9ABFFF)
    static let infoSoft = dynamic(light: 0xE1EAF8, dark: 0x182A47)
    static let idle = dynamic(light: 0x69747E, dark: 0x97A4AE)
    static let idleSoft = dynamic(light: 0xE8ECEF, dark: 0x202932)

    // MARK: - Backdrop and surfaces

    static let canvasTop = dynamic(light: 0xF5F7F8, dark: 0x080C10)
    static let canvasBottom = dynamic(light: 0xEDF1F3, dark: 0x0B1117)
    /// Compatibility aliases for `LuckyMark`; the page backdrop no longer paints ambient blooms.
    static let bloomTeal = dynamic(light: 0x38D6C6, dark: 0x1E9C93)
    static let bloomViolet = dynamic(light: 0x315DA8, dark: 0x7CA9F2)

    static let surface = dynamic(light: 0xFFFFFF, dark: 0x10171E,
                                 lightHigh: 0xFFFFFF, darkHigh: 0x0E151B)
    static let surfaceRaised = dynamic(light: 0xF0F3F5, dark: 0x17212A)
    static let surfaceSunken = dynamic(light: 0xE8ECEF, dark: 0x060A0E)
    static let hairline = dynamic(light: 0xD7DDE1, dark: 0x2A3641,
                                  lightHigh: 0xAEB8BF, darkHigh: 0x52616D)
    static let separator = dynamic(light: 0xE7EAED, dark: 0x202A33,
                                   lightHigh: 0xC6CDD2, darkHigh: 0x43515C)

    static let textPrimary = dynamic(light: 0x10161C, dark: 0xF2F6F8)
    static let textSecondary = dynamic(light: 0x4E5B66, dark: 0xACB7C0,
                                       lightHigh: 0x33404A, darkHigh: 0xCDD5DB)
    static let textTertiary = dynamic(light: 0x79858F, dark: 0x7C8993,
                                      lightHigh: 0x56636D, darkHigh: 0xA3AFB8)
    static let textOnAccent = dynamic(light: 0xFFFFFF, dark: 0x041C25)

    // MARK: - Radii

    /// Corners are structural now: instruments remain recognisably grouped without becoming soft
    /// floating cards. Nested controls derive their corner from the container whenever possible.
    enum Radius {
        static let hero: CGFloat = 20
        static let card: CGFloat = 16
        static let panel: CGFloat = 14
        static let row: CGFloat = 10
        static let chip: CGFloat = 7
        static let field: CGFloat = 10
        static let concentricFloor: CGFloat = 6
    }

    // MARK: - Spacing

    enum Space {
        static let hair: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// Page side margin. Also the spacing handed to `GlassEffectContainer`, which uses it to
        /// decide how close two glass shapes must be before their fields merge.
        static let gutter: CGFloat = 18
        /// Vertical rhythm between cards in a scroll view.
        static let stack: CGFloat = 14
        /// Inner padding of a card, and therefore the concentric inset of anything drawn inside
        /// one.
        static let cardInset: CGFloat = 16
    }

    // MARK: - Typography

    /// Chinese interface prose follows Dynamic Type. Only values that users compare character by
    /// character—addresses, ports, timings, sizes and payloads—use a monospaced design.
    enum Text {
        static let hero = Font.largeTitle.weight(.semibold)
        static let title = Font.title2.weight(.semibold)
        static let sectionTitle = Font.subheadline.weight(.semibold)
        static let cardTitle = Font.headline.weight(.semibold)
        static let body = Font.body
        static let bodyMedium = Font.body.weight(.medium)
        static let caption = Font.footnote
        static let captionMedium = Font.footnote.weight(.semibold)
        static let label = Font.subheadline.weight(.medium)
        static let metric = Font.system(.title, design: .monospaced).weight(.semibold)
        static let metricSmall = Font.system(.title3, design: .monospaced).weight(.semibold)
        static let code = Font.system(.callout, design: .monospaced)
        static let codeSmall = Font.system(.caption, design: .monospaced)
        static let button = Font.headline
    }

    // MARK: - Motion

    /// Glass morphing (`glassEffectID`) only interpolates inside `withAnimation`, so these are the
    /// durations the whole app shares. Anything faster than `.snap` reads as a glitch on a shape
    /// that is also refracting its backdrop.
    enum Motion {
        /// Selection changes, chips, toggles.
        static let snap = Animation.snappy(duration: 0.26, extraBounce: 0.02)
        /// Glass shapes merging or splitting.
        static let morph = Animation.smooth(duration: 0.38)
        /// Cards appearing after a load.
        static let reveal = Animation.smooth(duration: 0.3)
        /// The status pulse on a live dot.
        static let pulse = Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true)
    }

    // MARK: - Depth

    /// Content-layer shadow. Deliberately soft and single-layer: iOS 26 draws its own shadow under
    /// glass, and a second one under the card underneath makes the stack look muddy.
    enum Shadow {
        static let color = Color.black.opacity(0.10)
        static let radius: CGFloat = 14
        static let y: CGFloat = 6
    }

    /// Hairline width. `1 / displayScale` would be crisper but reads as a hard line against glass,
    /// so the port uses a full point at low opacity instead.
    static let strokeWidth: CGFloat = 1
}

extension UIColor {
    /// `0xRRGGBB` → opaque colour, in the sRGB (device) space so the hex matches the design values.
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
