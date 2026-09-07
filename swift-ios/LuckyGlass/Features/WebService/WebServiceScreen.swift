import SwiftUI

/// The 确认更新目录 prompt.
///
/// Unlike every other alert on this screen, *both* of its buttons do work — 取消更新 tells the
/// module to discard the staged copy — so `ServiceConfirmation`'s single `perform` cannot carry it.
/// The original passes `{ cancelable: false }`; a SwiftUI alert with no `.cancel` button is exactly
/// that, since there is no outside-tap dismissal to suppress.
private struct WebFolderConfirm: Identifiable {
    var id = UUID()
    var target: WebFolderRequest
    var tempId: String
}

/// `app/webservice.tsx` — 反向代理规则、子规则分组、CGI 实例、模块设置、日志 与 辅助接口, in one screen.
///
/// The original is a single component of some 2,900 lines: nine react-query queries, one mutation
/// with seventeen arms, four overlays and a six-tab bar. Here the value types live in
/// `WebServiceModel.swift`, the payload readers in `WebRecord.swift` and each pane in its own file;
/// this file is the shell — state, loaders, the mutation dispatch and the overlay wiring.
struct WebServiceScreen: View {
    /// `useIsFocused()`, as everywhere else in this port: `.task` is cancelled when the screen is
    /// popped, and the scene phase covers backgrounding. A sheet does not defocus the route under
    /// it, which is true of an RN `Modal` too.
    @Environment(\.scenePhase) private var phase

    @State private var pane: WebPane = .rules
    /// `expanded` — the one rule key whose sub-rules are showing.
    @State private var expanded = ""
    @State private var editor: WebEditorRequest?
    /// `output` — the tools pane's result drawer. The original holds `""` when there is nothing to
    /// show and tests it for truthiness; `nil` is that empty state here.
    @State private var output: JSONValue?
    @State private var localFailure = ""

    @State private var logTarget = WebLogTarget.module
    @State private var logPage = 1
    @State private var logMode: WebLogMode = .page

    @State private var toolsTarget: WebToolsTarget?
    @State private var orderRequest: WebOrderRequest?
    @State private var folderRequest: WebFolderRequest?
    @State private var folderConfirm: WebFolderConfirm?
    @State private var mountIndex = "0"
    @State private var uploadBusy = false

    @State private var rules: [LuckyListItem] = []
    @State private var groups: [LuckyListItem] = []
    @State private var cgiItems: [LuckyListItem] = []
    @State private var settings: JSONValue?
    @State private var tips: JSONValue?
    @State private var logPayload: JSONValue?

    /// react-query keeps one error per query, so a single string would print the rules failure over
    /// the CGI pane. Each pane keeps its own.
    @State private var paneFailures: [WebPane: String] = [:]
    @State private var loaded: Set<WebPane> = []
    @State private var fetching = false
    @State private var logsFetching = false

    /// The three editor option queries, all of them `enabled` for a rule or sub-rule editor.
    @State private var groupItems: [JSONValue] = []
    @State private var wafItems: [JSONValue] = []
    @State private var filterItems: [JSONValue] = []

    /// `mutation.variables` — the action itself and not just a flag, because the log rows dim only
    /// for `disconnect-client` and the editor's banner only for its own `save`.
    @State private var running: WebAction?
    @State private var confirmation: ServiceConfirmation?
    @State private var editorFailure = ""
    @State private var toast: LuckyToast?

    var body: some View {
        shell
            // `<Page subtitle="…">`. The title comes from `LuckyRoute.webservice`, applied by the
            // pushing stack; the subtitle slot in the navigation bar is where the pair belongs.
            .navigationSubtitle("规则、分组、CGI 与运行设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: LuckySymbol.refresh)
                    }
                    .disabled(fetching || logsFetching)
                    .accessibilityLabel("刷新")
                }
            }
            .luckyToast($toast)
            .alert(confirmation?.title ?? "", isPresented: confirming,
                   presenting: confirmation) { request in
                Button("取消", role: .cancel) {}
                Button(request.confirm, role: request.destructive ? .destructive : nil) {
                    request.perform()
                }
            } message: { request in
                Text(request.message)
            }
            .sheet(item: $toolsTarget) { target in toolsSheet(target) }
            .sheet(item: $editor) { request in editorSheet(request) }
            .sheet(item: $orderRequest) { request in orderSheet(request) }
            .sheet(item: $folderRequest) { request in folderSheet(request) }
            .task(id: pane) { await loadPane() }
            .task(id: logTaskID) { await pollLogs() }
            .task(id: optionsWanted) {
                guard optionsWanted else { return }
                await loadOptions()
            }
    }
}

// MARK: - 布局

extension WebServiceScreen {
    /// `<Page scrollable={false}>` for 规则/分组/CGI/日志: the tab picker stays pinned and only the
    /// list scrolls. The original's full-width 添加 button and its log pager both move into the
    /// bottom glass bar, where every other screen in this port keeps its primary verb.
    @ViewBuilder
    fileprivate var shell: some View {
        if hasActionBar {
            frame.luckyActionBar { actionBar }
        } else {
            frame
        }
    }

    private var frame: some View {
        ZStack {
            LuckyBackdrop()
            VStack(spacing: 0) {
                header
                branch
            }
        }
    }

    /// The six-tab `ResponsiveTabBar`, followed by the two `ErrorState`s — both of which can show
    /// at once. The log pane's 模块日志 and 最近日志 buttons ride along here rather than in the list,
    /// because a glass control may not sit inside scrolling content.
    private var header: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.m) {
            HStack(spacing: LuckyTheme.Space.s) {
                LuckyGlassMenuPicker(
                    title: "视图",
                    selection: paneSelection,
                    segments: WebPane.allCases.map {
                        LuckySegment($0, $0.label, symbol: $0.symbol)
                    }
                )
                Spacer(minLength: 0)
                if pane == .logs { logSourceButtons }
            }
            if !localFailure.isEmpty {
                LuckyErrorCard(message: localFailure)
            }
            if let failure = paneFailures[pane], !failure.isEmpty {
                LuckyErrorCard(message: failure) { Task { await refresh() } }
            }
        }
        .padding(.horizontal, LuckyTheme.Space.gutter)
        .padding(.bottom, LuckyTheme.Space.m)
    }

    /// §9's `setView`. Leaving a pane clears `localError`; arriving at 日志 also drops the tools
    /// output, points the pane back at the module log and rewinds the pager — the original does all
    /// four in the tab's `onSelect`, not in `openWebLog`.
    private var paneSelection: Binding<WebPane> {
        Binding(get: { pane }, set: { next in
            localFailure = ""
            if next == .logs, pane != .logs {
                output = nil
                logTarget = .module
                logPage = 1
                logMode = .page
            }
            pane = next
        })
    }

    /// §16.1's first two controls. 模块日志 only appears once the pane has been pointed at a
    /// per-rule log, and the mode toggle only for the two kinds that have a `lastlogs` endpoint.
    @ViewBuilder
    private var logSourceButtons: some View {
        if logTarget.kind != .module {
            LuckyPillButton(title: "模块日志", symbol: LuckySymbol.logs, fills: false) {
                openLog(.module)
            }
        }
        if logTarget.kind.supportsRecent {
            LuckyPillButton(title: logMode == .recent ? "最近日志" : "分页日志",
                            symbol: logMode == .recent ? "clock" : "list.number",
                            prominent: logMode == .recent, fills: false) {
                logMode = logMode == .recent ? .page : .recent
                logPage = 1
            }
        }
    }

    /// 设置 has its 编辑全部设置 button inside its own card (§15) and 工具 has two panels of them
    /// (§17), so neither pane takes a bar; 日志 takes one only while it is paging.
    private var hasActionBar: Bool {
        switch pane {
        case .rules, .groups, .cgi: true
        case .logs: logMode == .page
        case .settings, .tools: false
        }
    }

    /// The three 添加 buttons and the log pager. §16.1 draws the pager with `ChevronUp` /
    /// `ChevronDown`; a horizontal bar wants horizontal chevrons, so it gets them here.
    @ViewBuilder
    private var actionBar: some View {
        switch pane {
        case .rules:
            LuckyPillButton(title: "添加规则", symbol: LuckySymbol.add, prominent: true) {
                editor = WebEditorRequest(.rule, title: "添加 Web 规则",
                                          value: WebService.newRule())
            }
        case .groups:
            LuckyPillButton(title: "添加分组", symbol: LuckySymbol.add, prominent: true) {
                editor = WebEditorRequest(.group, title: "添加分组",
                                          value: WebService.newGroup())
            }
        case .cgi:
            LuckyPillButton(title: "添加 CGI", symbol: LuckySymbol.add, prominent: true) {
                editor = WebEditorRequest(.cgi, title: "添加 CGI 实例",
                                          value: WebService.newCgi())
            }
        case .logs:
            LuckyGlassIconButton(symbol: "chevron.left", label: "上一页") {
                logPage = max(1, logPage - 1)
            }
            .disabled(logPage <= 1 || logsFetching)
            Text(pagerLabel)
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textSecondary)
                .monospacedDigit()
                .frame(minWidth: 82, maxWidth: .infinity)
            LuckyGlassIconButton(symbol: "chevron.right", label: "下一页") { logPage += 1 }
                .disabled(!logHasNext || logsFetching)
        case .settings, .tools:
            EmptyView()
        }
    }

    /// The pager's middle label — `` `${logPage} / ${…}` ``, where the total is `"--"` while the
    /// module has not volunteered one and `Math.max(1, Math.ceil(logTotal / 50))` once it has.
    private var pagerLabel: String {
        guard let total = logTotal else { return "\(logPage) / --" }
        let pages = (total + WebLogTarget.pageSize - 1) / WebLogTarget.pageSize
        return "\(logPage) / \(max(1, pages))"
    }
}

// MARK: - 分支

extension WebServiceScreen {
    /// Each pane is a `View` of its own, in a file of its own. `private` is file-scoped in Swift,
    /// so everything a pane reads — its rows, the busy flags, its verbs — is handed over as a
    /// parameter rather than reached for.
    @ViewBuilder
    fileprivate var branch: some View {
        switch pane {
        case .rules:
            WebRulesView(items: rules, expanded: expanded, loading: loading, busy: pending,
                         refresh: { await refresh() }, actions: ruleActions)
        case .groups:
            WebGroupsView(items: groups, loading: loading, busy: pending,
                          refresh: { await refresh() },
                          move: { index, offset in moveGroup(index, offset) },
                          edit: { item, key in
                              editor = WebEditorRequest(.group, title: "编辑分组",
                                                        value: item, key: key)
                          },
                          remove: { key, name in
                              confirmDelete(.deleteGroup(key), key: key, name: name)
                          })
        case .cgi:
            WebCgiView(items: cgiItems, loading: loading, busy: pending,
                       refresh: { await refresh() },
                       setEnabled: { key, on in run(.toggleCgi(key: key, enabled: on)) },
                       edit: { item, key in
                           editor = WebEditorRequest(.cgi, title: "编辑 CGI 实例",
                                                     value: item, key: key)
                       },
                       remove: { key, name in
                           confirmDelete(.deleteCgi(key), key: key, name: name)
                       })
        case .settings:
            WebSettingsView(value: settings, loading: loading, refresh: { await refresh() }) {
                guard let settings else { return }
                editor = WebEditorRequest(.settings, title: "编辑模块设置", value: settings)
            }
        case .logs:
            WebLogsView(target: logTarget, entries: logEntries, total: logTotal, page: logPage,
                        mode: logMode, fetching: logsFetching, disconnecting: disconnecting,
                        refresh: { await refreshLogs() }, disconnect: confirmDisconnect)
        case .tools:
            WebToolsView(tips: tips, output: output, loading: loading, busy: pending,
                         refresh: { await refresh() }, lite: { await loadLite() },
                         showTips: { output = tips ?? .object(JSONObject()) },
                         markTip: {
                             // `typeof tips.data?.version === "string"` — the button is hidden
                             // without one, and a number version would not be sent either.
                             guard case .string(let version) = tips?["version"] else { return }
                             run(.markTip(version))
                         },
                         template: {
                             editor = WebEditorRequest(.template, title: "请求轻面板配置模板",
                                                       value: .object(JSONObject()))
                         })
        }
    }
}

// MARK: - 派生值

extension WebServiceScreen {
    /// `mutation.isPending`.
    fileprivate var pending: Bool { running != nil }

    /// §16.2's `disconnecting` — the log rows dim for a 断开客户端 and for nothing else, so a rule
    /// toggle running in another pane must not grey them out.
    fileprivate var disconnecting: Bool {
        if case .disconnectClient = running { return true }
        return false
    }

    /// `activeQuery.isLoading` — fetching with nothing to show yet, which is what separates the
    /// spinner from the pull-to-refresh spinner over an existing list.
    fileprivate var loading: Bool { fetching && !loaded.contains(pane) }

    var confirming: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    var folderConfirming: Binding<Bool> {
        Binding(get: { folderConfirm != nil }, set: { if !$0 { folderConfirm = nil } })
    }

    /// `["webservice","log-view", kind, ruleKey, subKey, logPage, logMode]`, plus the two gates
    /// react-query spells as `enabled` — the pane and the focus.
    fileprivate var logTaskID: String {
        let live = pane == .logs && phase == .active
        let kind = logTarget.kind.rawValue
        let target = "\(kind)/\(logTarget.ruleKey ?? "")/\(logTarget.subKey ?? "")"
        return "\(live)|\(target)|\(logPage)|\(logMode.rawValue)"
    }

    /// The three option queries share one `enabled`, so they share one task.
    fileprivate var optionsWanted: Bool {
        editor?.kind == .rule || editor?.kind == .subrule
    }

    fileprivate var logEntries: [JSONValue] { WebRecord.logEntries(logPayload) }

    fileprivate var logTotal: Int? { WebRecord.logTotal(logPayload) }

    /// §8's `logHasNext`. Without a total the pager guesses from the page size, so a short page is
    /// the last one; in 最近日志 there is no next page at all.
    fileprivate var logHasNext: Bool {
        guard logMode == .page else { return false }
        guard let total = logTotal else { return logEntries.count >= WebLogTarget.pageSize }
        return logPage * WebLogTarget.pageSize < total
    }
}

// MARK: - 选项列表

extension WebServiceScreen {
    /// `ipFilterNames`.
    private static let filterNames = ["disable": "停用", "blacklist": "黑名单",
                                      "whitelist": "白名单", "globalblacklist": "全局黑名单"]

    /// `ipFilterOptions`. A `Map` keyed by value, so a repeated key relabels the row it already
    /// has instead of adding a second one, and the order is the order of first insertion — which
    /// is why 停用 stays at the top even when the module lists it again.
    fileprivate var filterOptions: [WebOption] {
        var order = ["disable"]
        var labels = ["disable": "停用"]
        for (index, item) in filterItems.enumerated() {
            let value = WebRecord.pick(item, ["Key", "key"])
            guard !value.isEmpty else { continue }
            let named = Self.filterNames[value]
                ?? WebRecord.pick(item, ["Name", "RuleName", "Remark"], "IP 规则 \(index + 1)")
            if labels.updateValue(named, forKey: value) == nil { order.append(value) }
        }
        return order.map { WebOption(labels[$0] ?? $0, $0) }
    }

    fileprivate var groupOptions: [WebOption] {
        [WebOption("未分组", "")] + groupItems.enumerated().map { index, item in
            WebOption(WebRecord.pick(item, ["Name", "GroupName", "Remark"], "分组 \(index + 1)"),
                      WebRecord.key(item, index))
        }
    }

    fileprivate var wafOptions: [WebOption] {
        [WebOption("无", "")] + wafItems.enumerated().map { index, item in
            WebOption(WebRecord.pick(item, ["Name", "Remark"], "WAF \(index + 1)"),
                      WebRecord.key(item, index))
        }
    }

    /// The sub-rule and default-proxy WAF pickers put 跟随主规则 first. The filter is the original's
    /// own guard against a module that names an instance `main`.
    fileprivate var subWafOptions: [WebOption] {
        [WebOption("跟随主规则", "main")] + wafOptions.filter { $0.value != "main" }
    }
}

// MARK: - 行内动作

extension WebServiceScreen {
    /// `ruleKeys` / `groupKeys` — the reorder payloads are built from the list the rows were drawn
    /// from, so a row's index and the key at that index always agree.
    private var ruleKeys: [String] { rules.enumerated().map { WebRecord.key($1, $0) } }

    private var groupKeys: [String] { groups.enumerated().map { WebRecord.key($1, $0) } }

    private func moveRule(_ index: Int, _ offset: Int) {
        run(.reorderRules(WebRecord.move(ruleKeys, index, offset)))
    }

    private func moveGroup(_ index: Int, _ offset: Int) {
        run(.reorderGroups(WebRecord.move(groupKeys, index, offset)))
    }

    /// The eleven verbs §12 hangs off a rule row and the sub-rule cards under it.
    fileprivate var ruleActions: WebRuleActions {
        WebRuleActions(
            // The header `Pressable` toggles between `key` and `""`, so tapping the open rule
            // closes it and tapping another one moves the disclosure over.
            expand: { key in expanded = expanded == key ? "" : key },
            move: { index, offset in moveRule(index, offset) },
            setEnabled: { key, on in run(.toggleRule(key: key, enabled: on)) },
            edit: { key, copy in Task { await editRule(key, copy: copy) } },
            remove: { key, name in confirmDelete(.deleteRule(key), key: key, name: name) },
            order: { request in orderRequest = request },
            tools: { target in toolsTarget = target },
            editSub: { parentKey, subKey in Task { await editSubRule(parentKey, subKey) } },
            setSubEnabled: { parentKey, key, on in
                run(.toggleSubRule(parentKey: parentKey, key: key, enabled: on))
            },
            removeSub: { parentKey, key, name in
                confirmDelete(.deleteSubRule(parentKey: parentKey, key: key),
                              key: key, name: name, subRule: true)
            },
            copyURL: { rule, sub in copyURL(rule, sub) }
        )
    }

    /// §19's first two rows. `name || key` — a row whose module named nothing falls back to the
    /// key, which is the only handle the person can recognise it by.
    private func confirmDelete(_ action: WebAction, key: String, name: String,
                               subRule: Bool = false) {
        let label = name.isEmpty ? key : name
        let what = subRule ? "子规则“\(label)”" : "“\(label)”"
        confirmation = ServiceConfirmation(title: "确认删除", message: "确定删除\(what)吗？",
                                          confirm: "删除") { run(action) }
    }

    /// `openWebLog(target)`. `pane` is assigned directly rather than through `paneSelection`,
    /// whose setter would immediately reset the target this call just chose.
    private func openLog(_ target: WebLogTarget) {
        logTarget = target
        logPage = 1
        logMode = .page
        output = nil
        localFailure = ""
        toolsTarget = nil
        pane = .logs
    }

    private func confirmDisconnect(_ ruleKey: String, _ clientKey: String) {
        confirmation = ServiceConfirmation(
            title: "断开客户端", message: "确定断开此客户端连接吗？", confirm: "断开"
        ) { run(.disconnectClient(ruleKey: ruleKey, clientKey: clientKey)) }
    }
}

// MARK: - 打开编辑器

extension WebServiceScreen {
    /// `editRule(key, copyRule)`. 复制规则 re-uses the edit form to POST a new rule: the key is
    /// blanked, the name gains 副本, every sub-rule loses its key so the module assigns fresh ones,
    /// and the editor is handed no `key` — which is what makes its save a create.
    private func editRule(_ key: String, copy: Bool) async {
        do {
            var value = try await WebService.rule(key).record
            if copy {
                value["RuleKey"] = .string("")
                let name = WebRecord.pick(.object(value), ["RuleName"], "规则")
                value["RuleName"] = .string("\(name) - 副本")
                value["ProxyList"] = .array(WebRecord.array(.object(value), ["ProxyList"]).map {
                    // `item.Key = ""` throws on a primitive in strict mode; a non-record entry is
                    // passed through instead of being given a key it cannot carry.
                    guard var proxy = $0.objectValue else { return $0 }
                    proxy["Key"] = .string("")
                    return .object(proxy)
                })
            }
            editor = WebEditorRequest(.rule, title: copy ? "复制 Web 规则" : "编辑 Web 规则",
                                      value: .object(value), key: copy ? nil : key)
        } catch {
            localFailure = error.luckyMessage("读取规则失败")
        }
    }

    /// `editSubRule(parentKey, key?)`. The sub-rule lives inside its parent, so the parent is read
    /// even to add one — its `DiaglogShowMode` and `EnableTLS` decide which fields the form draws.
    private func editSubRule(_ parentKey: String, _ key: String?) async {
        do {
            let rule = try await WebService.rule(parentKey)
            let value = try subRuleValue(rule, key)
            editor = WebEditorRequest(.subrule, title: key == nil ? "添加子规则" : "编辑子规则",
                                      value: value, key: key, parentKey: parentKey,
                                      ruleMode: ruleMode(rule["DiaglogShowMode"]),
                                      tlsEnabled: WebRecord.bool(rule["EnableTLS"]))
        } catch {
            localFailure = error.luckyMessage("读取子规则失败")
        }
    }

    private func subRuleValue(_ rule: JSONValue, _ key: String?) throws -> JSONValue {
        guard let key else { return WebService.newSubRule() }
        let items = WebRecord.array(rule, ["ProxyList"])
        let match = items.indices.first { WebRecord.key(items[$0], $0) == key }
        guard let index = match else { throw LuckyError("子规则不存在") }
        return items[index]
    }

    /// `rule.DiaglogShowMode === "full" ? "diy" : String(rule.DiaglogShowMode ?? "simple")`.
    /// `??` skips null as well as absent, and `String` of anything else is its own text — so a
    /// numeric mode arrives at the form as digits and simply matches none of its branches.
    private func ruleMode(_ value: JSONValue?) -> String {
        guard let value, !value.isNull else { return "simple" }
        if value.stringValue == "full" { return "diy" }
        return value.asDisplayString
    }

    /// `copySubRuleUrl(rule, subRule)`. Copying is not a decision, so its five `Alert.alert`s all
    /// become toasts — the success one carrying the URL, which is what the original shows as the
    /// alert's message. `UIPasteboard` has no failure channel, so the two clipboard-error outcomes
    /// (`复制失败` for a falsy result and for a throw) cannot arise here.
    private func copyURL(_ rule: LuckyListItem, _ sub: LuckyListItem) {
        let url: String
        do {
            url = try WebRecord.subRuleUrl(rule, sub)
        } catch {
            toast = .failed("无法复制 · 该子规则的前端地址格式不正确")
            return
        }
        guard !url.isEmpty else {
            toast = .failed("无法复制 · 该子规则没有前端地址")
            return
        }
        LuckyClipboard.copy(url)
        toast = .ok("网址已复制 · \(url)")
    }
}

// MARK: - 变更

extension WebServiceScreen {
    /// The single `useMutation`. Seventeen call sites, one dispatch.
    fileprivate func run(_ action: WebAction) {
        Task { await perform(action) }
    }

    /// `mutate`'s three phases. `running` holds the action itself and not a flag, because §16.2
    /// dims the log rows for a 断开客户端 and for nothing else.
    private func perform(_ action: WebAction) async {
        running = action
        defer { running = nil }
        do {
            let result = try await action.perform()
            // `mutationFn`'s own tail — a template request produces output and changes nothing.
            if case .save(let request, _) = action, request.kind == .template { output = result }
            switch action {
            case .save: editor = nil
            case .reorderGroupSubRules: orderRequest = nil
            case .disconnectClient: toast = .ok("客户端已断开 · 访问详情正在刷新")
            case .flushCache:
                output = result
                toolsTarget = nil
                toast = .ok("缓存已刷新")
            default: break
            }
            localFailure = ""
            editorFailure = ""
            await invalidate(action)
        } catch {
            let message = error.luckyMessage()
            localFailure = message
            // The original has one `mutation.error`, read both by the page and by the open editor.
            if case .save = action { editorFailure = message }
            switch action {
            case .disconnectClient, .flushCache: toast = .failed("操作失败 · \(message)")
            default: break
            }
        }
    }

    /// `invalidateWebService(action)`. react-query refetches the mounted queries and marks the rest
    /// stale; every pane here refetches on entry anyway, so marking an off-screen one stale is a
    /// no-op and the sweep reduces to "reload whatever is showing". The pane keeps its old rows
    /// while that runs, which is what makes this a refetch and not a reload.
    private func invalidate(_ action: WebAction) async {
        let keys = action.invalidates
        if pane == .logs {
            if keys.contains(.logs) { await loadLogs() }
        } else if keys.contains(query(of: pane)) {
            await loadPane()
        }
    }

    /// `activeQuery` — the query a pane draws from. 工具 draws the tips, which is why 标记为已读
    /// refreshes it.
    private func query(of pane: WebPane) -> WebQuery {
        switch pane {
        case .rules: .rules
        case .groups: .groups
        case .cgi: .cgi
        case .settings: .settings
        case .logs: .logs
        case .tools: .tips
        }
    }
}

// MARK: - 读取

extension WebServiceScreen {
    /// The five non-log queries, gated by `view` exactly as their `enabled` flags are.
    ///
    /// There is deliberately no `guard !fetching` prologue: `.task(id: pane)` starts the next
    /// pane's load before the cancelled one has returned, and a guard would drop it. The flag is
    /// instead cleared only by the load that is still on the pane it started on; a duplicate read
    /// from pull-to-refresh is harmless, since the last write wins either way.
    fileprivate func loadPane() async {
        let target = pane
        // 日志 is driven by `pollLogs`, whose task id carries the target, the page and the mode.
        guard target != .logs else { return }
        fetching = true
        defer { if pane == target { fetching = false } }
        do {
            switch target {
            case .rules: rules = try await WebService.rules().items
            case .groups: groups = try await WebService.groups(includeCounts: true).items
            case .cgi: cgiItems = try await WebService.cgiList().items
            case .settings: settings = try await WebService.settings()
            case .tools: tips = try await WebService.tipInfo()
            case .logs: return
            }
            paneFailures[target] = ""
            loaded.insert(target)
        } catch {
            // A cancelled read is a pane switch, not a failure; react-query drops those too.
            guard !error.isCancellation else { return }
            paneFailures[target] = error.luckyMessage()
        }
    }

    /// The `logs` query. Its failure goes in the log pane's own slot so a stale rules error cannot
    /// print over it.
    private func loadLogs() async {
        logsFetching = true
        defer { logsFetching = false }
        do {
            logPayload = try await logTarget.load(page: logPage, mode: logMode)
            paneFailures[.logs] = ""
            loaded.insert(.logs)
        } catch {
            guard !error.isCancellation else { return }
            paneFailures[.logs] = error.luckyMessage()
        }
    }

    /// `refetchInterval: 15000` while the pane is showing and it is either the tail or page 1.
    /// The loop is the whole gate: `.task(id: logTaskID)` cancels it — and the sleep with it —
    /// whenever the target, page, mode or scene phase changes, or the screen is popped.
    fileprivate func pollLogs() async {
        guard pane == .logs, phase == .active else { return }
        await loadLogs()
        guard logMode == .recent || logPage == 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await loadLogs()
        }
    }

    /// The three editor option queries. They share one `enabled`, so they share one task; their
    /// errors are never surfaced — an empty list reads as "this module has none", which is the
    /// common case for both the WAF instances and the IP filter rules.
    fileprivate func loadOptions() async {
        async let groupsTask = WebService.groupOptions()
        async let wafTask = WebService.corazaInstances()
        async let filtersTask = WebService.ipFilterRules()
        groupItems = (try? await groupsTask) ?? []
        wafItems = (try? await wafTask) ?? []
        filterItems = (try? await filtersTask) ?? []
    }

    /// `activeQuery.refetch()` — the 刷新 button and every pull-to-refresh.
    fileprivate func refresh() async {
        if pane == .logs {
            await loadLogs()
        } else {
            await loadPane()
        }
    }

    private func refreshLogs() async { await loadLogs() }

    /// §17's 读取轻量列表. `result.raw` and not `items`: the panel shows the whole envelope.
    fileprivate func loadLite() async {
        do {
            output = try await WebService.rules(lite: true).raw
        } catch {
            localFailure = error.luckyMessage("请求失败")
        }
    }
}

// MARK: - 目录更新

extension WebServiceScreen {
    /// `Math.max(0, Number.parseInt(mountIndex, 10) || 0)`. NaN and every negative index fold to 0;
    /// a digit run too long for an `Int` is infinity to `parseInt`, and the module clamps it to its
    /// own mount count either way.
    private var mountIndexValue: Int {
        let parsed = JSCompat.parseInt(mountIndex)
        guard parsed > 0 else { return 0 }
        return Int(exactly: parsed) ?? .max
    }

    /// `String(result.tempId ?? result.data?.tempId ?? "")` — `??` skips null as well as absent.
    private func tempId(_ result: JSONValue) -> String {
        for candidate in [result["tempId"], result["data"]?["tempId"]] {
            guard let value = candidate, !value.isNull else { continue }
            return value.asDisplayString
        }
        return ""
    }

    /// `uploadFolderUpdate()`, from just after the picker returned. A module that answers no
    /// `tempId` has nothing to confirm, so the sheet simply closes — the output pane already shows
    /// whatever it did say.
    fileprivate func uploadFolder(_ target: WebFolderRequest, _ url: URL) async {
        uploadBusy = true
        localFailure = ""
        defer { uploadBusy = false }
        do {
            let file = try WebServiceUpload(url: url)
            let result = try await WebService.uploadFolder(ruleKey: target.parentKey,
                                                          subKey: target.subKey,
                                                          mountIndex: mountIndexValue, file: file)
            output = result
            let id = tempId(result)
            guard !id.isEmpty else {
                folderRequest = nil
                return
            }
            folderConfirm = WebFolderConfirm(target: target, tempId: id)
        } catch {
            localFailure = error.luckyMessage("目录更新失败")
        }
    }

    /// `resolveFolderUpdate(target, tempId, applyUpdate)`. Both buttons of the alert land here;
    /// what differs is the endpoint and whether the rules are re-read afterwards — applying an
    /// update changes the sub-rule's directory, which the rule list prints.
    fileprivate func resolveFolder(_ request: WebFolderConfirm, apply: Bool) async {
        let title = apply ? "应用目录更新失败" : "取消目录更新失败"
        let target = request.target
        uploadBusy = true
        localFailure = ""
        defer { uploadBusy = false }
        do {
            if apply {
                output = try await WebService.confirmFolderUpdate(ruleKey: target.parentKey,
                                                                 subKey: target.subKey,
                                                                 tempId: request.tempId)
            } else {
                output = try await WebService.cancelFolderUpdate(ruleKey: target.parentKey,
                                                                subKey: target.subKey,
                                                                tempId: request.tempId)
            }
            folderRequest = nil
            if apply, pane == .rules { await loadPane() }
        } catch {
            let message = error.luckyMessage(title)
            localFailure = message
            toast = .failed("\(title) · \(message)")
        }
    }
}

// MARK: - 浮层

extension WebServiceScreen {
    /// §18's tools modal. Its close ignores the tap while a mutation is running, so a 刷新 still in
    /// flight cannot lose the sheet it was started from.
    ///
    /// §19's 刷新目录缓存 confirmation is raised by the sheet rather than from here, for the same
    /// reason §18.1's is: the original floats it over the still-open modal, and a page-level alert
    /// behind a sheet never appears. What is left here is the mutation it confirms.
    fileprivate func toolsSheet(_ target: WebToolsTarget) -> some View {
        WebToolsSheet(
            target: target, busy: pending,
            close: { if !pending { toolsTarget = nil } },
            openLog: openLog,
            flush: {
                guard let subKey = target.subKey, !subKey.isEmpty else { return }
                run(.flushCache(ruleKey: target.ruleKey, subKey: subKey))
            },
            updateFolder: {
                guard let subKey = target.subKey, !subKey.isEmpty else { return }
                mountIndex = "0"
                folderRequest = WebFolderRequest(parentKey: target.ruleKey, subKey: subKey)
                toolsTarget = nil
            }
        )
    }

    /// `WebServiceEditor`. `.sheet(item:)` keys on `WebEditorRequest.id`, which is the original's
    /// `key={`${type}-${key ?? "new"}`}` — so moving from one rule to another remounts the form
    /// instead of feeding new props to the old one.
    fileprivate func editorSheet(_ request: WebEditorRequest) -> some View {
        WebEditorSheet(request: request, busy: pending, failure: editorFailure,
                       filterOptions: filterOptions, groupOptions: groupOptions,
                       wafOptions: wafOptions, subWafOptions: subWafOptions,
                       close: {
                           // `mutation.reset()` — closing the form drops the error it was showing.
                           editorFailure = ""
                           editor = nil
                       },
                       save: { value in run(.save(request, value)) })
    }

    fileprivate func orderSheet(_ request: WebOrderRequest) -> some View {
        WebOrderSheet(request: request, busy: pending, close: { orderRequest = nil }) { keys in
            // The sheet lets every row be cleared; an empty payload would wipe the rule's
            // sub-rules, so it is refused before the mutation is built.
            guard !keys.isEmpty else {
                localFailure = "至少填写一个子规则 Key"
                return
            }
            run(.reorderGroupSubRules(ruleKey: request.key, keys: keys))
        }
    }

    /// §18.1. The 确认更新目录 alert hangs off the sheet and not off the page, because the original
    /// shows it *over* the still-open modal — and an alert presented from behind a sheet never
    /// appears at all.
    fileprivate func folderSheet(_ request: WebFolderRequest) -> some View {
        WebFolderSheet(mountIndex: $mountIndex, busy: uploadBusy, failure: localFailure,
                       close: { if !uploadBusy { folderRequest = nil } },
                       upload: { url in Task { await uploadFolder(request, url) } })
            .alert("确认更新目录", isPresented: folderConfirming,
                   presenting: folderConfirm) { item in
                Button("取消更新", role: .destructive) {
                    Task { await resolveFolder(item, apply: false) }
                }
                Button("应用更新") { Task { await resolveFolder(item, apply: true) } }
            } message: { _ in
                Text("压缩包已上传并完成预检，是否应用目录更新？")
            }
    }
}
