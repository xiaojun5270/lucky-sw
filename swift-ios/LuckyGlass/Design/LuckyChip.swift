import SwiftUI

/// A status pip. The pulse is reserved for a live socket — a dot that breathes when nothing is
/// actually streaming is a lie the monitor screen would tell every second.
struct LuckyStatusDot: View {
    var tone: LuckyTone
    var pulsing: Bool = false
    var size: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wide = false

    var body: some View {
        Circle()
            .fill(tone.tint)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(tone.tint.opacity(0.45), lineWidth: 2)
                    .scaleEffect(wide ? 2.1 : 1)
                    .opacity(wide ? 0 : 1)
            }
            .onAppear {
                guard pulsing, !reduceMotion else { return }
                withAnimation(LuckyTheme.Motion.pulse) { wide = true }
            }
            .accessibilityHidden(true)
    }
}

/// A labelled state. Lives on the content layer, so it is a tinted fill rather than glass.
struct LuckyChip: View {
    var text: String
    var tone: LuckyTone = .idle
    var symbol: String?
    /// `false` draws it as a tinted outline, for a chip sitting on an already-filled surface.
    var filled: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.caption2.weight(.bold))
            }
            Text(text)
                .font(LuckyTheme.Text.captionMedium)
                .lineLimit(1)
        }
        .foregroundStyle(tone.tint)
        .padding(.horizontal, LuckyTheme.Space.s)
        .padding(.vertical, LuckyTheme.Space.xs)
        .background {
            let shape = RoundedRectangle(cornerRadius: LuckyTheme.Radius.chip, style: .continuous)
            if filled {
                shape.fill(tone.fill.opacity(0.70))
            } else {
                shape.strokeBorder(tone.tint.opacity(0.36), lineWidth: LuckyTheme.strokeWidth)
            }
        }
    }
}

extension LuckyHttpMethod {
    /// Read/write intent as colour, matching `methodColor` in `app/modules/[module].tsx`: `GET` is
    /// `colors.success`, `POST` is `colors.primary`, `PUT` is `colors.warning` and everything else
    /// falls through to `colors.danger`.
    var tone: LuckyTone {
        switch self {
        case .get: .ok
        case .post: .brand
        case .put: .warning
        case .delete, .patch: .danger
        }
    }
}

/// The method badge used by the endpoint list, the endpoint detail header and the request log.
struct LuckyMethodBadge: View {
    var method: LuckyHttpMethod
    var compact: Bool = false

    var body: some View {
        Text(method.rawValue)
            .font(.system(size: compact ? 9 : 10, weight: .heavy, design: .rounded))
            .kerning(0.3)
            .foregroundStyle(method.tone.tint)
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, compact ? 2 : 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(method.tone.fill)
            )
            .accessibilityLabel("\(method.rawValue) 请求")
    }
}

/// A count on the trailing edge of a row — module endpoint counts, container totals, log line
/// counts.
struct LuckyCountBadge: View {
    var count: Int
    var tone: LuckyTone = .idle

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tone.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(tone.fill))
            .contentTransition(.numericText())
    }
}

/// Wrapping row of chips. A `Layout` rather than a `LazyVGrid` because the items have wildly
/// different widths — a module list runs from `ddns` to `docker-compose-project`, and a fixed grid
/// would leave half the row empty.
struct LuckyWrap: Layout {
    var spacing: CGFloat = LuckyTheme.Space.s
    var lineSpacing: CGFloat = LuckyTheme.Space.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var line: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if line > 0, line + spacing + size.width > limit {
                width = max(width, line)
                height += lineHeight + lineSpacing
                line = 0
                lineHeight = 0
            }
            line += line > 0 ? spacing + size.width : size.width
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: max(width, line), height: height + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
