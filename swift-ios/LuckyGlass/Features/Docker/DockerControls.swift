import SwiftUI

/// §5's four row-level sub-components, plus the scroll every non-list view sits in.

// MARK: - 容器图标

/// §5.1's `ContainerArtwork`. The library serves its artwork from an endpoint that wants the admin
/// token, and `AsyncImage` cannot set a header, so the fetch is a `URLSession` call of its own.
///
/// An icon whose path is already a URL (`http:`, `data:`, `file:`) came from the container's own
/// labels rather than the library, and must be fetched *without* the token attached.
@MainActor
final class DockerIconLoader {
    static let shared = DockerIconLoader()

    /// `cachePolicy="memory-disk"` — the memory half. A container list re-renders on every
    /// five-second stats tick, so an uncached loader would re-fetch the whole grid each time.
    private var cache: [String: Image] = [:]
    /// The paths already known to fail, so `failed` never retries in a loop.
    private var failures: Set<String> = []
    private var running: Set<String> = []

    private init() {}

    func cached(_ icon: String) -> Image? { cache[icon] }

    func failed(_ icon: String) -> Bool { failures.contains(icon) }

    /// Resolves the icon path, fetches it once, and caches the result. Concurrent callers for the
    /// same path — which is every visible row asking at once — collapse into the first request.
    func load(_ icon: String) async {
        guard !icon.isEmpty, cache[icon] == nil, !failures.contains(icon),
              !running.contains(icon) else { return }
        running.insert(icon)
        defer { running.remove(icon) }
        guard let request = await Self.request(for: icon) else {
            failures.insert(icon)
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard status < 400, let image = UIImage(data: data) else {
                failures.insert(icon)
                return
            }
            cache[icon] = Image(uiImage: image)
        } catch {
            // `onError={() => setFailed(true)}` — the glyph stands in and nothing is reported.
            failures.insert(icon)
        }
    }

    /// `${baseUrl}/api/iconlib/icon?path=…` with the admin token, or the icon's own URL bare.
    private static func request(for icon: String) async -> URLRequest? {
        if DockerRecord.isExternalIcon(icon) {
            guard let url = URL(string: icon) else { return nil }
            return URLRequest(url: url)
        }
        let credentials = await LuckyClient.shared.snapshot
        let base = credentials.baseUrl.jsTrimmed.withoutTrailingSlashes
        guard !base.isEmpty else { return nil }
        let query = JSCompat.encodeURIComponent(icon)
        guard let url = URL(string: "\(base)/api/iconlib/icon?path=\(query)") else { return nil }
        var request = URLRequest(url: url)
        if !credentials.token.isEmpty {
            request.setValue(credentials.token, forHTTPHeaderField: "Lucky-Admin-Token")
        }
        return request
    }
}

/// §5.1. Drawn at 48 pt in the containers list, which is the only place it appears.
struct ContainerArtwork: View {
    var item: LuckyListItem
    var icons: [JSONValue]
    var running: Bool
    var size: CGFloat = 44

    @State private var image: Image?

    private var icon: String { DockerRecord.containerIcon(item, icons) }

    /// `borderRadius: Math.max(10, Math.round(size * 0.26))`
    private var radius: CGFloat { max(10, (size * 0.26).rounded()) }

    var body: some View {
        ZStack {
            if let image {
                // `contentFit="contain"` inside a frame 6 pt smaller than the tile.
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: size - 6, height: size - 6)
            } else {
                Image(systemName: LuckySymbol.docker)
                    .font(.system(size: (size * 0.45).rounded(), weight: .semibold))
                    .foregroundStyle(running ? LuckyTheme.accent : LuckyTheme.idleSoft)
            }
        }
        .frame(width: size, height: size)
        .background(background, in: .rect(cornerRadius: radius))
        .clipShape(.rect(cornerRadius: radius))
        // `failed` resets whenever the URI changes, which the id does for us.
        .task(id: icon) { await resolve() }
        .accessibilityHidden(true)
    }

    /// The fallback tints itself by state; the image sits on the plain raised surface.
    private var background: Color {
        if image != nil { return LuckyTheme.surfaceRaised }
        return running ? LuckyTheme.accentSoft : LuckyTheme.surfaceRaised
    }

    private func resolve() async {
        image = nil
        let path = icon
        guard !path.isEmpty else { return }
        if let cached = DockerIconLoader.shared.cached(path) {
            image = cached
            return
        }
        await DockerIconLoader.shared.load(path)
        // A second row may have finished the fetch while this one waited.
        guard path == icon else { return }
        image = DockerIconLoader.shared.cached(path)
    }
}

// MARK: - 统计网格

/// §5.2's `ContainerStatsGrid` — three tiles of two metrics, wrapping as the width allows.
struct ContainerStatsGrid: View {
    var stats: DockerStatRow?

    var body: some View {
        LuckyTileGrid(minimum: 145, spacing: 6) {
            tile(
                Metric("CPU", LuckySymbol.cpu, LuckyTheme.accent, cpu),
                Metric("内存", LuckySymbol.memory, LuckyTheme.success, memory)
            )
            tile(
                Metric("下载", LuckySymbol.download, LuckyTheme.info,
                       bytes(\.networkRx, \.hasNetworkRx)),
                Metric("上传", LuckySymbol.upload, LuckyTheme.warning,
                       bytes(\.networkTx, \.hasNetworkTx))
            )
            tile(
                Metric("读取", "internaldrive.fill", LuckyTheme.textSecondary,
                       bytes(\.blockRead, \.hasBlockRead)),
                Metric("写入", "internaldrive", LuckyTheme.textSecondary,
                       bytes(\.blockWrite, \.hasBlockWrite))
            )
        }
    }

    /// One label-and-value pair.
    private struct Metric {
        var label: String
        var symbol: String
        var tint: Color
        var value: String

        init(_ label: String, _ symbol: String, _ tint: Color, _ value: String) {
            self.label = label
            self.symbol = symbol
            self.tint = tint
            self.value = value
        }
    }

    private func tile(_ first: Metric, _ second: Metric) -> some View {
        HStack(spacing: 0) {
            cell(first)
            // `borderLeftWidth: 1` on the second cell only.
            Rectangle()
                .fill(LuckyTheme.separator)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            cell(second)
        }
        .frame(minHeight: 54)
        .padding(LuckyTheme.Space.s)
        .background(LuckyTheme.surfaceRaised, in: .rect(cornerRadius: 12))
    }

    private func cell(_ metric: Metric) -> some View {
        VStack(spacing: LuckyTheme.Space.xs) {
            HStack(spacing: LuckyTheme.Space.xs) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 12, weight: .bold))
                Text(metric.label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(LuckyTheme.textSecondary)
            Text(metric.value)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LuckyTheme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                // `adjustsFontSizeToFit` + `minimumFontScale 0.75`.
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, LuckyTheme.Space.xs)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.label) \(metric.value)")
    }

    /// `hasCpu ? cpu.toFixed(1)+"%" : "-"`
    private var cpu: String {
        guard let stats, stats.hasCpu else { return "-" }
        return JSCompat.toFixed(stats.cpu, 1) + "%"
    }

    /// The percentage when the daemon reported one, the absolute figure when it only reported
    /// bytes, and a dash when it reported neither.
    private var memory: String {
        guard let stats else { return "-" }
        if stats.hasMemoryPercent { return JSCompat.toFixed(stats.memoryPercent, 1) + "%" }
        if stats.hasMemory { return DockerRecord.compactBytes(stats.memory, true) }
        return "-"
    }

    /// `compactDockerBytes(value ?? 0, hasX === true)` — a missing metric prints `N/A`, a present
    /// zero prints `0 B`, which is the whole point of carrying the `has` flags alongside.
    private func bytes(_ value: KeyPath<DockerStatRow, Double>,
                       _ present: KeyPath<DockerStatRow, Bool>) -> String {
        guard let stats else { return DockerRecord.compactBytes(0, false) }
        return DockerRecord.compactBytes(stats[keyPath: value], stats[keyPath: present])
    }
}

// MARK: - 行内按钮

/// §5.3's `IconButton` — the bordered verb button every Docker row is built from. Not glass: these
/// live inside the scroll, where glass may not go.
struct DockerIconButton: View {
    var symbol: String
    var label: String
    var tint: Color
    var disabled: Bool = false
    /// `fluid` — a button that shares the row's width rather than hugging its label.
    var fluid: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(minWidth: 64, minHeight: 42)
            .frame(maxWidth: fluid ? .infinity : nil)
            .background(LuckyTheme.surfaceRaised, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(LuckyTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityLabel(label)
    }
}

/// §5.4's `ContainerCommandButton` — the same shape, always sharing the row equally, with a
/// slightly smaller glyph and a slightly larger label.
struct ContainerCommandButton: View {
    var symbol: String
    var label: String
    var tint: Color
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 42)
            .background(LuckyTheme.surfaceRaised, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(LuckyTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        .accessibilityLabel(label)
    }
}

// MARK: - 面板滚动

/// The scroll 总览 and 设置 sit in. §6's list views take `DockerListPane` below; these two are
/// `ScrollView`s in the original too, and share its 98 pt bottom inset so the glass bar never
/// covers the last card.
struct DockerPaneScroll<Content: View>: View {
    var spacing: CGFloat = LuckyTheme.Space.l
    /// `<Page refreshing onRefresh>` — the scrollable page has pull to refresh just as the lists
    /// do, so 总览, 设置 and 日志's Mode A all get it here.
    var refresh: @Sendable () async -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .padding(.horizontal, LuckyTheme.Space.gutter)
            .padding(.top, LuckyTheme.Space.xs)
            .padding(.bottom, 98)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await refresh() }
    }
}

/// §6's shared `FlatList` config, as the one shape all six list views and 日志 share: a header that
/// scrolls with the rows, a 12 pt separator between them, the 98 pt bottom inset, and pull to
/// refresh. `initialNumToRender` / `windowSize` have no counterpart — `LazyVStack` decides for
/// itself how far ahead to build — and the tab bar, the search box and the error cards have moved
/// out of `ListHeaderComponent` into the pinned chrome, because glass may not scroll.
///
/// The empty and loading branches replace the rows and not the header: §10 through §15 all draw
/// their `SectionHeader` first and their `EmptyState` under it, and `flexGrow: data.length ? 0 : 1`
/// is what centres the latter in the space left over.
struct DockerListPane<Header: View, Rows: View>: View {
    var count: Int
    var loading: Bool
    /// `<EmptyState message>` — `DockerView.emptyMessage`.
    var empty: String
    var symbol: String
    /// The original renders nothing at all while the first page is in flight; a spinner with the
    /// view's own sentence reads better and costs nothing (§25.15).
    var loadingText: String
    /// 12 px in the original. 日志 passes 0 — it has no separator.
    var spacing: CGFloat = LuckyTheme.Space.m
    var refresh: @Sendable () async -> Void
    @ViewBuilder var header: () -> Header
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: spacing) {
                header()
                if loading {
                    LuckyLoadingView(text: loadingText)
                } else if count == 0 {
                    LuckyEmptyState(symbol: symbol, title: empty)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LuckyTheme.Space.xl)
                } else {
                    rows()
                }
            }
            .padding(.horizontal, LuckyTheme.Space.gutter)
            .padding(.top, LuckyTheme.Space.xs)
            .padding(.bottom, 98)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollIndicators(.hidden)
        // `keyboardShouldPersistTaps="handled"` is RN's default-fighting flag; the iOS equivalent
        // is letting a drag dismiss the search keyboard rather than swallowing the first tap.
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await refresh() }
    }
}

/// The `N 项` count every list header carries in its `meta` slot.
struct DockerCountChip: View {
    var count: Int

    var body: some View {
        Text("\(count) 项")
            .font(LuckyTheme.Text.caption)
            .foregroundStyle(LuckyTheme.textSecondary)
            .monospacedDigit()
    }
}
