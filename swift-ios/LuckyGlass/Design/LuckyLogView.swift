import SwiftUI

/// The log viewer shared by the global log screen, the per-service log screens and the container
/// log screen. It takes the already-extracted lines from `LuckyLog` — nothing here parses a
/// payload.
///
/// `LazyVStack` inside a `ScrollView` rather than a `List`: a tail of 5,000 lines has to stay
/// smooth, and list rows would each build a background this view does not want.
struct LuckyLogView: View {
    var lines: [String]
    /// Highlighted, not filtered — the screens filter upstream so the counts they show stay honest.
    var query: String = ""
    /// Pins to the newest line as it arrives. The screens expose it as 自动滚动.
    var follows: Bool = true
    /// `nil` fills whatever space the parent offers — the global log tab is a non-scrolling page
    /// whose list must reach the tab bar.
    var height: CGFloat? = 380

    private static let bottomAnchor = "lucky.log.bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        row(line)
                            .id(index)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                .padding(LuckyTheme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .background(ConcentricRectangle().fill(LuckyTheme.surfaceSunken))
            .onChange(of: lines.count) {
                guard follows else { return }
                withAnimation(LuckyTheme.Motion.snap) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    private func row(_ line: String) -> some View {
        Text(attributed(line))
            .font(LuckyTheme.Text.codeSmall)
            .foregroundStyle(LuckyLogView.tone(line)?.tint ?? LuckyTheme.textSecondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Only failures and warnings are tinted. Colouring every line by level turns a busy log into
    /// confetti, and Lucky's own logs are mostly untagged Chinese sentences.
    private static func tone(_ line: String) -> LuckyTone? {
        // Level tags sit at the head of the line; scanning the whole string would cost a full pass
        // over every visible row on every frame of a scroll.
        let head = line.prefix(72).lowercased()
        if head.contains("error") || head.contains("fatal") || head.contains("panic")
            || head.contains("失败") || head.contains("错误") { return .danger }
        if head.contains("warn") || head.contains("警告") { return .warning }
        return nil
    }

    /// Marks every occurrence of the query. `AttributedString` is built per visible line only, and
    /// only when there is something to mark.
    private func attributed(_ line: String) -> AttributedString {
        var text = AttributedString(line)
        let needle = query.jsTrimmed
        guard !needle.isEmpty else { return text }
        var cursor = text.startIndex
        while cursor < text.endIndex,
              let found = text[cursor...].range(of: needle, options: .caseInsensitive) {
            text[found].backgroundColor = LuckyTheme.accent.opacity(0.28)
            text[found].foregroundColor = LuckyTheme.textPrimary
            cursor = found.upperBound
        }
        return text
    }
}
