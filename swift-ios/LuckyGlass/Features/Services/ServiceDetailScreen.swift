import SwiftUI

/// `ServiceEditor` — what a `ServiceFormEditor` is editing: one item of the module's list, or the
/// module's own settings record.
///
/// An empty `key` means "create". The original tests `editor.key` for truthiness and an absent key
/// is `undefined` there, so the empty string carries the same meaning here.
struct ServiceEditorRequest: Identifiable {
    enum Target: String { case item, settings }

    var target: Target = .item
    var title: String
    var value: JSONObject = JSONObject()
    var key: String = ""

    /// `key={`${editor.type}-${editor.key ?? 'new'}`}` — remounting the editor when the subject
    /// changes is what stops a half-typed record from leaking into the next one.
    var id: String { "\(target.rawValue)-\(key.isEmpty ? "new" : key)" }
}

/// `advanced` — the subject of the 高级操作 sheet.
struct ServiceAdvancedRequest: Identifiable {
    var key: String
    var name: String
    var item: JSONValue

    var id: String { key }
}

/// One `Alert.alert(title, message, [取消, confirm])`.
///
/// The original builds these inline at every call site; a single alert driven by a value keeps
/// SwiftUI from needing one `isPresented` flag per verb, and the five confirmations on this screen
/// differ only in their copy.
struct ServiceConfirmation: Identifiable {
    var id = UUID()
    var title: String
    var message: String
    var confirm: String
    var destructive: Bool = true
    var perform: () -> Void
}

/// One of the five Docker verbs. A struct rather than the original's `[action, label, Icon]` tuple
/// because `ForEach` needs a key path for identity and Swift key paths cannot address tuple
/// elements.
struct ServiceVerb: Identifiable {
    var id: String
    var label: String
    var symbol: String
}

/// `app/services/[kind].tsx` — one module's list, its logs, and every verb the module exposes.
///
/// Reachable for all four kinds: 反向代理 and Docker have their own richer screens, and the original
/// still routes `/services/webservice` and `/services/docker` here, so both branches are kept.
struct ServiceDetailScreen: View {
    var kind: LuckyServiceKind

    private enum Mode: Hashable { case list, logs }
    private enum LogMode: String, Hashable { case page, recent }

    /// `useIsFocused()` has no `LuckyNavigator` equivalent — the navigator exposes no "top of
    /// stack" query — so the poll gate is the scene phase, plus `.task` being cancelled when the
    /// screen is popped. A presented sheet does not remove the view, which matches RN: a `Modal`
    /// does not defocus the route underneath it.
    @Environment(\.scenePhase) private var phase

    @State private var mode: Mode = .list
    @State private var items: [LuckyListItem] = []
    @State private var listFailure = ""
    @State private var loaded = false
    @State private var fetching = false

    /// `selectedKey` — both the expanded row and the detail request's argument.
    @State private var selectedKey = ""
    @State private var detail: JSONValue?
    @State private var detailFailure = ""
    @State private var detailFetching = false

    @State private var logKey: String?
    @State private var logMode: LogMode = .page
    @State private var logPage = 1
    @State private var logs: LuckyLogPage?
    @State private var logsFailure = ""
    @State private var logsFetching = false

    /// One slot for what the original keeps in `ddnsEditor` and `sslEditor`: a screen has exactly
    /// one `kind`, so only one of the two can ever be set.
    @State private var editor: ServiceEditorRequest?
    @State private var adding = false
    @State private var advanced: ServiceAdvancedRequest?
    @State private var syncClients: [LuckyListItem] = []
    @State private var editorFailure = ""
    @State private var saving = false

    @State private var confirmation: ServiceConfirmation?
    @State private var actionFailure = ""
    @State private var pending = false
    @State private var toast: LuckyToast?

    /// `[['start','启动',Play], …]`. `unpause` shares `Play` in the original too.
    private static let dockerVerbs: [ServiceVerb] = [
        ServiceVerb(id: "start", label: "启动", symbol: LuckySymbol.start),
        ServiceVerb(id: "stop", label: "停止", symbol: LuckySymbol.stop),
        ServiceVerb(id: "restart", label: "重启", symbol: LuckySymbol.restart),
        ServiceVerb(id: "pause", label: "暂停", symbol: "pause.fill"),
        ServiceVerb(id: "unpause", label: "恢复", symbol: LuckySymbol.start),
    ]

    var body: some View {
        shell
            .luckyScene(scene)
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
            .sheet(item: $editor) { request in
                editorSheet(request)
            }
            .sheet(isPresented: $adding) {
                SslCertificateAddSheet(busy: saving, syncClients: syncClients) {
                    adding = false
                } save: { value in
                    save(ServiceEditorRequest(title: "添加 SSL 证书"), value)
                }
            }
            .sheet(item: $advanced) { request in
                advancedSheet(request)
            }
            .task { await loadList() }
            .task(id: selectedKey) {
                guard !selectedKey.isEmpty else { return }
                await loadDetail(selectedKey)
            }
            .task(id: logTaskID) { await pollLogs() }
            .task(id: needsSyncClients) {
                guard needsSyncClients else { return }
                await loadSyncClients()
            }
    }

    // MARK: - Layout

    /// `<Page scrollable={false}>`: the scene strip and mode switch stay above the active branch,
    /// while the command deck is attached directly to the bottom safe area. Only the list scrolls.
    @ViewBuilder
    private var shell: some View {
        if hasActionBar {
            frame.safeAreaBar(edge: .bottom) { commandDeck }
        } else {
            frame
        }
    }

    private var frame: some View {
        ZStack {
            LuckyBackdrop()
            VStack(spacing: 0) {
                header
                if mode == .logs { logsBranch } else { listBranch }
            }
        }
    }

    private var scene: LuckySceneDescriptor {
        let health: LuckyHealthState
        if !actionFailure.isEmpty || !editorFailure.isEmpty || !listFailure.isEmpty {
            health = .critical
        } else if fetching || logsFetching || detailFetching {
            health = .attention
        } else if loaded {
            health = .nominal
        } else {
            health = .unknown
        }
        return LuckySceneDescriptor(
            module: .services,
            title: kind.title,
            subtitle: kind.subtitle,
            symbol: kind.symbol,
            tone: kind.tone,
            health: health
        )
    }

    private var hasActionBar: Bool {
        mode == .list ? (kind == .ddns || kind == .ssl) : (logMode == .page)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.m) {
            LuckySceneStrip(scene)
            LuckyGlassSegmentedControl(
                selection: modeSelection,
                segments: [
                    LuckySegment(Mode.list, "列表", symbol: "list.bullet"),
                    LuckySegment(Mode.logs, "日志", symbol: LuckySymbol.logs),
                ]
            )
            // `{mutation.error ? <ErrorState /> : null}` and the editor's own failure. The original
            // mounts three of these — one per mutation — but ddns and ssl cannot both be live on a
            // screen that has a single kind.
            if !actionFailure.isEmpty {
                LuckyErrorCard(message: actionFailure)
            }
            if !editorFailure.isEmpty {
                LuckyErrorCard(message: editorFailure)
            }
        }
        .padding(.horizontal, LuckyTheme.Space.gutter)
        .padding(.bottom, LuckyTheme.Space.m)
    }

    private var commandDeck: some View {
        LuckyCommandDeck(context: commandContext) {
            actionBar
        }
    }

    private var commandContext: LuckyCommandContext {
        if mode == .logs {
            return LuckyCommandContext(
                title: logKey == nil ? "模块日志" : "配置日志",
                detail: pagerLabel,
                symbol: LuckySymbol.logs,
                tone: logsFailure.isEmpty ? kind.tone : .danger
            )
        }
        return LuckyCommandContext(
            title: kind.title,
            detail: "\(items.count) 项配置",
            symbol: kind.symbol,
            tone: actionFailure.isEmpty && editorFailure.isEmpty ? kind.tone : .danger
        )
    }

    @ViewBuilder
    private var actionBar: some View {
        if mode == .list {
            LuckyPillButton(title: kind == .ssl ? "添加证书" : "添加任务", symbol: LuckySymbol.add,
                            prominent: true) {
                openAdd()
            }
            LuckyPillButton(title: "模块设置", symbol: "gearshape.2") { openSettingsEditor() }
            LuckyGlassIconButton(symbol: "list.number",
                                 label: kind == .ssl ? "证书排序" : "排序和测试工具") {
                openOrdering()
            }
        } else {
            LuckyGlassIconButton(symbol: "chevron.left", label: "上一页日志") {
                logPage = max(1, logPage - 1)
            }
            .disabled(logPage <= 1 || logsFetching)
            Text(pagerLabel)
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textSecondary)
                .monospacedDigit()
                .frame(minWidth: 82, maxWidth: .infinity)
            LuckyGlassIconButton(symbol: "chevron.right", label: "下一页日志") { logPage += 1 }
                .disabled(logsFetching || !(logs?.hasMore ?? false))
        }
    }

    /// `` logsQuery.data?.total === undefined ? `第 ${logPage} 页` : `${logPage} / ${…}` ``, with the
    /// ceiling done in integers because `pageSize` is guaranteed positive by `LuckyLogPage`.
    private var pagerLabel: String {
        guard let logs, let total = logs.total else { return "第 \(logPage) 页" }
        let size = max(1, logs.pageSize)
        return "\(logPage) / \(max(1, (total + size - 1) / size))"
    }

    private var listBranch: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LuckyTheme.Space.m) {
                if !listFailure.isEmpty {
                    LuckyErrorCard(message: listFailure) { Task { await loadList() } }
                }
                if !loaded {
                    LuckySkeleton(rows: 4)
                }
                if !items.isEmpty {
                    LuckyDataRail(title: kind.title, subtitle: "\(items.count) 项配置", tone: kind.tone) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                row(item, index)
                                if index < items.count - 1 { LuckyHairline() }
                            }
                        }
                    }
                }
                if loaded, listFailure.isEmpty, items.isEmpty {
                    LuckyEmptyState(symbol: LuckySymbol.kind(kind), title: "接口未返回列表数据")
                }
            }
            .padding(.horizontal, LuckyTheme.Space.gutter)
            .padding(.bottom, LuckyTheme.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollIndicators(.hidden)
        .refreshable { await loadList() }
    }

    /// The log half. `LuckyLogView` scrolls internally, so this branch is a non-scrolling stack
    /// that hands it the remaining height — the same shape `LogsScreen` uses.
    private var logsBranch: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.m) {
            logControls
            if !logsFailure.isEmpty {
                LuckyErrorCard(message: logsFailure) { Task { await loadLogs() } }
            }
            if let lines = logs?.lines, !lines.isEmpty {
                LuckyLogView(lines: lines, follows: false, height: nil)
                    .clipShape(RoundedRectangle(cornerRadius: LuckyTheme.Radius.card,
                                                style: .continuous))
                Text("本页显示 \(lines.count) 行")
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if logsFetching {
                // The original renders nothing at all while the first page is in flight; a blank
                // screen reads as a failure, so the port says what it is doing.
                LuckyLoadingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if logsFailure.isEmpty {
                LuckyEmptyState(symbol: LuckySymbol.logs, title: "暂无日志")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, LuckyTheme.Space.gutter)
        .padding(.bottom, LuckyTheme.Space.m)
    }

    private var logControls: some View {
        HStack(spacing: LuckyTheme.Space.s) {
            if logKey != nil {
                ServiceActionButton(title: "查看模块日志", fill: .muted, height: 36, radius: 9,
                                    expands: false) {
                    logKey = nil
                    logPage = 1
                }
            }
            ServiceActionButton(title: logMode == .recent ? "最近日志" : "分页日志",
                                symbol: LuckySymbol.restart,
                                tone: logMode == .recent ? .brand : .idle,
                                fill: logMode == .recent ? .soft : .muted,
                                height: 36, radius: 9, expands: false) {
                logMode = logMode == .recent ? .page : .recent
                logPage = 1
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Rows

    /// One operational record on the shared rail. Its disclosure button covers only the identity
    /// band; toggles and verbs remain sibling controls so they never become nested button content.
    @ViewBuilder
    private func row(_ item: LuckyListItem, _ index: Int) -> some View {
        let key = ServiceRecord.key(item, index)
        let name = ServiceRecord.displayName(item, kind: kind, index: index)
        VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            rowHeader(item, key: key, name: name)
            if kind == .ddns || kind == .ssl {
                enableRow(item, key: key)
            }
            if kind == .docker {
                dockerRow(key: key)
            }
            if kind == .ddns || kind == .ssl {
                primaryVerbs(item, key: key, name: name)
            }
            if kind != .webservice {
                secondaryVerbs(item, key: key, name: name)
            }
            if selectedKey == key {
                detailBlock()
            }
        }
        .padding(.horizontal, LuckyTheme.Space.m)
        .padding(.vertical, LuckyTheme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The tappable header. `onPress={() => setSelectedKey(expanded ? '' : key)}` — collapsing by
    /// clearing the key is also what disables `detailQuery`, so one piece of state does both jobs.
    private func rowHeader(_ item: LuckyListItem, key: String, name: String) -> some View {
        let expanded = selectedKey == key
        let summary = ServiceRecord.rowDetail(item, kind: kind)
        let status = ServiceRecord.rowStatus(item)
        let statusTone: LuckyTone = ServiceRecord.isHealthyStatus(status) ? .ok : .idle
        return Button {
            selectedKey = expanded ? "" : key
            detail = nil
            detailFailure = ""
        } label: {
            LuckyListRow(
                title: name,
                subtitle: summary.isEmpty ? nil : summary,
                symbol: kind.symbol,
                tone: kind.tone,
                chips: [LuckyChipSpec(status, tone: statusTone)],
                dot: statusTone,
                showsChevron: false
            ) {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LuckyTheme.textSecondary)
            }
            .padding(.horizontal, -LuckyTheme.Space.m)
            .padding(.vertical, -LuckyTheme.Space.s)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) \(status)")
        .accessibilityHint(expanded ? "收起详情" : "展开详情")
    }

    /// The 启用 switch. `onValueChange` confirms before mutating, so the binding's setter never
    /// writes: the toggle springs back and only the reloaded list moves it.
    private func enableRow(_ item: LuckyListItem, key: String) -> some View {
        let on = ServiceRecord.isEnabled(item)
        return HStack(spacing: LuckyTheme.Space.m) {
            Text("启用")
                .font(LuckyTheme.Text.label)
                .foregroundStyle(LuckyTheme.textSecondary)
            Spacer(minLength: LuckyTheme.Space.s)
            Toggle("", isOn: Binding(get: { on }, set: { confirmEnabled(key: key, enabled: $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(LuckyTheme.accent)
        }
        .frame(minHeight: 44)
        .disabled(pending)
    }

    /// The five Docker verbs. The original lays them out at `width: '31%'` with `flexWrap`, which
    /// is three per line on every phone — `LuckyTileGrid` reaches the same shape without the magic
    /// percentage, and reflows to five across on an iPad.
    private func dockerRow(key: String) -> some View {
        LuckyTileGrid(minimum: 96, spacing: LuckyTheme.Space.s) {
            ForEach(Self.dockerVerbs) { verb in
                ServiceActionButton(title: verb.label, symbol: verb.symbol, tone: .idle,
                                    fill: .outline, height: 38, disabled: pending) {
                    confirmAction(key: key, action: verb.id, label: verb.label)
                }
            }
        }
    }

    /// 同步/刷新 · 编辑 · 删除. SSL certificates that arrived from a sync source are re-pulled rather
    /// than re-issued, which is the only difference between the two kinds' first button.
    private func primaryVerbs(_ item: LuckyListItem, key: String, name: String) -> some View {
        let source = ServiceRecord.pick(item, ["AddFrom", "Type"], "file")
        let syncSource = kind == .ssl && source.jsTrimmed.lowercased() == "sync"
        let action = kind == .ddns ? "sync" : (syncSource ? "sync" : "flush")
        let label = kind == .ddns ? "手动同步" : (syncSource ? "同步证书" : "刷新证书")
        let title = kind == .ddns ? "同步" : (syncSource ? "同步" : "刷新")
        return HStack(spacing: 7) {
            ServiceActionButton(title: title, symbol: LuckySymbol.restart, fill: .solid,
                                disabled: pending) {
                confirmAction(key: key, action: action, label: label)
            }
            ServiceActionButton(title: "编辑", symbol: LuckySymbol.edit, fill: .muted,
                                disabled: pending) {
                openItemEditor(key: key)
            }
            ServiceActionButton(title: "删除", symbol: LuckySymbol.delete, tone: .danger,
                                fill: .soft, disabled: pending) {
                confirmRemove(key: key, name: name)
            }
        }
    }

    /// 更多操作 and 查看日志. Both are optional per kind and the original mounts them as two separate
    /// siblings, so a kind that shows both gets two stacked rows rather than one split row.
    @ViewBuilder
    private func secondaryVerbs(_ item: LuckyListItem, key: String, name: String) -> some View {
        if kind == .ddns || kind == .ssl {
            ServiceActionButton(title: "更多操作", symbol: "ellipsis", tone: .idle, fill: .muted,
                                height: 38, radius: 9) {
                advanced = ServiceAdvancedRequest(key: key, name: name, item: item)
            }
        }
        if kind == .docker || kind == .ssl {
            ServiceActionButton(title: "查看日志", symbol: LuckySymbol.logs, fill: .plain,
                                height: 38) {
                showLogs(key: key)
            }
        }
    }

    /// The expanded body: `<StructuredDataView value={detailValue(detailQuery.data)} />` behind a
    /// separator. The original shows nothing while the detail is in flight, so the port adds the
    /// spinner — an empty gap under a just-tapped row reads as a dead tap.
    @ViewBuilder
    private var detailBlockBody: some View {
        if !detailFailure.isEmpty {
            LuckyErrorCard(message: detailFailure) { Task { await loadDetail(selectedKey) } }
        }
        if let detail {
            StructuredDataView(value: ServiceRecord.detailValue(detail))
        } else if detailFetching {
            LuckyLoadingView()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func detailBlock() -> some View {
        LuckyCard(radius: LuckyTheme.Radius.row, padding: LuckyTheme.Space.m,
                  spacing: LuckyTheme.Space.s, tone: kind.tone, role: .evidence) {
            detailBlockBody
        }
        .padding(.top, 2)
    }

    // MARK: - Sheets

    /// `key={`${editor.type}-${editor.key ?? 'new'}`}` is `ServiceEditorRequest.id`, so
    /// `.sheet(item:)` already remounts the editor whenever the subject changes.
    ///
    /// An ACME certificate gets the purpose-built editor; everything else — including a
    /// file-uploaded certificate and both 模块设置 records — gets the generic form.
    @ViewBuilder
    private func editorSheet(_ request: ServiceEditorRequest) -> some View {
        let source = ServiceRecord.pick(.object(request.value), ["AddFrom", "Type"], "file")
        if kind == .ssl, request.target == .item, source.lowercased() == "acme" {
            SslAcmeEditor(request: request, busy: saving, syncClients: syncClients) {
                editor = nil
            } save: { value in
                save(request, value)
            }
        } else {
            ServiceFormEditor(request: request, busy: saving) {
                editor = nil
            } save: { value in
                save(request, value)
            }
        }
    }

    /// `kind={kind === 'ssl' ? 'ssl' : 'ddns'}` — 高级操作 is only reachable from those two lists,
    /// and the normalisation keeps the sheet from having to know about the other two.
    private func advancedSheet(_ request: ServiceAdvancedRequest) -> some View {
        ServiceAdvancedSheet(
            kind: kind == .ssl ? .ssl : .ddns,
            itemKey: request.key,
            name: request.name,
            item: request.item,
            orderKeys: items.enumerated().map { ServiceRecord.key($1, $0) },
            close: { advanced = nil },
            reorder: { keys in try await reorder(keys) },
            changed: { await loadList() },
            showLogs: {
                advanced = nil
                showLogs(key: request.key)
            }
        )
    }

    // MARK: - Derived state

    /// `onPress={() => { setView(value); if (value === 'logs') setLogKey(undefined); }}`.
    ///
    /// A proxy binding rather than `.onChange(of: mode)` because the original clears the key on
    /// every tap of 日志, including a tap on the already-selected segment — and `onChange` only
    /// fires when the value actually differs.
    private var modeSelection: Binding<Mode> {
        Binding(get: { mode }, set: { value in
            mode = value
            if value == .logs { logKey = nil }
        })
    }

    private var confirming: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    /// Everything `logsQuery` keys on, plus the poll gate. `.task(id:)` restarts on any change,
    /// which is both the refetch and the `refetchInterval` reset that react-query does implicitly.
    private var logTaskID: String {
        let live = mode == .logs && phase == .active
        return "\(live)|\(logKey ?? "")|\(logPage)|\(logMode.rawValue)"
    }

    /// `enabled: kind === 'ssl' && (sslAddOpen || sslEditor?.type === 'item')`.
    private var needsSyncClients: Bool {
        kind == .ssl && (adding || editor?.target == .item)
    }

    // MARK: - Confirmations

    /// `confirmAction(key, action, label)` — 取消 / 继续, where the message names the module.
    private func confirmAction(key: String, action: String, label: String) {
        confirmation = ServiceConfirmation(
            title: "确认\(label)",
            message: "该操作会修改 \(kind.title) 的运行状态，是否继续？",
            confirm: "继续"
        ) {
            Task { await perform(key: key, action: action) }
        }
    }

    /// `confirmEnabled(key, enabled)` — the confirm button carries the verb, and only 停用 is
    /// styled destructive.
    private func confirmEnabled(key: String, enabled: Bool) {
        let label = enabled ? "启用" : "停用"
        confirmation = ServiceConfirmation(
            title: "确认\(label)",
            message: "是否\(label)这项\(kind.title)配置？",
            confirm: label,
            destructive: !enabled
        ) {
            Task { await perform(key: key, enabled: enabled) }
        }
    }

    private func confirmRemove(key: String, name: String) {
        let noun = kind == .ssl ? "SSL 证书" : "DDNS 任务"
        confirmation = ServiceConfirmation(
            title: "确认删除",
            message: "确定删除\(noun)“\(name)”吗？",
            confirm: "删除"
        ) {
            Task { await remove(key: key) }
        }
    }

    // MARK: - Mutations

    /// `mutation` with an `action`. `pending` is the port's `isPending`, and the guard is what
    /// react-query gets for free by disabling every button while a mutation is in flight.
    private func perform(key: String, action: String) async {
        guard !pending else { return }
        pending = true
        actionFailure = ""
        defer { pending = false }
        do {
            try await LuckyService.runAction(kind, key: key, action: action)
            await reloadAfterMutation()
        } catch {
            guard !error.isCancellation else { return }
            actionFailure = error.luckyMessage()
        }
    }

    private func perform(key: String, enabled: Bool) async {
        guard !pending else { return }
        pending = true
        actionFailure = ""
        defer { pending = false }
        do {
            try await LuckyService.setEnabled(kind, key: key, enabled: enabled)
            await reloadAfterMutation()
        } catch {
            guard !error.isCancellation else { return }
            actionFailure = error.luckyMessage()
        }
    }

    /// `onSuccess` — invalidate the list, then the open detail. The order matters: the detail read
    /// is the slower of the two and the row's own fields come from the list.
    private func reloadAfterMutation() async {
        await loadList()
        guard !selectedKey.isEmpty else { return }
        await loadDetail(selectedKey)
    }

    /// `removeDdnsTask` / `removeSslCertificate`. The original reports the failure through
    /// `Alert.alert('删除失败', …)`; a toast says the same thing without a second tap.
    private func remove(key: String) async {
        guard !pending else { return }
        pending = true
        defer { pending = false }
        do {
            if kind == .ssl {
                try await SslService.delete(key)
            } else {
                try await DdnsService.delete(key)
            }
            if selectedKey == key { selectedKey = "" }
            await loadList()
        } catch {
            guard !error.isCancellation else { return }
            toast = .failed(error.luckyMessage("删除失败"))
        }
    }

    /// `reorderServiceTasks(keys)` — the sheet awaits this, so the failure travels back to it and
    /// the list only reloads on success.
    private func reorder(_ keys: [String]) async throws {
        let payload = JSONValue.array(keys.map { JSONValue.string($0) })
        if kind == .ssl {
            try await SslService.reorderCertificates(payload)
        } else {
            try await DdnsService.reorderTasks(payload)
        }
        await loadList()
    }

    /// `ddnsMutation` / `sslMutation`. One method for both because the branch is the same shape:
    /// settings go to the module endpoint, an item with a key updates and one without creates.
    private func save(_ request: ServiceEditorRequest, _ value: JSONObject) {
        Task { await commit(request, value) }
    }

    private func commit(_ request: ServiceEditorRequest, _ value: JSONObject) async {
        guard !saving else { return }
        saving = true
        editorFailure = ""
        defer { saving = false }
        let payload = JSONValue.object(value)
        do {
            if kind == .ssl {
                if request.target == .settings {
                    try await SslService.updateSetting(payload)
                } else if request.key.isEmpty {
                    try await SslService.create(payload)
                } else {
                    try await SslService.update(payload)
                }
            } else {
                if request.target == .settings {
                    try await DdnsService.updateConfigure(payload)
                } else if request.key.isEmpty {
                    try await DdnsService.create(payload)
                } else {
                    try await DdnsService.update(request.key, payload)
                }
            }
            editor = nil
            adding = false
            await reloadAfterMutation()
        } catch {
            guard !error.isCancellation else { return }
            editorFailure = error.luckyMessage()
        }
    }

    // MARK: - Opening the editors

    /// 添加任务 / 添加证书. A new DDNS task starts from the three fields the module requires; a new
    /// certificate goes to the purpose-built ACME sheet instead of an empty form.
    private func openAdd() {
        editorFailure = ""
        if kind == .ssl {
            adding = true
        } else {
            editor = ServiceEditorRequest(
                title: "添加 DDNS 任务",
                value: JSONObject([
                    ("TaskName", .string("")),
                    ("Enable", .bool(true)),
                    ("Records", .array([])),
                ])
            )
        }
    }

    /// `editDdnsTask` / `editSslCertificate` — read the record first, because the list payload is a
    /// summary and posting it back would drop every field the list does not carry.
    private func openItemEditor(key: String) {
        Task {
            editorFailure = ""
            do {
                let payload = kind == .ssl
                    ? try await SslService.certificate(key)
                    : try await DdnsService.task(key)
                editor = ServiceEditorRequest(
                    title: kind == .ssl ? "编辑 SSL 证书" : "编辑 DDNS 任务",
                    value: ServiceRecord.editableValue(payload).record,
                    key: key
                )
            } catch {
                guard !error.isCancellation else { return }
                let fallback = kind == .ssl ? "无法读取 SSL 证书" : "无法读取 DDNS 任务"
                toast = .failed(error.luckyMessage(fallback))
            }
        }
    }

    /// `editDdnsConfigure` / `editSslSetting` — the module's own record, edited by the same form.
    private func openSettingsEditor() {
        Task {
            editorFailure = ""
            do {
                let payload = kind == .ssl
                    ? try await SslService.setting()
                    : try await DdnsService.configure()
                editor = ServiceEditorRequest(
                    target: .settings,
                    title: kind == .ssl ? "SSL 模块设置" : "DDNS 模块设置",
                    value: ServiceRecord.editableValue(payload).record
                )
            } catch {
                guard !error.isCancellation else { return }
                let fallback = kind == .ssl ? "无法读取 SSL 设置" : "无法读取 DDNS 设置"
                toast = .failed(error.luckyMessage(fallback))
            }
        }
    }

    /// `showLogs(key?)`. The mode is assigned directly rather than through `modeSelection`, which
    /// would clear the key this call just set.
    private func showLogs(key: String? = nil) {
        logKey = key
        logPage = 1
        logMode = .page
        mode = .logs
    }

    /// `openOrdering()` — 排序 has no screen of its own; it opens 高级操作 on the first item, which is
    /// where the reorder list lives.
    private func openOrdering() {
        guard let first = items.first else {
            toast = .note("请先添加一项配置")
            return
        }
        advanced = ServiceAdvancedRequest(
            key: ServiceRecord.key(first, 0),
            name: ServiceRecord.orderingName(first, kind: kind),
            item: first
        )
    }

    // MARK: - Loading

    private func loadList() async {
        guard !fetching else { return }
        fetching = true
        defer {
            fetching = false
            loaded = true
        }
        do {
            items = try await LuckyService.items(kind).items
            listFailure = ""
        } catch {
            guard !error.isCancellation else { return }
            listFailure = error.luckyMessage()
        }
    }

    /// `detailQuery`, driven by `.task(id: selectedKey)` — collapsing a row empties the key, which
    /// is exactly the `enabled: Boolean(selectedKey)` gate.
    private func loadDetail(_ key: String) async {
        detailFetching = true
        detailFailure = ""
        defer { detailFetching = false }
        do {
            detail = try await LuckyService.detail(kind, key: key)
        } catch {
            guard !error.isCancellation else { return }
            detailFailure = error.luckyMessage()
        }
    }

    private func loadLogs() async {
        logsFetching = true
        logsFailure = ""
        defer { logsFetching = false }
        do {
            if logMode == .recent {
                logs = try await LuckyService.serviceLastLogs(kind, key: logKey)
            } else {
                logs = try await LuckyService.serviceLogs(kind, key: logKey, page: logPage)
            }
        } catch {
            guard !error.isCancellation else { return }
            logsFailure = error.luckyMessage()
        }
    }

    /// `refetchInterval: 10000` when `logsEnabled && isFocused && (logMode === 'recent' || logPage
    /// === 1)`, with `refetchIntervalInBackground: false`.
    ///
    /// The loop is the whole gate: `.task(id: logTaskID)` is cancelled — and so is the sleep —
    /// whenever the mode, key, page or scene phase changes, or the screen is popped.
    private func pollLogs() async {
        guard mode == .logs, phase == .active else { return }
        await loadLogs()
        guard logMode == .recent || logPage == 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await loadLogs()
        }
    }

    /// The distribution picker's options. The original never surfaces this query's error — an empty
    /// list reads as "this server has no sync clients", which is the common case anyway.
    private func loadSyncClients() async {
        do {
            syncClients = try await SslService.syncClientOptions()
        } catch {
            syncClients = []
        }
    }

    /// `onRefresh={() => view === 'logs' && logsEnabled ? logsQuery.refetch() : query.refetch()}`.
    private func refresh() async {
        if mode == .logs {
            await loadLogs()
        } else {
            await loadList()
        }
    }
}
