import SwiftUI

/// A ring gauge for a 0–100 reading. The monitor screen draws CPU and memory with it, and the value
/// is always already a percent — `Format.percent(used, total)` is the only thing allowed to compute
/// one.
struct LuckyRingGauge: View {
    var percent: Double
    var label: String
    var caption: String?
    /// `nil` derives the colour from the reading, so a saturated CPU turns amber then red on its
    /// own.
    var tone: LuckyTone?
    var size: CGFloat = 108
    var lineWidth: CGFloat = 11

    private var clamped: Double {
        guard percent.isFinite else { return 0 }
        return min(max(percent, 0), 100)
    }

    private var resolved: LuckyTone { tone ?? LuckyTone.load(clamped) }

    var body: some View {
        VStack(spacing: LuckyTheme.Space.s) {
            ZStack {
                Circle()
                    .stroke(LuckyTheme.surfaceRaised, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: clamped / 100)
                    .stroke(
                        AngularGradient(
                            colors: [resolved.tint.opacity(0.55), resolved.tint],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(JSCompat.toFixed(clamped, 1))
                        .font(LuckyTheme.Text.metricSmall)
                        .foregroundStyle(LuckyTheme.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%")
                        .font(LuckyTheme.Text.caption)
                        .foregroundStyle(LuckyTheme.textTertiary)
                }
            }
            .frame(width: size, height: size)
            .animation(LuckyTheme.Motion.snap, value: clamped)
            VStack(spacing: 1) {
                Text(label)
                    .font(LuckyTheme.Text.captionMedium)
                    .foregroundStyle(LuckyTheme.textSecondary)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(LuckyTheme.Text.caption)
                        .foregroundStyle(LuckyTheme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(JSCompat.toFixed(clamped, 1))%")
    }
}

/// A horizontal meter — memory used of total, disk of quota, containers running of created.
/// `leading` and `trailing` are pre-formatted strings so the caller keeps control of units.
struct LuckyMeterBar: View {
    var label: String
    var percent: Double
    var leading: String?
    var trailing: String?
    var tone: LuckyTone?
    var height: CGFloat = 8

    private var clamped: Double {
        guard percent.isFinite else { return 0 }
        return min(max(percent, 0), 100)
    }

    private var resolved: LuckyTone { tone ?? LuckyTone.load(clamped) }

    /// A non-zero reading always draws at least a dot, so 0.2% does not vanish.
    private func fillWidth(in total: CGFloat) -> CGFloat {
        max(total * clamped / 100, clamped > 0 ? height : 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.xs) {
            HStack(spacing: LuckyTheme.Space.s) {
                Text(label)
                    .font(LuckyTheme.Text.captionMedium)
                    .foregroundStyle(LuckyTheme.textSecondary)
                Spacer(minLength: LuckyTheme.Space.xs)
                if let trailing, !trailing.isEmpty {
                    Text(trailing)
                        .font(LuckyTheme.Text.caption)
                        .foregroundStyle(LuckyTheme.textTertiary)
                        .monospacedDigit()
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous).fill(LuckyTheme.surfaceRaised)
                    Capsule(style: .continuous)
                        .fill(resolved.tint)
                        .frame(width: fillWidth(in: proxy.size.width))
                }
            }
            .frame(height: height)
            .animation(LuckyTheme.Motion.snap, value: clamped)
            if let leading, !leading.isEmpty {
                Text(leading)
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(JSCompat.toFixed(clamped, 1))%")
    }
}

/// One line of a sparkline.
struct LuckySparkSeries: Identifiable {
    var id: String
    var values: [Double]
    var tone: LuckyTone
    /// Only the primary series is area-filled; two filled series would hide each other.
    var filled: Bool = false
}

/// The rolling chart behind the monitor screen — the last 90 samples of CPU, memory or network
/// speed.
///
/// Series share one vertical scale so in and out speeds stay comparable, and the scale is the
/// maximum across all series rather than per series. The plot is inset to the middle four fifths of
/// the box, with five dashed gridlines behind it, so a reading pinned at 100% still reads as a line
/// instead of merging with the top edge. Drawn in a single `Canvas`: one `Path` per series is far
/// cheaper than a stack of shapes redrawn every second.
struct LuckySparkline: View {
    var series: [LuckySparkSeries]
    var height: CGFloat = 96
    /// Forces the top of the scale, and clamps readings above it. `nil` scales to the largest
    /// sample plus 12% of headroom, so a live line does not ride the ceiling.
    var ceiling: Double?
    /// Samples are taken from the tail, matching `samples.slice(-90)`.
    var window: Int = 90

    /// Gridlines and the plot band live in a 0–1 space over `height`: the original draws a 120-unit
    /// viewBox with lines at 12/36/60/84/108 and plots between 108 and 12.
    private static let gridlines: [CGFloat] = [0.1, 0.3, 0.5, 0.7, 0.9]
    private static let baseline: CGFloat = 0.9
    private static let span: CGFloat = 0.8

    private var windowed: [LuckySparkSeries] {
        series.map {
            var line = $0
            line.values = Array($0.values.suffix(window))
            return line
        }
    }

    private var peak: Double {
        if let ceiling, ceiling > 0 { return ceiling }
        let highest = windowed.flatMap(\.values).filter(\.isFinite).max() ?? 0
        return max(1, highest) * 1.12
    }

    var body: some View {
        Canvas { context, size in
            for fraction in Self.gridlines {
                var rule = Path()
                let y = (size.height * fraction).rounded() + 0.5
                rule.move(to: CGPoint(x: 0, y: y))
                rule.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    rule,
                    with: .color(LuckyTheme.separator),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 4])
                )
            }
            for line in windowed {
                let points = coordinates(line.values, in: size)
                guard points.count > 1 else { continue }
                var path = Path()
                path.addLines(points)
                if line.filled {
                    let floor = size.height * Self.baseline
                    var area = path
                    area.addLine(to: CGPoint(x: points[points.count - 1].x, y: floor))
                    area.addLine(to: CGPoint(x: points[0].x, y: floor))
                    area.closeSubpath()
                    context.fill(
                        area,
                        with: .linearGradient(
                            Gradient(colors: [line.tone.tint.opacity(0.30),
                                              line.tone.tint.opacity(0.02)]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: 0, y: floor)
                        )
                    )
                }
                context.stroke(
                    path,
                    with: .color(line.tone.tint),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(height: height)
        .background(ConcentricRectangle().fill(LuckyTheme.surfaceSunken))
        .accessibilityHidden(true)
    }

    private func coordinates(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        let scale = peak
        return values.enumerated().map { index, raw in
            let value = raw.isFinite ? min(max(raw, 0), scale) : 0
            let y = size.height * (Self.baseline - Self.span * CGFloat(value / scale))
            return CGPoint(x: CGFloat(index) * step, y: y)
        }
    }
}

/// A three-quarter arc for one already-formatted reading, with the gap at the bottom — the Docker
/// resource cards use it for CPU and memory.
///
/// `percent` is separate from `label` on purpose: the label may be `--`, or carry a different number
/// of digits than the arc's own precision, and an absent reading must draw an empty track rather
/// than a zero-length arc that looks like a real measurement of nothing.
struct LuckyArcGauge: View {
    var label: String
    var percent: Double?
    var tone: LuckyTone
    var size: CGFloat = 94
    var lineWidth: CGFloat = 8

    /// `arc = circumference * 0.75`, starting 135° round from three o'clock.
    private static let sweep: CGFloat = 0.75
    private static let start: Double = 135

    private var clamped: Double {
        guard let percent, percent.isFinite else { return 0 }
        return min(max(percent, 0), 100)
    }

    private var drawsProgress: Bool { percent != nil && clamped > 0 }

    var body: some View {
        ZStack {
            arc(to: Self.sweep, color: LuckyTheme.surfaceRaised)
            if drawsProgress {
                arc(to: Self.sweep * CGFloat(clamped / 100), color: tone.tint)
            }
            Text(label)
                .font(LuckyTheme.Text.metricSmall)
                .foregroundStyle(LuckyTheme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, lineWidth * 2)
        }
        .frame(width: size, height: size)
        .animation(LuckyTheme.Motion.snap, value: clamped)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: lineWidth, lineCap: .round) }

    /// The ring is inset from the box the way the original's radius 34 sits inside its 94-unit
    /// viewBox, which leaves room for the round cap without clipping it.
    private func arc(to end: CGFloat, color: Color) -> some View {
        Circle()
            .trim(from: 0, to: end)
            .rotation(.degrees(Self.start))
            .stroke(color, style: stroke)
            .frame(width: size * 0.724, height: size * 0.724)
    }
}
