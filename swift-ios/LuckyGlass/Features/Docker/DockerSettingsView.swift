import SwiftUI

/// §17's eight verbs. Every one of them opens an editor or a confirmation the screen owns, so the
/// view carries no payloads — only the fact that the button was pressed.
struct DockerSettingsActions {
    var editConfig: () -> Void
    var createGroup: () -> Void
    var updateGroup: () -> Void
    var removeGroup: () -> Void
    var clearUpgrades: () -> Void
    var addMirror: () -> Void
    var removeMirror: () -> Void
    var prune: () -> Void
}

/// §17 — Docker 设置. Three read-only reports and eight verbs, in the scrollable page.
///
/// Nothing here is disabled while a mutation runs: the original's settings buttons all open a form
/// or a confirmation rather than firing, so a pending mutation cannot be made worse by pressing
/// one of them.
struct DockerSettingsView: View {
    var config: JSONValue?
    var mirrors: JSONValue?
    var maintenance: JSONValue?
    /// `maintenance.isFetching` — the only spinner in the view, printed as the 维护状态 meta.
    var maintenanceFetching: Bool
    /// `maintenance.error.message`, which gets a card of its own (§17.3) because `config` is the
    /// query the chrome's error card is wired to.
    var maintenanceFailure: String
    /// Shown only before anything has arrived. The original draws the two headers over nothing
    /// while the three queries are in flight (§25.15).
    var loading: Bool
    var refresh: @Sendable () async -> Void
    var actions: DockerSettingsActions

    var body: some View {
        DockerPaneScroll(refresh: refresh) {
            LuckySectionHeader(title: "Docker 设置", symbol: LuckySymbol.settings)
            // `config.data ? … : null` — there is nothing to edit until the daemon's settings are
            // in hand, and an editor opened over an empty record would save an empty record.
            if config != nil {
                ServiceActionButton(title: "编辑设置", symbol: LuckySymbol.settings, fill: .solid,
                                    height: 46, radius: 12, glyph: 17) {
                    actions.editConfig()
                }
            }
            if !maintenanceFailure.isEmpty {
                LuckyErrorCard(message: maintenanceFailure) { Task { await refresh() } }
            }
            LuckySectionHeader(title: "维护状态", symbol: LuckySymbol.monitor) {
                Text(maintenanceFetching ? "正在刷新" : "7 个接口")
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textSecondary)
            }
            if let maintenance {
                groupPanel(maintenance)
                backupPanel(maintenance)
                upgradePanel(maintenance)
            } else if loading {
                LuckyLoadingView(text: "正在读取维护状态")
            }
            mirrorPanel
            // 清理未使用资源 stays in the scroll rather than moving to a glass bar: it is the last
            // thing in the page and it opens a five-switch form, not a one-tap action.
            ServiceActionButton(title: "清理未使用资源", symbol: "exclamationmark.shield",
                                tone: .danger, fill: .soft, height: 46, radius: 12, glyph: 17) {
                actions.prune()
            }
        }
    }
}

// MARK: - 维护状态面板

extension DockerSettingsView {
    /// §17.5's first panel — the four grouping endpoints as one record, and the three group verbs.
    ///
    /// The four fields are re-wrapped rather than passed through: `maintenance` also carries
    /// `imageUpgrades`, `composeBackup` and `volumeBackup`, and each panel shows only its own.
    private func groupPanel(_ payload: JSONValue) -> some View {
        panel(title: "分组与标签", symbol: "shippingbox") {
            StructuredDataView(value: .object(JSONObject([
                ("labels", payload["labels"] ?? .null),
                ("containerGroups", payload["containerGroups"] ?? .null),
                ("collapsedStates", payload["collapsedStates"] ?? .null),
                ("orderMapping", payload["orderMapping"] ?? .null),
            ])))
            HStack(spacing: LuckyTheme.Space.s) {
                ServiceActionButton(title: "添加分组", symbol: LuckySymbol.add, fill: .tinted,
                                    height: 44, radius: 12, glyph: 15) {
                    actions.createGroup()
                }
                // `borderColor: primary, backgroundColor: card` — the same tinted border over the
                // card fill, which `.card` draws with a neutral label; the accent belongs to the
                // border here, and the label follows the design system rather than the border.
                ServiceActionButton(title: "编辑分组", symbol: LuckySymbol.edit, fill: .card,
                                    height: 44, radius: 12, glyph: 15) {
                    actions.updateGroup()
                }
                ServiceActionButton(title: "删除分组", symbol: LuckySymbol.delete, tone: .danger,
                                    fill: .tinted, height: 44, radius: 12, glyph: 15) {
                    actions.removeGroup()
                }
            }
        }
    }

    /// §17.5's second panel. lucide's `Database` is a stack of platters, which reads as a drive on
    /// iOS; there is no report here beyond the two backup states, and no verb at all.
    private func backupPanel(_ payload: JSONValue) -> some View {
        panel(title: "备份任务", symbol: LuckySymbol.disk) {
            StructuredDataView(value: .object(JSONObject([
                ("composeBackup", payload["composeBackup"] ?? .null),
                ("volumeBackup", payload["volumeBackup"] ?? .null),
            ])))
        }
    }

    /// §17.5's third panel — the upgrade report, and the one verb in 设置 that fires a mutation.
    private func upgradePanel(_ payload: JSONValue) -> some View {
        panel(title: "镜像升级", symbol: DockerView.images.symbol) {
            StructuredDataView(value: payload["imageUpgrades"] ?? .null)
            ServiceActionButton(title: "清除升级状态", symbol: LuckySymbol.delete, tone: .danger,
                                fill: .soft, height: 44, radius: 12, glyph: 15) {
                actions.clearUpgrades()
            }
        }
    }

    /// §17.6 — the one panel whose heading is plain text and not a `SectionHeader`. Kept that way:
    /// `Registry Mirrors` is the daemon's own term and the only untranslated string in the screen.
    private var mirrorPanel: some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            Text("Registry Mirrors")
                .font(LuckyTheme.Text.bodyMedium)
                .foregroundStyle(LuckyTheme.textPrimary)
            StructuredDataView(value: mirrorList)
            HStack(spacing: LuckyTheme.Space.s) {
                ServiceActionButton(title: "添加", symbol: LuckySymbol.add, fill: .tinted,
                                    height: 44, radius: 12, glyph: 15) {
                    actions.addMirror()
                }
                ServiceActionButton(title: "删除", symbol: LuckySymbol.delete, tone: .danger,
                                    fill: .tinted, height: 44, radius: 12, glyph: 15) {
                    actions.removeMirror()
                }
            }
        }
    }

    /// `mirrors.data?.mirrors ?? mirrors.data?.list ?? []` — JS `??` falls through `null` only, so
    /// a module that answers with an empty `mirrors` array stops here rather than trying `list`.
    private var mirrorList: JSONValue {
        guard let mirrors else { return .array([]) }
        if let value = mirrors["mirrors"], !value.isNull { return value }
        if let value = mirrors["list"], !value.isNull { return value }
        return .array([])
    }

    /// `<Panel><SectionHeader …/>…</Panel>` — the header sits inside the plate, as it does in the
    /// original, because these three are cards nested in a page that already has its own headings.
    private func panel<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            LuckySectionHeader(title: title, symbol: symbol)
            content()
        }
    }
}
