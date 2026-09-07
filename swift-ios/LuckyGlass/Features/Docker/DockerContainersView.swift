import SwiftUI

/// The six verbs §10's rows dispatch. Handed over rather than reached for, because `private` in
/// Swift is file-scoped and every one of these lives on `DockerScreen`.
struct DockerContainerActions {
    var menu: (DockerContainerMenu) -> Void
    var unpause: (String) -> Void
    var start: (String) -> Void
    var stop: (String, String) -> Void
    var restart: (String, String) -> Void
    var update: (String, String) -> Void
}

/// §10's 容器 list.
struct DockerContainersView: View {
    var items: [LuckyListItem]
    var icons: [JSONValue]
    var stats: [String: DockerStatRow]
    var loading: Bool
    var busy: Bool
    var refresh: @Sendable () async -> Void
    var actions: DockerContainerActions

    var body: some View {
        DockerListPane(count: items.count, loading: loading,
                       empty: DockerView.containers.emptyMessage,
                       symbol: DockerView.containers.symbol,
                       loadingText: "正在读取容器", refresh: refresh) {
            LuckySectionHeader(title: DockerView.containers.title,
                               symbol: DockerView.containers.symbol) {
                DockerCountChip(count: items.count)
            }
        } rows: {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                DockerContainerCard(row: DockerContainerRow(item, index), icons: icons,
                                    stats: stats, busy: busy, actions: actions)
            }
        }
    }
}

// MARK: - 行

/// §10's per-row derivation, done once rather than five times inside the card.
struct DockerContainerRow {
    var item: LuckyListItem
    var key: String
    var state: DockerContainerState
    var name: String
    var displayName: String

    init(_ item: LuckyListItem, _ index: Int) {
        self.item = item
        let key = DockerRecord.keyOf(item, index)
        self.key = key
        state = DockerStats.containerState(item)
        // `key.slice(0, 12)` — a container with no name at all is known by the head of its id.
        let fallback = String(key.prefix(12))
        let name = DockerRecord.pick(item, ["Names", "Name", "name"], fallback)
        self.name = name
        // `name.replace(/^\/+/, "") || name` — a name of nothing but slashes keeps them.
        let bare = String(name.drop { $0 == "/" })
        displayName = bare.isEmpty ? name : bare
    }

    /// §25.2 — a paused container is still a running one for every purpose but its own verb.
    var paused: Bool { state == .paused }
    var running: Bool { state == .running || paused }

    /// The list and the statistics endpoint rarely agree on which of the two they print, so both
    /// are tried. §25.1's map holds every row under each.
    func stats(_ table: [String: DockerStatRow]) -> DockerStatRow? {
        table[key] ?? table[displayName]
    }

    var status: String {
        DockerRecord.containerStatus(item, running: running, paused: paused)
    }

    var menu: DockerContainerMenu {
        DockerContainerMenu(key: key, name: name, running: running, paused: paused)
    }
}

// MARK: - 卡片

private struct DockerContainerCard: View {
    var row: DockerContainerRow
    var icons: [JSONValue]
    var stats: [String: DockerStatRow]
    var busy: Bool
    var actions: DockerContainerActions

    var body: some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            Button {
                actions.menu(row.menu)
            } label: {
                heading
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开容器 \(row.displayName) 操作菜单")
            ContainerStatsGrid(stats: row.stats(stats))
            LuckyHairline()
            commands
        }
    }

    private var heading: some View {
        HStack(spacing: 11) {
            ContainerArtwork(item: row.item, icons: icons, running: row.running, size: 48)
            VStack(alignment: .leading, spacing: LuckyTheme.Space.xs + 2) {
                Text(row.displayName)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                badge
            }
            // The 34×34 ellipsis affordance. The whole row is the button, so this only has to look
            // like one.
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LuckyTheme.textSecondary)
                .frame(width: 34, height: 34)
                .background(LuckyTheme.surfaceRaised, in: .rect(cornerRadius: 11))
        }
        .frame(minHeight: 54)
    }

    /// The status pill: a 6 pt dot and the uptime phrase, tinted by whether the container is up.
    private var badge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(row.running ? LuckyTheme.success : LuckyTheme.idleSoft)
                .frame(width: 6, height: 6)
            Text(row.status)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(row.running ? LuckyTheme.success : LuckyTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, LuckyTheme.Space.s)
        .frame(minHeight: 24)
        .background(row.running ? LuckyTheme.successSoft : LuckyTheme.surfaceRaised,
                    in: .rect(cornerRadius: 8))
    }

    /// Three buttons, the first of which depends on the state. 恢复 and 启动 ask nothing; 停止 and
    /// 重启 both confirm, and both interpolate the **raw** name, leading slash and all.
    private var commands: some View {
        HStack(spacing: 6) {
            if row.paused {
                ContainerCommandButton(symbol: LuckySymbol.start, label: "恢复",
                                       tint: LuckyTheme.success, disabled: busy) {
                    actions.unpause(row.key)
                }
            } else if !row.running {
                ContainerCommandButton(symbol: LuckySymbol.start, label: "启动",
                                       tint: LuckyTheme.success, disabled: busy) {
                    actions.start(row.key)
                }
            } else {
                ContainerCommandButton(symbol: LuckySymbol.stop, label: "停止",
                                       tint: LuckyTheme.danger, disabled: busy) {
                    actions.stop(row.key, row.name)
                }
            }
            ContainerCommandButton(symbol: LuckySymbol.restart, label: "重启",
                                   tint: LuckyTheme.accent, disabled: busy) {
                actions.restart(row.key, row.name)
            }
            ContainerCommandButton(symbol: "icloud.and.arrow.up", label: "更新",
                                   tint: LuckyTheme.info, disabled: busy) {
                actions.update(row.key, row.displayName)
            }
        }
    }
}
