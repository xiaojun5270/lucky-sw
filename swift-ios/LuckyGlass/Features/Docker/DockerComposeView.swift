import SwiftUI

/// §12's sixteen verbs, in the exact order the original lays them out.
///
/// Sixteen closures in a struct is what this replaces. Making them a value has a second payoff: the
/// grid becomes a `ForEach` over `allCases`, so the order, the glyphs and the four confirmations
/// cannot drift out of step with each other the way sixteen hand-written buttons can.
enum DockerComposeVerb: String, CaseIterable, Identifiable, Sendable {
    case start, stop, restart, logs
    case backup, backupList, backupDownload, backupsClear, backupUpload
    case backupRestore, backupRemove, backupCancel
    case editConfig, readFile, restoreConfig, dockerfile

    var id: String { rawValue }

    var label: String {
        switch self {
        case .start: "启动"
        case .stop: "停止"
        case .restart: "重启"
        case .logs: "日志"
        case .backup: "备份"
        case .backupList: "备份列表"
        case .backupDownload: "下载备份"
        case .backupsClear: "清空备份"
        case .backupUpload: "上传备份"
        case .backupRestore: "恢复备份"
        case .backupRemove: "删除备份"
        case .backupCancel: "取消备份"
        case .editConfig: "编辑配置"
        case .readFile: "读取文件"
        case .restoreConfig: "恢复配置"
        case .dockerfile: "Dockerfile"
        }
    }

    /// `Play`, `CircleStop`, `RotateCw`, `FileText`, `Save`, `Archive`, `Download`, `Trash2`,
    /// `Upload`, `Pencil`. `Save` is lucide's floppy disk, which reads as a tray on iOS.
    var symbol: String {
        switch self {
        case .start: LuckySymbol.start
        case .stop, .backupCancel: "stop.circle"
        case .restart, .backupRestore, .restoreConfig: LuckySymbol.restart
        case .logs, .readFile, .dockerfile: "doc.text"
        case .backup: "tray.and.arrow.down"
        case .backupList: "archivebox"
        case .backupDownload: LuckySymbol.download
        case .backupsClear, .backupRemove: LuckySymbol.delete
        case .backupUpload: LuckySymbol.upload
        case .editConfig: LuckySymbol.edit
        }
    }

    var tint: Color {
        switch self {
        case .start: LuckyTheme.success
        case .stop, .backupsClear, .backupRemove, .backupCancel: LuckyTheme.danger
        case .restart, .editConfig, .dockerfile: LuckyTheme.accent
        case .logs, .backupDownload, .backupUpload: LuckyTheme.info
        case .backup, .backupRestore, .restoreConfig: LuckyTheme.warning
        case .backupList, .readFile: LuckyTheme.textPrimary
        }
    }

    /// The four verbs that ask first. Every other one either opens a form — which is its own
    /// confirmation — or is harmless.
    func confirmation(_ name: String) -> (title: String, message: String)? {
        switch self {
        case .stop: ("确认停止", "停止 Compose 项目 \(name)？")
        case .backup: ("确认备份", "备份 Compose 项目 \(name)？")
        case .backupsClear: ("清空 Compose 备份", "确定删除项目 \(name) 的全部备份吗？")
        case .backupCancel: ("取消备份", "取消 Compose 项目 \(name) 的备份任务？")
        default: nil
        }
    }
}

/// One Compose row's identity, derived once. Both `keyExtractor` and `renderItem` compute this in
/// the original, from the same three lines.
struct DockerComposeTarget: Hashable, Sendable {
    var key: String
    /// `payload.project_name || key` — what is displayed, and what eight of the sixteen verbs send.
    var name: String
    /// `payload.project_name` — what the other four send, empty or not. Sending `name` there would
    /// invent a project out of a row that never had one.
    var rawName: String
    var path: String

    init(_ item: LuckyListItem, _ index: Int) {
        let payload = DockerRecord.composePayload(item)
        // `[name, path].filter(Boolean).join(":")` — a project with neither falls back to the row's
        // own key, which is why an unnamed entry still gets a stable identity.
        let parts = [payload.name, payload.path].filter { !$0.isEmpty }
        let joined = parts.joined(separator: ":")
        key = joined.isEmpty ? DockerRecord.keyOf(item, index) : joined
        rawName = payload.name
        name = payload.name.isEmpty ? key : payload.name
        path = payload.path
    }

    /// `composePayload(item)` as the four lifecycle mutations send it — both keys always present.
    var payload: JSONValue {
        .object([("project_name", .string(rawName)), ("project_path", .string(path))])
    }

    /// `{ project_name: name }` — the four backup verbs that are keyed by the display name.
    var namePayload: JSONValue {
        .object([("project_name", .string(name))])
    }
}

/// §12 — Compose 项目.
struct DockerComposeView: View {
    var items: [LuckyListItem]
    var loading: Bool
    var busy: Bool
    var refresh: @Sendable () async -> Void
    var scan: () -> Void
    var perform: (DockerComposeVerb, DockerComposeTarget) -> Void

    var body: some View {
        DockerListPane(count: items.count, loading: loading,
                       empty: DockerView.compose.emptyMessage,
                       symbol: DockerView.compose.symbol,
                       loadingText: "正在读取 Compose 项目", refresh: refresh) {
            header
        } rows: {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                DockerComposeCard(target: DockerComposeTarget(item, index), busy: busy,
                                  perform: perform)
            }
        }
    }

    /// 创建 Compose has moved into the glass bar with every other list's primary verb, so 扫描项目
    /// is what is left of the two-button row.
    private var header: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            LuckySectionHeader(title: DockerView.compose.title,
                               symbol: DockerView.compose.symbol) {
                DockerCountChip(count: items.count)
            }
            ServiceActionButton(title: "扫描项目", symbol: LuckySymbol.search, fill: .tinted,
                                height: 46, radius: 12, name: "扫描 Compose 项目", glyph: 17) {
                scan()
            }
        }
    }
}

// MARK: - 项目卡片

private struct DockerComposeCard: View {
    var target: DockerComposeTarget
    var busy: Bool
    var perform: (DockerComposeVerb, DockerComposeTarget) -> Void

    var body: some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            heading
            // `flexBasis 88` with sixteen items: a wrapping grid of equal columns, which is what
            // `flexGrow 1` on every one of them comes to.
            LuckyTileGrid(minimum: 88, spacing: 7) {
                Group {
                    ForEach(DockerComposeVerb.allCases.prefix(8)) { verb in button(verb) }
                }
                Group {
                    ForEach(DockerComposeVerb.allCases.dropFirst(8)) { verb in button(verb) }
                }
            }
        }
    }

    private var heading: some View {
        HStack(spacing: 9) {
            LuckyIconTile(symbol: DockerView.compose.symbol, size: 40, glyph: 20)
            VStack(alignment: .leading, spacing: LuckyTheme.Space.hair) {
                Text(target.name)
                    .font(LuckyTheme.Text.cardTitle)
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .lineLimit(2)
                // The path is what tells two projects of the same name apart, so it is printed even
                // when it is empty — an empty line is itself the answer to "where is this?".
                Text(target.path)
                    .font(.system(size: 11))
                    .foregroundStyle(LuckyTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func button(_ verb: DockerComposeVerb) -> some View {
        DockerIconButton(symbol: verb.symbol, label: verb.label, tint: verb.tint,
                         disabled: busy, fluid: true) {
            perform(verb, target)
        }
    }
}
