import SwiftUI

/// §14's eight verbs. Every one of them is keyed by the volume's **name** and not by `keyOf` — the
/// daemon's volume endpoints take a name, and the row's index has no meaning to them.
enum DockerVolumeVerb: String, CaseIterable, Identifiable, Sendable {
    case backup, backupList, export, backupUpload
    case backupRestore, backupRemove, backupCancel, remove

    var id: String { rawValue }

    var label: String {
        switch self {
        case .backup: "备份"
        case .backupList: "备份列表"
        case .export: "导出"
        case .backupUpload: "上传备份"
        case .backupRestore: "恢复备份"
        case .backupRemove: "删除备份"
        case .backupCancel: "取消备份"
        case .remove: "删除"
        }
    }

    var symbol: String {
        switch self {
        case .backup: "tray.and.arrow.down"
        case .backupList: LuckySymbol.search
        case .export: LuckySymbol.download
        case .backupUpload: LuckySymbol.upload
        case .backupRestore: LuckySymbol.restart
        case .backupRemove, .remove: LuckySymbol.delete
        case .backupCancel: "stop.circle"
        }
    }

    var tint: Color {
        switch self {
        case .backup: LuckyTheme.accent
        case .backupList: LuckyTheme.textPrimary
        case .export, .backupUpload: LuckyTheme.info
        case .backupRestore: LuckyTheme.warning
        case .backupRemove, .backupCancel, .remove: LuckyTheme.danger
        }
    }

    /// Only the two destructive ones ask, and only these two: 删除备份 opens a form instead, which
    /// is its own confirmation.
    func confirmation(_ name: String) -> (title: String, message: String)? {
        switch self {
        case .backupCancel: ("取消备份", "取消数据卷 \(name) 的备份任务？")
        case .remove: ("确认删除", "删除数据卷 \(name)？")
        default: nil
        }
    }
}

/// §14 — 数据卷.
struct DockerVolumesView: View {
    var items: [LuckyListItem]
    var loading: Bool
    var busy: Bool
    var refresh: @Sendable () async -> Void
    var importVolume: () -> Void
    var perform: (DockerVolumeVerb, String) -> Void

    var body: some View {
        DockerListPane(count: items.count, loading: loading,
                       empty: DockerView.volumes.emptyMessage,
                       symbol: DockerView.volumes.symbol,
                       loadingText: "正在读取数据卷", refresh: refresh) {
            header
        } rows: {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                DockerVolumeCard(item: item, index: index, busy: busy, perform: perform)
            }
        }
    }

    /// 创建数据卷 has moved into the glass bar; 导入数据卷 stays, because it opens a file picker and
    /// belongs beside the list it adds to.
    private var header: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            LuckySectionHeader(title: DockerView.volumes.title,
                               symbol: DockerView.volumes.symbol) {
                DockerCountChip(count: items.count)
            }
            ServiceActionButton(title: "导入数据卷", symbol: LuckySymbol.upload, fill: .tinted,
                                height: 44, radius: 12, glyph: 17) {
                importVolume()
            }
        }
    }
}

// MARK: - 数据卷卡片

private struct DockerVolumeCard: View {
    var item: LuckyListItem
    var index: Int
    var busy: Bool
    var perform: (DockerVolumeVerb, String) -> Void

    /// `pick(item, ["Name","name"], keyOf(item,index))` — and this string is the key every one of
    /// the eight verbs sends.
    private var name: String {
        DockerRecord.pick(item, ["Name", "name"], DockerRecord.keyOf(item, index))
    }

    /// `${pick(item,["Driver"],"local")} · ${pick(item,["Mountpoint"])}`
    private var subtitle: String {
        let driver = DockerRecord.pick(item, ["Driver"], "local")
        return "\(driver) · \(DockerRecord.pick(item, ["Mountpoint"]))"
    }

    var body: some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            heading
            LuckyHairline()
            // `basis 120` — wider tiles than Compose's, because these labels are longer.
            LuckyTileGrid(minimum: 120, spacing: 7) {
                ForEach(DockerVolumeVerb.allCases) { verb in
                    DockerIconButton(symbol: verb.symbol, label: verb.label, tint: verb.tint,
                                     disabled: busy, fluid: true) {
                        perform(verb, name)
                    }
                }
            }
        }
    }

    private var heading: some View {
        HStack(spacing: LuckyTheme.Space.s + 2) {
            LuckyIconTile(symbol: DockerView.volumes.symbol, size: 38, glyph: 19, tone: .warning)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(LuckyTheme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 48)
    }
}
