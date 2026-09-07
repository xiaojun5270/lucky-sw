import SwiftUI

/// Which Docker list a summary tile jumps to. The `rawValue` is exactly what
/// `LuckyRoute.docker(view:)` carries, matching the original's
/// `router.push({ pathname: "/docker", params: { view } })`.
enum DockerOverviewTarget: String, Sendable, CaseIterable {
    case containers
    case images
    case compose
    case networks
    case volumes
}

enum DockerResourcePresentation: Sendable {
    case cards
    case telemetry
}

/// Display-only formatting for the Docker surfaces. `DockerStats` parses; this prints.
enum DockerText {
    /// `formatPercent` — an absent or non-finite reading is a dash, never `0.0%`, because
    /// "not measured" and "idle" are different facts.
    static func percent(_ value: Double?, digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "--" }
        return JSCompat.toFixed(value, digits) + "%"
    }

    /// `count` — `undefined` means the endpoint was unavailable, `0` means it answered zero.
    static func count(_ value: Int?) -> String {
        guard let value else { return "--" }
        return String(value)
    }

    static func count(_ value: Double?) -> String {
        guard let value else { return "--" }
        return JSONSerializer.numberString(value)
    }
}

// MARK: - Live resource cards

/// One resource plate: an icon, a title, two labelled readings and a 270° gauge.
///
/// `percent` drives the gauge and `value` prints inside it, separately, because the gauge must
/// draw an empty track when there is no reading while the label says `连接中` instead of a
/// number.
private struct DockerResourceCard: View {
    var title: String
    var symbol: String
    var tone: LuckyTone
    var primaryLabel: String
    var primaryValue: String
    var secondaryLabel: String
    var secondaryValue: String
    var percent: Double?
    var digits: Int

    var body: some View {
        LuckyCard {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: LuckyTheme.Space.s) {
                        LuckyIconTile(symbol: symbol, size: 32, glyph: 16, tone: tone)
                        Text(title)
                            .font(LuckyTheme.Text.cardTitle)
                            .foregroundStyle(LuckyTheme.textPrimary)
                    }
                    VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
                        reading(primaryLabel, primaryValue,
                                font: LuckyTheme.Text.captionMedium,
                                color: LuckyTheme.textPrimary)
                        reading(secondaryLabel, secondaryValue,
                                font: LuckyTheme.Text.bodyMedium,
                                color: tone.tint)
                    }
                }
                Spacer(minLength: LuckyTheme.Space.xs)
                LuckyArcGauge(
                    label: DockerText.percent(percent, digits: digits),
                    percent: percent,
                    tone: tone,
                    size: 88
                )
            }
            .frame(minHeight: 116)
        }
    }

    private func reading(_ label: String, _ value: String,
                         font: Font, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LuckyTheme.Space.s) {
            Text(label)
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textTertiary)
            Spacer(minLength: LuckyTheme.Space.xs)
            Text(value)
                .font(font)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

/// `DockerLiveResourceCards` — the host's CPU and memory, read from the status socket rather
/// than from the Docker API, with `docker info` supplying the totals the socket does not carry.
///
/// The original creates its own socket when no `liveStatus` is handed down; here the store is a
/// single reference-counted instance, so the caller has already retained it and this view only
/// reads.
struct DockerResourceCards: View {
    var info: JSONValue
    var active: Bool
    var live: LuckyStatusStore
    var presentation: DockerResourcePresentation = .cards

    private var hasLiveData: Bool { active && live.connected && live.data != nil }

    private var cpuCount: Double? {
        JSONUnwrap.deepNumber(info, keys: ["NCPU", "Ncpu", "CPUCount", "cpuCount", "NumCPU"])
    }

    /// `(hasLiveData ? live.data?.totalMem : 0) || parseDockerBytes(...)` — a zero or absent
    /// socket reading falls through to `docker info`, which reports a string such as
    /// `"15.55GiB"`.
    private var totalMemory: Double? {
        if hasLiveData, let reported = live.data?.totalMem, reported.isFinite, reported != 0 {
            return reported
        }
        let raw = DockerStats.value(info, ["MemTotal", "memTotal", "TotalMemory", "totalMemory"])
        return DockerStats.parseBytes(raw)
    }

    private var cpuUsage: Double? {
        guard hasLiveData, let usage = live.data?.usedCpu, usage.isFinite else { return nil }
        return usage
    }

    private var memoryUsage: Double? { hasLiveData ? live.data?.usedMem : nil }

    private var memoryPercent: Double? {
        guard let memoryUsage, let totalMemory, totalMemory > 0 else { return nil }
        return memoryUsage / totalMemory * 100
    }

    /// What stands in for a percentage while there is no frame — an interrupted socket says so
    /// rather than pretending to still be connecting.
    private var connectionValue: String {
        live.error.isEmpty ? "连接中" : "连接中断"
    }

    private var cpuCountValue: String {
        guard let cpuCount else { return "--" }
        return String(Int(cpuCount.rounded()))
    }

    private var totalMemoryValue: String {
        guard let totalMemory, totalMemory > 0 else { return "--" }
        return Format.bytes(totalMemory)
    }

    var body: some View {
        Group {
            switch presentation {
            case .cards:
                LuckyTileGrid(minimum: 300, spacing: LuckyTheme.Space.m) {
                    cpuCard
                    memoryCard
                }
            case .telemetry:
                LuckyTelemetryDeck(title: "Docker 宿主机", subtitle: connectionValue,
                                   tone: .warning) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: LuckyTheme.Space.l) {
                            telemetryReadings
                        }
                        VStack(spacing: LuckyTheme.Space.l) {
                            telemetryReadings
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var telemetryReadings: some View {
        LuckyTelemetryReading(label: "逻辑核心", value: cpuCountValue,
                              detail: "Docker 运行时", symbol: LuckySymbol.cpu, tone: .brand)
        LuckyTelemetryReading(
            label: "CPU 使用率",
            value: cpuUsage == nil ? connectionValue : DockerText.percent(cpuUsage, digits: 2),
            detail: "来自实时状态流",
            symbol: "gauge.with.dots.needle.33percent",
            tone: .brand
        )
        LuckyTelemetryReading(label: "总内存", value: totalMemoryValue,
                              detail: "宿主机可用", symbol: LuckySymbol.memory, tone: .ok)
        LuckyTelemetryReading(
            label: "内存使用率",
            value: memoryPercent == nil ? connectionValue : DockerText.percent(memoryPercent),
            detail: "实时使用 / 总内存",
            symbol: "chart.bar.fill",
            tone: .ok
        )
    }

    private var cpuCard: some View {
        DockerResourceCard(
            title: "CPU",
            symbol: LuckySymbol.cpu,
            tone: .brand,
            primaryLabel: "逻辑核心",
            primaryValue: cpuCountValue,
            secondaryLabel: "使用率 (%)",
            secondaryValue: cpuUsage == nil
                ? connectionValue
                : DockerText.percent(cpuUsage, digits: 2),
            percent: cpuUsage,
            digits: 2
        )
    }

    private var memoryCard: some View {
        DockerResourceCard(
            title: "内存",
            symbol: LuckySymbol.memory,
            tone: .ok,
            primaryLabel: "总可用内存",
            primaryValue: totalMemoryValue,
            secondaryLabel: "使用率 (%)",
            secondaryValue: memoryPercent == nil
                ? connectionValue
                : DockerText.percent(memoryPercent, digits: 1),
            percent: memoryPercent,
            digits: 1
        )
    }
}

// MARK: - Summary tiles

/// One tappable count. `value`, `suffix` and `badge` arrive already formatted so the tile never
/// has to know whether a dash means "unavailable" or "zero".
private struct DockerSummaryTile: View {
    var label: String
    var value: String
    var suffix: String? = nil
    var badge: String? = nil
    var symbol: String
    var tint: Color
    var fill: Color
    var valueColor: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
                HStack(alignment: .firstTextBaseline, spacing: LuckyTheme.Space.xs) {
                    Text(value)
                        .font(LuckyTheme.Text.metricSmall)
                        .foregroundStyle(valueColor ?? LuckyTheme.textPrimary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let suffix, !suffix.isEmpty {
                        Text(suffix)
                            .font(LuckyTheme.Text.captionMedium)
                            .foregroundStyle(LuckyTheme.textTertiary)
                            .monospacedDigit()
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text(label)
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textTertiary)
                    .lineLimit(1)
                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(LuckyTheme.Text.captionMedium)
                        .foregroundStyle(LuckyTheme.textTertiary)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule(style: .continuous).fill(LuckyTheme.surfaceRaised))
                }
            }
            .frame(minHeight: 72, alignment: .topLeading)
        }
        .buttonStyle(LuckyCardButtonStyle(radius: 16, padding: LuckyTheme.Space.m))
        .accessibilityLabel("查看\(label)")
    }
}

/// The five counts from `getDockerOverview`, in the original's order. Each one is a door into
/// the Docker screen's matching list.
struct DockerSummaryGrid: View {
    var data: DockerOverview?
    var onSelectView: (DockerOverviewTarget) -> Void

    /// `statusValue` — the running count only means something once the container list itself
    /// came back, so an unavailable endpoint shows a dash rather than `0`.
    private func statusValue(_ value: Int) -> String {
        (data?.containersAvailable ?? false) ? String(value) : "--"
    }

    private var runningCount: Int {
        (data?.containers ?? []).reduce(into: 0) { total, item in
            if DockerStats.containerState(item) == .running { total += 1 }
        }
    }

    private var containerSuffix: String? {
        guard let total = data?.containerCount else { return nil }
        return " / " + JSONSerializer.numberString(total)
    }

    private var imageBadge: String? {
        guard let size = data?.imageSize else { return nil }
        return size > 0 ? Format.bytes(size) : "0 B"
    }

    var body: some View {
        LuckyTileGrid(minimum: 132) {
            DockerSummaryTile(
                label: "Compose",
                value: DockerText.count(data?.composeCount),
                symbol: "square.stack.3d.down.right",
                tint: LuckyTheme.textTertiary,
                fill: LuckyTheme.surfaceRaised,
                action: { onSelectView(.compose) }
            )
            DockerSummaryTile(
                label: "容器",
                value: statusValue(runningCount),
                suffix: containerSuffix,
                symbol: "shippingbox",
                tint: LuckyTheme.accent,
                fill: LuckyTheme.accentSoft,
                valueColor: LuckyTheme.success,
                action: { onSelectView(.containers) }
            )
            DockerSummaryTile(
                label: "镜像列表",
                value: DockerText.count(data?.imageCount),
                badge: imageBadge,
                symbol: "photo.on.rectangle.angled",
                tint: LuckyTheme.violet,
                fill: LuckyTheme.violetSoft,
                action: { onSelectView(.images) }
            )
            DockerSummaryTile(
                label: "数据卷",
                value: DockerText.count(data?.volumeCount),
                symbol: "externaldrive",
                tint: LuckyTheme.success,
                fill: LuckyTheme.successSoft,
                action: { onSelectView(.volumes) }
            )
            DockerSummaryTile(
                label: "网络",
                value: DockerText.count(data?.networkCount),
                symbol: LuckySymbol.network,
                tint: LuckyTheme.info,
                fill: LuckyTheme.infoSoft,
                action: { onSelectView(.networks) }
            )
        }
    }
}

// MARK: - Container states

/// A dot, a name and a count. Bordered rather than filled, so five of them in a row read as a
/// legend instead of five buttons.
private struct DockerStateChip: View {
    var label: String
    var value: String
    var tone: LuckyTone

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.tint)
                .frame(width: 6, height: 6)
            Text(label)
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textTertiary)
            Text(value)
                .font(LuckyTheme.Text.captionMedium)
                .foregroundStyle(LuckyTheme.textPrimary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 32)
        .background(Capsule(style: .continuous).fill(LuckyTheme.surface))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth)
        )
    }
}

/// The 容器状态 strip. Counts come from the container list, so they show a dash until that list
/// arrives — except 其它, which only appears at all when something landed in it.
struct DockerStateStrip: View {
    var states: [DockerContainerState: Int]
    var available: Bool

    private func value(_ state: DockerContainerState) -> String {
        available ? String(states[state] ?? 0) : "--"
    }

    var body: some View {
        LuckyInset(padding: LuckyTheme.Space.m) {
            LuckyWrap(spacing: LuckyTheme.Space.s, lineSpacing: LuckyTheme.Space.s) {
                Text("容器状态")
                    .font(LuckyTheme.Text.captionMedium)
                    .foregroundStyle(LuckyTheme.textPrimary)
                DockerStateChip(label: "运行中", value: value(.running), tone: .ok)
                DockerStateChip(label: "已暂停", value: value(.paused), tone: .warning)
                DockerStateChip(label: "已退出", value: value(.exited), tone: .danger)
                DockerStateChip(label: "已创建", value: value(.created), tone: .brand)
                if (states[.other] ?? 0) > 0 {
                    DockerStateChip(
                        label: "其它",
                        value: String(states[.other] ?? 0),
                        tone: .idle
                    )
                }
            }
        }
    }
}

// MARK: - Rankings

/// The original's `opacity: pressed ? 0.65 : 1`. `.plain` would swallow the press feedback and a
/// card style would draw a plate inside a plate.
private struct DockerRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(LuckyTheme.Motion.snap, value: configuration.isPressed)
    }
}

/// Top five containers by one metric. The bar is relative: CPU is already a percentage, while
/// memory falls back to a share of the largest row when the daemon reports no percentage — and
/// note that the *colour* always comes from `memoryPercent`, even in that fallback.
struct DockerRankingCard: View {
    enum Mode: Sendable { case cpu, memory }

    var title: String
    var tone: LuckyTone
    var rows: [DockerStatRow]
    var mode: Mode
    var emptyMessage: String
    var onSelectContainer: (String) -> Void

    /// `Math.max(1, ...rows.map(row => row.memory))` — over the already-sliced rows, so each
    /// card scales against its own top entry.
    private var memoryMax: Double { max(1, rows.map(\.memory).max() ?? 0) }

    var body: some View {
        LuckyCard(spacing: LuckyTheme.Space.s) {
            HStack(spacing: LuckyTheme.Space.s) {
                LuckyIconTile(
                    symbol: mode == .cpu ? LuckySymbol.cpu : LuckySymbol.memory,
                    size: 32,
                    glyph: 16,
                    tone: tone
                )
                Text(title)
                    .font(LuckyTheme.Text.cardTitle)
                    .foregroundStyle(LuckyTheme.textPrimary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 28)
            if rows.isEmpty {
                Text(emptyMessage)
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 92)
            } else {
                VStack(spacing: 0) {
                    header
                    ForEach(rows.indices, id: \.self) { index in
                        entry(index: index, row: rows[index])
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("#")
                .frame(width: 18)
            Text("容器名称")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(mode == .cpu ? "使用率 (%)" : "内存占用")
                .frame(minWidth: 62, alignment: .trailing)
        }
        .font(LuckyTheme.Text.caption)
        .foregroundStyle(LuckyTheme.textTertiary)
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private func entry(index: Int, row: DockerStatRow) -> some View {
        LuckyHairline()
        Button {
            onSelectContainer(row.name)
        } label: {
            HStack(spacing: LuckyTheme.Space.s) {
                Text(String(index + 1))
                    .font(LuckyTheme.Text.captionMedium)
                    .foregroundStyle(rankColor(index))
                    .monospacedDigit()
                    .frame(width: 18)
                Text(row.name)
                    .font(LuckyTheme.Text.captionMedium)
                    .foregroundStyle(LuckyTheme.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                bar(row)
                Text(valueText(row))
                    .font(LuckyTheme.Text.captionMedium)
                    .foregroundStyle(LuckyTheme.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(minWidth: 62, alignment: .trailing)
            }
            .frame(minHeight: 48)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(DockerRowButtonStyle())
        .accessibilityLabel("查看容器 \(row.name)")
    }

    private func rankColor(_ index: Int) -> Color {
        switch index {
        case 0: LuckyTheme.danger
        case 1: LuckyTheme.warning
        default: LuckyTheme.textTertiary
        }
    }

    private func bar(_ row: DockerStatRow) -> some View {
        let fraction = min(100, max(0, barPercent(row))) / 100
        return ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(LuckyTheme.surfaceRaised)
            Capsule(style: .continuous)
                .fill(barTone(row).tint)
                .frame(width: 70 * fraction)
        }
        .frame(width: 70, height: 6)
        .animation(LuckyTheme.Motion.snap, value: fraction)
    }

    private func barPercent(_ row: DockerStatRow) -> Double {
        if mode == .cpu { return min(100, max(0, row.cpu)) }
        if row.hasMemoryPercent { return min(100, max(0, row.memoryPercent)) }
        return row.memory / memoryMax * 100
    }

    private func barTone(_ row: DockerStatRow) -> LuckyTone {
        if mode == .cpu {
            if row.cpu >= 80 { return .danger }
            return row.cpu >= 50 ? .warning : .brand
        }
        if row.memoryPercent >= 80 { return .danger }
        return row.memoryPercent >= 60 ? .warning : .ok
    }

    private func valueText(_ row: DockerStatRow) -> String {
        if mode == .cpu { return DockerText.percent(row.cpu, digits: 1) }
        return row.memory > 0 ? Format.bytes(row.memory) : "0 B"
    }
}

// MARK: - Dashboard

/// `DockerOverviewDashboard` — the block shared by the 总览 tab and the Docker screen. The three
/// flags are how the original splits it: the dashboard tab shows the live resource cards alone,
/// while the Docker screen adds the section header, the five counts and the container insights.
struct DockerOverviewDashboard: View {
    var data: DockerOverview?
    var active: Bool
    var live: LuckyStatusStore
    var stats: JSONValue? = nil
    var statsLoading: Bool = false
    var statsError: String = ""
    var showHeader: Bool = true
    var showDockerSummary: Bool = true
    var showContainerInsights: Bool = true
    var resourcePresentation: DockerResourcePresentation = .cards
    var onSelectView: (DockerOverviewTarget) -> Void
    var onSelectContainer: (String) -> Void

    private var containers: [JSONValue] { data?.containers ?? [] }

    /// Counted over every state so a missing key never has to mean zero at the call site.
    private var states: [DockerContainerState: Int] {
        var counts: [DockerContainerState: Int] = [:]
        for state in DockerContainerState.allCases { counts[state] = 0 }
        for item in containers { counts[DockerStats.containerState(item), default: 0] += 1 }
        return counts
    }

    private var rankingEmpty: String {
        if !statsError.isEmpty { return "容器统计暂不可用" }
        return statsLoading ? "正在读取容器统计" : "暂无容器统计数据"
    }

    /// The five rows one card ranks. Ties keep their original order, because `Array.sort` is
    /// stable in JavaScript and `sorted(by:)` is not.
    private func top(
        _ rows: [DockerStatRow],
        _ include: (DockerStatRow) -> Bool,
        _ metric: (DockerStatRow) -> Double
    ) -> [DockerStatRow] {
        rows.enumerated()
            .filter { include($0.element) }
            .sorted { lhs, rhs in
                let left = metric(lhs.element)
                let right = metric(rhs.element)
                return left == right ? lhs.offset < rhs.offset : left > right
            }
            .prefix(5)
            .map { $0.element }
    }

    var body: some View {
        // Walked once per render rather than once per ranking card: the stats payload is a tree,
        // and the live socket redraws this view every second.
        let rows = showContainerInsights
            ? DockerStats.rows(stats, containers: containers)
            : []
        return VStack(alignment: .leading, spacing: LuckyTheme.Space.l) {
            if showHeader {
                LuckySectionHeader(title: "Docker 总览", symbol: LuckySymbol.dashboard)
            }
            DockerResourceCards(info: data?.info ?? .object([]), active: active, live: live,
                                presentation: resourcePresentation)
            if showDockerSummary {
                DockerSummaryGrid(data: data, onSelectView: onSelectView)
            }
            if showContainerInsights {
                DockerStateStrip(states: states, available: data?.containersAvailable ?? false)
                LuckyTileGrid(minimum: 320, spacing: LuckyTheme.Space.m) {
                    DockerRankingCard(
                        title: "CPU 使用率前 5",
                        tone: .brand,
                        rows: top(rows, { $0.hasCpu }, { $0.cpu }),
                        mode: .cpu,
                        emptyMessage: rankingEmpty,
                        onSelectContainer: onSelectContainer
                    )
                    DockerRankingCard(
                        title: "内存使用率前 5",
                        tone: .ok,
                        rows: top(rows, { $0.hasMemory }, { $0.memory }),
                        mode: .memory,
                        emptyMessage: rankingEmpty,
                        onSelectContainer: onSelectContainer
                    )
                }
            }
        }
    }
}
