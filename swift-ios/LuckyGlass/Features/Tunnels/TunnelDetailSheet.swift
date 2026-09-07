import SwiftUI

/// The detail `ScreenModal` — 日志, 运行详情, and the three child lists.
///
/// It renders what the screen has already fetched rather than fetching anything itself: the
/// polling, the page cursor and every mutation live on `TunnelScreen`, because closing the sheet
/// must not cancel a save and a save must refresh the list behind it. What arrives here is one
/// payload plus the callbacks, which is also why re-opening a pane starts from a clean 加载中 rather
/// than from a stale render.
struct TunnelDetailSheet: View {
    var kind: TunnelKind
    var detail: TunnelDetail
    var value: JSONValue?
    /// The screen's mutation banner. The original prints it inside this modal as well, and an
    /// operation started from in here would otherwise report to a banner hidden behind the sheet.
    var actionFailure: String
    var failure: String
    var loaded: Bool
    var fetching: Bool
    var pending: Bool
    var page: Int
    var dnsResult: JSONValue?
    var close: () -> Void
    var refresh: () async -> Void
    var setPage: (Int) -> Void
    var add: (TunnelCollection, JSONValue) -> Void
    var edit: (TunnelCollection, JSONValue, JSONValue) -> Void
    var toggle: (TunnelCollection, JSONValue, JSONValue) -> Void
    var remove: (TunnelCollection, JSONValue, JSONValue) -> Void
    var dns: (TunnelsService.DnsAction, JSONValue, String) -> Void

    private var itemKey: String { TunnelRecord.key(detail.item) }

    /// `${模式} · ${key ? 名称 : 模块名}`. The ` · ` join becomes the navigation bar's title and
    /// subtitle — the same pair the 服务 sheets use — so a long rule name no longer truncates the
    /// word that says which pane this is.
    private var subtitle: String {
        itemKey.isEmpty ? kind.title : TunnelRecord.name(detail.item)
    }

    var body: some View {
        ServiceSheet(title: detail.mode.title, subtitle: subtitle, close: close) {
            actionBar
        } content: {
            banners
            pane
        }
    }
}

// MARK: - Chrome

extension TunnelDetailSheet {
    /// The original's 刷新 / 新增规则 row, moved to the bottom glass bar. 新增规则 is the sheet's only
    /// primary verb, and it exists only for a child list.
    @ViewBuilder
    private var actionBar: some View {
        LuckyPillButton(title: "刷新", symbol: LuckySymbol.refresh) {
            Task { await refresh() }
        }
        .disabled(fetching)
        if let collection = detail.mode.collection {
            LuckyPillButton(title: "新增规则", symbol: LuckySymbol.add, prominent: true) {
                add(collection, detail.item)
            }
            .disabled(pending)
        }
    }

    @ViewBuilder
    private var banners: some View {
        if !actionFailure.isEmpty {
            LuckyErrorCard(message: actionFailure, title: "操作失败")
        }
        if !failure.isEmpty {
            LuckyErrorCard(message: failure) { Task { await refresh() } }
        }
        if !loaded {
            LuckyLoadingView()
        }
    }
}

// MARK: - Panes

extension TunnelDetailSheet {
    @ViewBuilder
    private var pane: some View {
        switch detail.mode {
        case .logs: logsPane
        case .status: statusPane
        case .collection(let collection): childPane(collection)
        }
    }
}

// MARK: - 日志

extension TunnelDetailSheet {
    private var lines: [String] { TunnelsService.logLines(value) }

    @ViewBuilder
    private var logsPane: some View {
        let entries = lines
        if entries.isEmpty {
            if loaded, failure.isEmpty {
                LuckyEmptyState(symbol: LuckySymbol.logs, title: "暂无日志")
            }
        } else {
            // Following the tail is right for 实时 and wrong for a history page, which the reader
            // arrived at deliberately and wants to start at the top of.
            LuckyLogView(lines: entries, follows: page <= 1, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: LuckyTheme.Radius.card,
                                            style: .continuous))
        }
        pager(entries.count)
    }

    /// Page 0 is 最新日志, the module's realtime endpoint, and it exists only for a rule that has a
    /// key — so the module-wide log floors at 1. 下一页 closes on a short page because the module
    /// answers 100 lines at a time and anything shorter is the last of them.
    private func pager(_ count: Int) -> some View {
        let floor = itemKey.isEmpty ? 1 : 0
        return HStack(spacing: LuckyTheme.Space.s) {
            ServiceActionButton(title: page == 1 && !itemKey.isEmpty ? "最新日志" : "上一页",
                                symbol: "arrow.up", fill: .soft, height: 42, radius: 12,
                                disabled: page <= floor || fetching) {
                setPage(page - 1)
            }
            Text(page == 0 ? "实时" : String(page))
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textSecondary)
                .frame(minWidth: 34)
            ServiceActionButton(title: page == 0 ? "历史日志" : "下一页",
                                symbol: "arrow.down", fill: .soft, height: 42, radius: 12,
                                disabled: fetching || (page > 0 && count < 100)) {
                setPage(page + 1)
            }
        }
    }
}

// MARK: - 运行详情

extension TunnelDetailSheet {
    /// `record(details.data).status ?? record(details.data).data ?? {}`. `??` steps over an absent
    /// key only, so a module answering `status: false` shows that rather than falling through.
    private var statusValue: JSONValue {
        let payload = (value ?? .null).record
        if let status = payload["status"], !status.isNull { return status }
        if let data = payload["data"], !data.isNull { return data }
        return .object(JSONObject())
    }

    private var statusPane: some View {
        LuckyCard {
            StructuredDataView(value: statusValue)
        }
    }
}

// MARK: - 子规则

extension TunnelDetailSheet {
    private var children: [JSONValue] { value?["items"]?.arrayValue ?? [] }

    /// `dnsResult.status ?? dnsResult` — 检测 DNS answers inside a `status` wrapper and the other
    /// two answer bare, so the same view renders both.
    private var dnsValue: JSONValue? {
        guard let dnsResult else { return nil }
        if let status = dnsResult["status"], !status.isNull { return status }
        return dnsResult
    }

    @ViewBuilder
    private func childPane(_ collection: TunnelCollection) -> some View {
        let rules = children
        if rules.isEmpty, loaded, failure.isEmpty {
            LuckyEmptyState(symbol: LuckySymbol.network, title: "暂无规则")
        }
        // The original keys these by name, path and index together; a child list has no identity of
        // its own, so the position is the only stable part of that.
        ForEach(Array(rules.enumerated()), id: \.offset) { _, child in
            childCard(collection, child)
        }
        if let dnsValue {
            LuckyCard {
                StructuredDataView(value: dnsValue)
            }
        }
    }
}

// MARK: - 子规则的动作

extension TunnelDetailSheet {
    private func childCard(_ collection: TunnelCollection, _ child: JSONValue) -> some View {
        LuckyCard(spacing: LuckyTheme.Space.s) {
            Text(TunnelRecord.childTitle(child))
                .font(LuckyTheme.Text.bodyMedium)
                .foregroundStyle(LuckyTheme.textPrimary)
                .lineLimit(2)
            Text(TunnelRecord.childSummary(child, collection: collection))
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textSecondary)
                .textSelection(.enabled)
            LuckyTileGrid(minimum: 105, spacing: 7) {
                verb("编辑", LuckySymbol.edit) { edit(collection, detail.item, child) }
                // 域名路由 has no per-rule switch: Cloudflared's ingress table is ordered, not
                // toggled, so the module ignores a `disabled` key there.
                if collection != .ingress {
                    let off = child["disabled"]?.isTruthy == true
                    verb(off ? "启用" : "停用", LuckySymbol.restart) {
                        toggle(collection, detail.item, child)
                    }
                }
                verb("删除", LuckySymbol.delete, tone: .danger) {
                    remove(collection, detail.item, child)
                }
                dnsVerbs(collection, child)
            }
        }
    }

    /// The three Cloudflare verbs, for an ingress rule that names a hostname. 检测 renders its answer
    /// under the list; 创建 and 删除 route through the screen's confirmation alert.
    @ViewBuilder
    private func dnsVerbs(_ collection: TunnelCollection, _ child: JSONValue) -> some View {
        if collection == .ingress, child["hostname"]?.isTruthy == true {
            let hostname = TunnelRecord.text(child["hostname"])
            verb("检测 DNS", "globe.asia.australia") { dns(.check, detail.item, hostname) }
            verb("创建 DNS", LuckySymbol.add) { dns(.create, detail.item, hostname) }
            verb("删除 DNS", LuckySymbol.delete, tone: .danger) {
                dns(.delete, detail.item, hostname)
            }
        }
    }

    private func verb(_ title: String, _ symbol: String, tone: LuckyTone = .brand,
                      action: @escaping () -> Void) -> some View {
        ServiceActionButton(title: title, symbol: symbol, tone: tone, fill: .soft, height: 42,
                            radius: 12, disabled: pending, action: action)
    }
}
