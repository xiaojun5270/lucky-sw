import SwiftUI

/// §18 — Docker 日志, which is two views wearing one tab.
///
/// Mode A appears whenever a container-log, compose-log or file-listing read has just landed in
/// `output`: the payload takes over the tab and the pager disappears, because what is on screen is
/// no longer the daemon's log. Leaving the tab, or coming back to it, clears `output` and Mode B
/// returns — that is `selectDockerView`'s `setOutput("")`, not anything this view does.
struct DockerLogsView: View {
    /// `output` — non-nil is Mode A.
    var output: JSONValue?
    /// `dockerLogLines` — Mode B's 200-line page.
    var lines: [String]
    var loading: Bool
    var refresh: @Sendable () async -> Void

    var body: some View {
        if let output {
            payload(output)
        } else {
            page
        }
    }

    /// §18.1. A scroll rather than a list, and no pager: one payload, however deep it is.
    private func payload(_ value: JSONValue) -> some View {
        DockerPaneScroll(refresh: refresh) {
            LuckySectionHeader(title: DockerView.logs.title, symbol: DockerView.logs.symbol)
            LuckyCard(spacing: LuckyTheme.Space.m) {
                StructuredDataView(value: value)
            }
        }
    }

    /// §18.2. `spacing: 0` — the one list in the screen with no separator: its rows butt together
    /// and the hairline at the top of each one is the divider, which is what makes 200 lines of
    /// monospace read as a single block of log rather than 200 cards.
    private var page: some View {
        DockerListPane(count: lines.count, loading: loading,
                       empty: DockerView.logs.emptyMessage,
                       symbol: DockerView.logs.symbol,
                       loadingText: "正在读取 Docker 日志", spacing: 0, refresh: refresh) {
            LuckySectionHeader(title: DockerView.logs.title, symbol: DockerView.logs.symbol)
                .padding(.bottom, LuckyTheme.Space.m)
        } rows: {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                DockerLogRow(line: line, first: index == 0)
            }
        }
    }
}

/// One daemon log line. `borderTopWidth = index ? 1 : 0` — the first row has no rule above it, so
/// the block opens flush with the header.
private struct DockerLogRow: View {
    var line: String
    var first: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !first { LuckyHairline() }
            Text(line)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(LuckyTheme.textPrimary)
                // `lineHeight: 17` against a 10 pt line — the extra 7 pt is what keeps a wrapped
                // stack trace legible.
                .lineSpacing(7)
                .textSelection(.enabled)
                .padding(.horizontal, LuckyTheme.Space.m)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LuckyTheme.surface)
    }
}
