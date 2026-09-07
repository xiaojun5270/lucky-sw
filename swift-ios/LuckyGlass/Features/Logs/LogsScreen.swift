import SwiftUI

/// `app/(tabs)/users.tsx` — the file is named `users` but the screen is 运行日志.
///
/// The polling contract is the delicate part: `getGlobalLogBatch(cursor)` every 3 s, but only while
/// the tab is showing *and* the app is foregrounded, and the response decides whether its lines are
/// appended or replace what is on screen. Getting that wrong either duplicates the whole buffer or
/// silently stops updating.
struct LogsScreen: View {
    private static let maxLogLines = 5000

    @Environment(\.luckyNavigator) private var navigator
    @Environment(\.scenePhase) private var phase

    @State private var lines: [String] = []
    @State private var cursor = ""
    @State private var startTime = ""
    @State private var failure = ""
    @State private var fetching = false
    @State private var loaded = false

    /// `logsActive = isFocused && appIsActive`.
    private var active: Bool { navigator.selection == .logs && phase == .active }

    private var scene: LuckySceneDescriptor {
        let health: LuckyHealthState
        if !failure.isEmpty { health = .critical }
        else if !loaded { health = .unknown }
        else if fetching { health = .attention }
        else { health = .nominal }
        return LuckySceneDescriptor(
            module: .logs,
            title: "Lucky 全局日志",
            subtitle: loaded ? "已载入 \(lines.count) 条" : "正在等待实时输出",
            symbol: LuckySymbol.logs,
            tone: .brand,
            health: health
        )
    }

    var body: some View {
        ZStack {
            LuckyBackdrop()
            content
        }
        .luckyTitle("运行日志", "Lucky 全局日志")
        .luckyScene(scene)
        .safeAreaBar(edge: .bottom) { commandDeck }
        // `refetchInterval: 3000` while enabled, cancelled the moment it is not.
        .task(id: active) {
            guard active else { return }
            while !Task.isCancelled {
                await poll()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    /// `scrollable={false}`: the page does not scroll, the list inside it does.
    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            LuckySceneStrip(scene)
            if !failure.isEmpty {
                LuckyErrorCard(message: failure) { Task { await poll() } }
            }
            if lines.isEmpty {
                LuckyDataRail(title: "实时输出", subtitle: "\(lines.count) 条", tone: .idle) {
                    if loaded, failure.isEmpty {
                        LuckyEmptyState(symbol: "terminal", title: "暂无实时日志")
                            .frame(maxHeight: .infinity)
                    } else if !loaded, failure.isEmpty {
                        LuckyLoadingView().frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                LuckyDataRail(title: "实时输出", subtitle: "\(lines.count) 条", tone: .brand) {
                    // `[...lines].reverse()` — newest first, so the interesting line is on screen
                    // without scrolling, and therefore no auto-follow.
                    LuckyLogView(lines: Array(lines.reversed()), follows: false, height: nil)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, LuckyTheme.Space.gutter)
        .padding(.top, LuckyTheme.Space.s)
    }

    private var commandDeck: some View {
        LuckyCommandDeck(
            context: LuckyCommandContext(
                title: fetching ? "正在同步日志" : "3 秒轮询",
                detail: "\(lines.count) 条 · 最多保留 \(Self.maxLogLines) 条",
                symbol: LuckySymbol.logs,
                tone: !failure.isEmpty ? .danger : (active ? .ok : .idle)
            )
        ) {
            LuckyGlassIconButton(symbol: LuckySymbol.refresh, label: "刷新") {
                Task { await poll() }
            }
            .disabled(fetching)
        }
    }

    private func poll() async {
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }
        do {
            let batch = try await LuckyService.globalLogBatch(pre: cursor)
            apply(batch)
            failure = ""
            loaded = true
        } catch {
            guard !error.isCancellation else { return }
            failure = error.luckyMessage()
            loaded = true
        }
    }

    /// The `useEffect` that folds a batch into the visible buffer.
    private func apply(_ batch: LuckyLogBatch) {
        let restarted = batch.reset
            || (!batch.startTime.isEmpty && !startTime.isEmpty && batch.startTime != startTime)
        cursor = batch.cursor
        if !batch.startTime.isEmpty { startTime = batch.startTime }

        // "Nothing new" arrives as an empty incremental page; keeping the current buffer is what
        // stops the list from flickering empty every three seconds.
        if batch.incremental, !restarted, batch.lines.isEmpty { return }
        // A full page identical to what is shown is dropped too, so the rows keep their identity
        // and the user's text selection survives.
        if !batch.incremental, !restarted, lines == batch.lines { return }

        let next = batch.incremental && !restarted ? lines + batch.lines : batch.lines
        lines = next.count > Self.maxLogLines ? Array(next.suffix(Self.maxLogLines)) : next
    }
}
