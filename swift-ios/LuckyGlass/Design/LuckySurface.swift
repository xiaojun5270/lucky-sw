import SwiftUI

/// Semantic roles for opaque cockpit content. The role changes depth and boundary treatment, not
/// the public structure of `LuckyCard`, so existing feature code can migrate incrementally.
enum LuckySurfaceRole: Sendable {
    case instrument
    case group
    case ledger
    case evidence
    case critical
}

struct LuckyCard<Content: View>: View {
    var radius: CGFloat = LuckyTheme.Radius.card
    var padding: CGFloat = LuckyTheme.Space.cardInset
    var spacing: CGFloat = LuckyTheme.Space.m
    var tone: LuckyTone?
    var role: LuckySurfaceRole = .group
    @ViewBuilder var content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    private var fill: Color {
        switch role {
        case .evidence: LuckyTheme.surfaceSunken
        case .instrument, .group, .ledger, .critical: LuckyTheme.surface
        }
    }

    private var stroke: Color {
        switch role {
        case .critical:
            return (tone ?? .danger).tint.opacity(0.66)
        case .instrument, .group, .ledger, .evidence:
            return tone?.tint.opacity(0.34) ?? LuckyTheme.hairline
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing, content: content)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: LuckyTheme.strokeWidth))
            .overlay(alignment: .topLeading) {
                if role == .instrument, let tone {
                    Capsule()
                        .fill(tone.tint)
                        .frame(width: 40, height: 2)
                        .padding(.leading, padding)
                }
            }
            .containerShape(shape)
    }
}

struct LuckyCardButtonStyle: ButtonStyle {
    var radius: CGFloat = LuckyTheme.Radius.card
    var padding: CGFloat = LuckyTheme.Space.m + 3
    var tone: LuckyTone?

    func makeBody(configuration: Configuration) -> some View {
        LuckyCard(radius: radius, padding: padding, tone: tone) {
            configuration.label
        }
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(configuration.isPressed ? LuckyTheme.surfaceRaised : .clear)
        )
        .animation(LuckyTheme.Motion.snap, value: configuration.isPressed)
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A nested surface inside a card — a log line, a port mapping, a JSON field. Its corners are
/// derived from the card's, so the inset never looks like a sticker.
struct LuckyInset<Content: View>: View {
    var padding: CGFloat = LuckyTheme.Space.m
    var spacing: CGFloat = LuckyTheme.Space.s
    var fill: Color = LuckyTheme.surfaceRaised
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing, content: content)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ConcentricRectangle().fill(fill))
    }
}

/// A group heading. Sits outside the card, in the page margin, so the card itself stays a clean
/// plate.
struct LuckySectionHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LuckyTheme.Space.s) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LuckyTheme.accent)
            }
            VStack(alignment: .leading, spacing: LuckyTheme.Space.hair) {
                Text(title)
                    .font(LuckyTheme.Text.sectionTitle)
                    .foregroundStyle(LuckyTheme.textSecondary)
                    .textCase(nil)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(LuckyTheme.Text.caption)
                        .foregroundStyle(LuckyTheme.textTertiary)
                }
            }
            Spacer(minLength: LuckyTheme.Space.s)
            trailing()
        }
        .padding(.horizontal, LuckyTheme.Space.xs)
    }
}

extension LuckySectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, symbol: String? = nil) {
        self.init(title: title, subtitle: subtitle, symbol: symbol) { EmptyView() }
    }
}

/// Header plus card, which is how almost every screen is laid out.
struct LuckySection<Content: View>: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    var padding: CGFloat = LuckyTheme.Space.cardInset
    var spacing: CGFloat = LuckyTheme.Space.m
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            LuckySectionHeader(title: title, subtitle: subtitle, symbol: symbol)
            LuckyCard(padding: padding, spacing: spacing, content: content)
        }
    }
}

/// A label/value line. `value` is monospaced when it holds an address, a port or a byte count,
/// which is most of what Lucky reports — hence the `mono` flag rather than a separate view.
struct LuckyRow<Trailing: View>: View {
    var label: String
    var value: String?
    var mono: Bool = false
    var tone: LuckyTone?
    var lineLimit: Int? = 2
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LuckyTheme.Space.m) {
            Text(label)
                .font(LuckyTheme.Text.label)
                .foregroundStyle(LuckyTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: LuckyTheme.Space.s)
            if let value, !value.isEmpty {
                Text(value)
                    .font(mono ? LuckyTheme.Text.code : LuckyTheme.Text.bodyMedium)
                    .foregroundStyle(tone?.tint ?? LuckyTheme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(lineLimit)
                    .textSelection(.enabled)
            }
            trailing()
        }
    }
}

extension LuckyRow where Trailing == EmptyView {
    init(_ label: String, _ value: String?, mono: Bool = false, tone: LuckyTone? = nil,
         lineLimit: Int? = 2) {
        self.init(label: label, value: value, mono: mono, tone: tone, lineLimit: lineLimit) {
            EmptyView()
        }
    }
}

/// The separator between rows inside a card. Full-width lines make a card look like a table, so
/// this one is inset and very low contrast.
struct LuckyHairline: View {
    var body: some View {
        Rectangle()
            .fill(LuckyTheme.separator)
            .frame(height: LuckyTheme.strokeWidth)
            .accessibilityHidden(true)
    }
}

/// JSON, YAML, compose files and log tails. Sunken rather than raised: the response body is
/// evidence, not a control, and it should read as a well in the card.
struct LuckyCodeBlock: View {
    var text: String
    /// `nil` grows with the content; the debugger caps it and lets the user expand.
    var maxHeight: CGFloat? = 260
    var small: Bool = false

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text.isEmpty ? "—" : text)
                .font(small ? LuckyTheme.Text.codeSmall : LuckyTheme.Text.code)
                .foregroundStyle(LuckyTheme.textPrimary)
                .textSelection(.enabled)
                .padding(LuckyTheme.Space.m)
                .frame(minWidth: 0, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: maxHeight)
        .background(ConcentricRectangle().fill(LuckyTheme.surfaceSunken))
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// One number in the dashboard grid. `value` is pre-formatted — every byte and percent in the app
/// goes through `Format`, so this view never does arithmetic.
struct LuckyMetricTile: View {
    var label: String
    var value: String
    var caption: String?
    var symbol: String
    var tone: LuckyTone = .brand
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            HStack(spacing: LuckyTheme.Space.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tone.tint)
                Text(label)
                    .font(LuckyTheme.Text.captionMedium)
                    .foregroundStyle(LuckyTheme.textSecondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(compact ? LuckyTheme.Text.metricSmall : LuckyTheme.Text.metric)
                .foregroundStyle(LuckyTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LuckyTheme.Space.m)
        .background(ConcentricRectangle().fill(LuckyTheme.surfaceRaised))
    }
}
