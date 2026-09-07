import SwiftUI

/// §11's batch state, gathered into one value. Eleven separate parameters is what this replaces —
/// the panel reads nine of them and the checkbox column the other two, and every one of them lives
/// on `DockerScreen`.
struct DockerImageBatch {
    /// `imageSelectionMode`.
    var mode: Bool
    /// `selectedImageSet` — already pruned to ids the current payload still carries.
    var selected: Set<String>
    var validCount: Int
    var visibleCount: Int
    var allVisibleSelected: Bool
    var upgradeChecking: Bool
    var scanChecking: Bool
    var scanProgress: DockerProgress?
    var deleteProgress: DockerProgress?
    /// `mutation.isPending` on its own — the mode switch is the one control that is stopped by a
    /// mutation but *not* by the unused-image scan, because leaving the mode is how you cancel it.
    var pending: Bool
    /// `mutation.isPending || unusedImageScanChecking` — dims the checkboxes.
    var selectionBusy: Bool
    /// The above plus the upgrade check — stops every button in the header.
    var actionBusy: Bool
}

/// The twelve verbs §11 dispatches.
struct DockerImageActions {
    var toggle: (String) -> Void
    var toggleMode: () -> Void
    var toggleVisible: () -> Void
    var selectUnused: () -> Void
    var removeSelected: () -> Void
    /// `validSelectedImageIds.length ? detectImageUpgrades() : showImageUpgradeStatus()` — the
    /// screen owns the branch because it owns the selection.
    var upgrade: () -> Void
    var build: () -> Void
    var tools: () -> Void
    var inspect: (String) -> Void
    var tag: (String) -> Void
    var menu: (DockerImageMenu) -> Void
    /// `(key, name)` — the delete key is derived from the pair, and the confirmation quotes `name`.
    var remove: (String, String) -> Void
}

/// §11 — 镜像. The one list with a selection mode, and the only one whose header grows a whole
/// second panel when it is on.
struct DockerImagesView: View {
    var entries: [DockerImageEntry]
    var batch: DockerImageBatch
    var loading: Bool
    var refresh: @Sendable () async -> Void
    var actions: DockerImageActions

    var body: some View {
        DockerListPane(count: entries.count, loading: loading,
                       empty: DockerView.images.emptyMessage,
                       symbol: DockerView.images.symbol,
                       loadingText: "正在读取镜像", refresh: refresh) {
            header
        } rows: {
            ForEach(entries) { entry in
                DockerImageCard(entry: entry, batch: batch, actions: actions)
            }
        }
    }
}

// MARK: - 表头

extension DockerImagesView {
    /// §11.1, minus 拉取: the primary verb of every list has moved into the glass bar, so what is
    /// left here is 构建 on its own line, the advanced-tools door, and the two batch switches.
    private var header: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            LuckySectionHeader(title: DockerView.images.title,
                               symbol: DockerView.images.symbol) {
                DockerCountChip(count: entries.count)
            }
            ServiceActionButton(title: "构建", symbol: "wrench.and.screwdriver", fill: .tinted,
                                height: 44, radius: 12, glyph: 16) {
                actions.build()
            }
            ServiceActionButton(title: "镜像高级工具", symbol: "wrench.and.screwdriver",
                                fill: .card, height: 44, radius: 12,
                                name: "打开镜像高级工具", glyph: 16) {
                actions.tools()
            }
            HStack(spacing: LuckyTheme.Space.s) {
                upgradeButton
                modeButton
            }
            if batch.mode { panel }
        }
    }

    /// 升级状态 with nothing selected, 检测所选 with a selection, 处理中 while either runs.
    private var upgradeButton: some View {
        ServiceActionButton(title: upgradeTitle, symbol: LuckySymbol.refresh, fill: .tinted,
                            height: 44, radius: 12, disabled: batch.actionBusy,
                            busy: batch.upgradeChecking, name: upgradeName, glyph: 16) {
            actions.upgrade()
        }
    }

    private var upgradeTitle: String {
        if batch.upgradeChecking { return "处理中" }
        return batch.validCount > 0 ? "检测所选" : "升级状态"
    }

    private var upgradeName: String {
        batch.validCount > 0
            ? "检测已选择的 \(batch.validCount) 个镜像升级"
            : "查看镜像升级状态"
    }

    /// The mode switch. `accessibilityState.selected` is `.isSelected` here, which is what makes
    /// VoiceOver announce it as a toggle rather than reading two unrelated labels.
    private var modeButton: some View {
        ServiceActionButton(title: batch.mode ? "退出批量" : "批量操作", symbol: "checklist",
                            fill: batch.mode ? .tinted : .card, height: 44, radius: 12,
                            disabled: batch.pending || batch.upgradeChecking, glyph: 16) {
            actions.toggleMode()
        }
        .accessibilityAddTraits(batch.mode ? .isSelected : [])
    }
}

// MARK: - 批量面板

extension DockerImagesView {
    /// §11.1.5 — the three batch verbs, in a well of their own.
    private var panel: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            Text("已选择 \(batch.validCount) 项")
                .font(LuckyTheme.Text.captionMedium)
                .foregroundStyle(LuckyTheme.textPrimary)
            HStack(spacing: LuckyTheme.Space.s) {
                selectAllButton
                scanButton
            }
            deleteButton
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LuckyTheme.surfaceRaised, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth)
        }
    }

    private var selectAllButton: some View {
        ServiceActionButton(title: batch.allVisibleSelected ? "取消全选" : "全选",
                            symbol: "checklist", fill: .muted, height: 44, radius: 11,
                            disabled: batch.visibleCount == 0 || batch.actionBusy,
                            name: batch.allVisibleSelected
                                ? "取消选择当前显示的全部镜像"
                                : "选择当前显示的全部镜像",
                            glyph: 15) {
            actions.toggleVisible()
        }
    }

    /// `PackageSearch` has no SF Symbol; the magnifier over a circle is the nearest reading of
    /// "look through the packages".
    private var scanButton: some View {
        ServiceActionButton(title: scanTitle, symbol: "magnifyingglass.circle", fill: .muted,
                            height: 44, radius: 11,
                            disabled: batch.visibleCount == 0 || batch.actionBusy,
                            busy: batch.scanChecking,
                            name: batch.scanChecking ? "正在检查未使用镜像" : "选择当前显示的未使用镜像",
                            glyph: 15) {
            actions.selectUnused()
        }
    }

    private var scanTitle: String {
        guard batch.scanChecking else { return "选择未使用" }
        guard let progress = batch.scanProgress else { return "检查中" }
        return "\(progress.completed)/\(progress.total)"
    }

    /// The one control whose opacity does *not* follow `disabled`: a delete in flight keeps full
    /// contrast so its counter stays readable while every other button dims.
    private var deleteButton: some View {
        ServiceActionButton(title: deleteTitle, symbol: LuckySymbol.delete,
                            tone: batch.validCount > 0 ? .danger : .idle,
                            fill: .muted, height: 44, radius: 11,
                            disabled: batch.validCount == 0 || batch.actionBusy,
                            busy: batch.deleteProgress != nil,
                            name: "删除已选择的 \(batch.validCount) 个镜像", glyph: 15,
                            dim: batch.deleteProgress == nil) {
            actions.removeSelected()
        }
    }

    private var deleteTitle: String {
        guard let progress = batch.deleteProgress else { return "删除所选" }
        return "删除中 \(progress.completed)/\(progress.total)"
    }
}

// MARK: - 镜像卡片

/// §11.2's row. `extraData` is what tells the original's `FlatList` to redraw when the selection
/// changes; SwiftUI compares the value itself, so the checkbox needs nothing of the kind.
private struct DockerImageCard: View {
    var entry: DockerImageEntry
    var batch: DockerImageBatch
    var actions: DockerImageActions

    /// `pick(item, ["RepoTags","Tags","Name"], "<none>")` — a dangling image really is called this.
    private var name: String {
        DockerRecord.pick(entry.item, ["RepoTags", "Tags", "Name"], "<none>")
    }

    private var selected: Bool { batch.selected.contains(entry.id) }

    var body: some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            heading
            // In selection mode the row is a checkbox and nothing else — the four verbs would all
            // act on a single image while the user is choosing many.
            if !batch.mode {
                LuckyHairline()
                verbs
            }
        }
    }

    private var heading: some View {
        HStack(spacing: LuckyTheme.Space.s + 2) {
            if batch.mode { checkbox }
            LuckyIconTile(symbol: DockerView.images.symbol, size: 38, glyph: 19, tone: .warning)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(LuckyTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 48)
    }

    /// `${key.slice(0, 16)} · ${bytes(item.Size)}` — the id head is enough to tell two `<none>`
    /// images apart, which is the whole reason it is printed.
    private var subtitle: String {
        "\(String(entry.id.prefix(16))) · \(DockerRecord.bytes(entry.item["Size"]))"
    }

    /// A 24 pt box in a 44 pt hit area, filled with the danger colour when ticked: the selection
    /// exists to delete with, and the original says so in the checkbox itself.
    private var checkbox: some View {
        Button {
            actions.toggle(entry.id)
        } label: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? LuckyTheme.danger : LuckyTheme.surface)
                .frame(width: 24, height: 24)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? LuckyTheme.danger : LuckyTheme.hairline,
                                lineWidth: 1.5)
                }
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(batch.actionBusy)
        .opacity(batch.actionBusy ? 0.45 : 1)
        .accessibilityLabel("选择镜像 \(name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The four row verbs. `flexWrap` in the original; four buttons of minimum 64 pt and a 7 pt gap
    /// come to 277 pt, which fits the card interior on the narrowest supported phone, so the wrap
    /// never triggers and an `HStack` sharing the width equally is the truer reading.
    private var verbs: some View {
        HStack(spacing: 7) {
            DockerIconButton(symbol: LuckySymbol.search, label: "详情",
                             tint: LuckyTheme.textPrimary, fluid: true) {
                actions.inspect(entry.id)
            }
            DockerIconButton(symbol: LuckySymbol.edit, label: "标记",
                             tint: LuckyTheme.accent, fluid: true) {
                actions.tag(entry.id)
            }
            DockerIconButton(symbol: "ellipsis", label: "更多",
                             tint: LuckyTheme.info, fluid: true) {
                actions.menu(DockerImageMenu(key: entry.id, name: name))
            }
            DockerIconButton(symbol: LuckySymbol.delete, label: "删除",
                             tint: LuckyTheme.danger, fluid: true) {
                actions.remove(entry.id, name)
            }
        }
    }
}
