import SwiftUI

/// The floating layer: the only place in the app allowed to use `glassEffect`.
///
/// Rules these views encode, so screens cannot get them wrong:
/// * one `GlassEffectContainer` per cluster, never nested, never inside a scroll view's content;
/// * a tint only when it means something (destructive, primary, selected);
/// * `glassEffectID` inside `withAnimation` so shapes morph rather than cross-fade.
struct LuckyGlassBar<Content: View>: View {
    var spacing: CGFloat = LuckyTheme.Space.s
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: LuckyTheme.Space.gutter) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: spacing, content: content)
                ScrollView(.horizontal) {
                    HStack(spacing: spacing, content: content)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, LuckyTheme.Space.gutter)
        .padding(.bottom, LuckyTheme.Space.s)
    }
}

/// The standard action button. `prominent` is the screen's single primary verb — 保存, 登录, 发送请求 —
/// and everything else is plain glass.
struct LuckyPillButton: View {
    var title: String
    var symbol: String?
    var tone: LuckyTone = .brand
    var prominent: Bool = false
    var loading: Bool = false
    var fills: Bool = true
    var action: () -> Void

    /// `.glass` and `.glassProminent` are different types, so the branch happens here rather than
    /// through a ternary on a single `buttonStyle` call.
    var body: some View {
        if prominent {
            button.buttonStyle(.glassProminent).tint(tone.tint)
        } else {
            button.buttonStyle(.glass).foregroundStyle(tone.tint)
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: LuckyTheme.Space.s) {
                if loading {
                    ProgressView().controlSize(.small)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                }
                Text(title).font(LuckyTheme.Text.button).lineLimit(1)
            }
            .frame(maxWidth: fills ? .infinity : nil)
            .padding(.vertical, 4)
        }
        .disabled(loading)
    }
}

/// A circular glass button, for anything whose meaning fits in one glyph: 刷新, 复制, 展开.
struct LuckyGlassIconButton: View {
    var symbol: String
    var label: String
    var tone: LuckyTone = .brand
    var prominent: Bool = false
    var action: () -> Void

    var body: some View {
        if prominent {
            button.buttonStyle(.glassProminent).tint(tone.tint)
        } else {
            button.buttonStyle(.glass).foregroundStyle(tone.tint)
        }
    }

    private var button: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                // 44×44 is the minimum comfortable target; the glass shape follows the frame.
                .frame(width: 26, height: 26)
        }
        .accessibilityLabel(label)
    }
}

/// A read-only floating badge — the live-connection pill over the monitor chart, the "只读" marker
/// over a GET result. Not a button, so it gets glass directly instead of a button style.
struct LuckyGlassBadge: View {
    var text: String
    var symbol: String?
    var tone: LuckyTone = .idle
    var pulsing: Bool = false

    var body: some View {
        HStack(spacing: LuckyTheme.Space.xs) {
            if pulsing {
                LuckyStatusDot(tone: tone, pulsing: true, size: 7)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold))
            }
            Text(text).font(LuckyTheme.Text.captionMedium).lineLimit(1)
        }
        .foregroundStyle(tone.tint)
        .padding(.horizontal, LuckyTheme.Space.m)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }
}

/// One option of a segmented control.
struct LuckySegment<Value: Hashable>: Identifiable {
    var value: Value
    var title: String
    var symbol: String?

    var id: Value { value }

    init(_ value: Value, _ title: String, symbol: String? = nil) {
        self.value = value
        self.title = title
        self.symbol = symbol
    }
}

/// A view switcher whose selection indicator is a single glass shape that *travels* between
/// segments.
///
/// Exactly one glass shape exists inside the container — the selected segment owns it via
/// `glassEffectID`, and the unselected segments are plain text. That is what makes the indicator
/// morph instead of fading, and it keeps the "no glass thicket" rule intact.
///
/// Use this for up to four options and pin it (`safeAreaBar`, or a header outside the scroll view);
/// for longer lists use `LuckyGlassMenuPicker`. Set `glass: false` when the control must live
/// inside scrolling content, which falls back to a tinted capsule.
struct LuckyGlassSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    var segments: [LuckySegment<Value>]
    var tone: LuckyTone = .brand
    var glass: Bool = true

    @Namespace private var indicator

    var body: some View {
        GlassEffectContainer(spacing: LuckyTheme.Space.m) {
            HStack(spacing: LuckyTheme.Space.xs) {
                ForEach(segments) { segment in
                    segmentButton(segment)
                }
            }
            .padding(4)
            .background(Capsule(style: .continuous).fill(LuckyTheme.surfaceRaised))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth)
            )
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    @ViewBuilder
    private func segmentButton(_ segment: LuckySegment<Value>) -> some View {
        let selected = segment.value == selection
        Button {
            withAnimation(LuckyTheme.Motion.morph) { selection = segment.value }
        } label: {
            HStack(spacing: LuckyTheme.Space.xs) {
                if let symbol = segment.symbol {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                }
                Text(segment.title).font(LuckyTheme.Text.captionMedium).lineLimit(1)
            }
            .foregroundStyle(selected ? tone.tint : LuckyTheme.textSecondary)
            .padding(.horizontal, LuckyTheme.Space.m)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                if selected {
                    if glass {
                        Capsule(style: .continuous)
                            .fill(.clear)
                            .glassEffect(.regular.tint(tone.tint.opacity(0.18)), in: .capsule)
                            .glassEffectID("indicator", in: indicator)
                    } else {
                        Capsule(style: .continuous)
                            .fill(tone.fill)
                            .matchedGeometryEffect(id: "indicator", in: indicator)
                    }
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The same job as `LuckyGlassSegmentedControl` when there are too many options to sit side by side
/// — Docker's six views, a module list, a log source. A glass button that opens a system menu.
struct LuckyGlassMenuPicker<Value: Hashable>: View {
    var title: String
    @Binding var selection: Value
    var segments: [LuckySegment<Value>]
    var tone: LuckyTone = .brand

    private var current: LuckySegment<Value>? {
        segments.first { $0.value == selection }
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(segments) { segment in
                    if let symbol = segment.symbol {
                        Label(segment.title, systemImage: symbol).tag(segment.value)
                    } else {
                        Text(segment.title).tag(segment.value)
                    }
                }
            }
        } label: {
            HStack(spacing: LuckyTheme.Space.xs) {
                if let symbol = current?.symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                Text(current?.title ?? title).font(LuckyTheme.Text.button).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(tone.tint)
            .padding(.horizontal, LuckyTheme.Space.l)
            .padding(.vertical, 10)
            // Glass goes on the label rather than through `buttonStyle`: a `Menu` does not reliably
            // forward a button style to its label on iOS, and the shape here must be exact.
            .glassEffect(.regular, in: .capsule)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
