import SwiftUI

/// The module-level helpers of `app/tunnels/[kind].tsx` — `text`, `itemKey`, `itemName`, the strict
/// `enabled`, the `icons` and `collectionTitles` tables, and the row's state and summary lines.
///
/// A namespace of its own rather than an extension on `JSONValue`, because `ServiceRecord` already
/// owns same-named helpers for the eight service modules and the two disagree about what reads as
/// enabled: these three modules answer with exactly three spellings and nothing else counts.
enum TunnelRecord {
    /// `text(value)` — a string or a number prints itself, and everything else, a boolean included,
    /// becomes the empty string. Most of the screen's `||` fallbacks turn on that last part.
    static func text(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        switch value {
        case .string(let inner): return inner
        case .number(let number): return JSONSerializer.numberString(number)
        default: return ""
        }
    }

    /// `a ?? b ?? c` over a record's keys: `??` steps past a missing key and an explicit null but
    /// stops at `false`, `0` and `''`.
    static func first(_ value: JSONValue, _ keys: [String]) -> JSONValue? {
        for key in keys {
            guard let found = value[key], !found.isNull else { continue }
            return found
        }
        return nil
    }

    /// `itemKey(item)` — the identity every request on this screen is addressed by.
    static func key(_ item: JSONValue) -> String { text(item["Key"]) }

    /// `itemName(item)`. STUN rules carry `Name`, the other two carry `Remark`, and a child record
    /// carries the lowercase `name`.
    static func name(_ item: JSONValue) -> String {
        let found = text(first(item, ["Name", "Remark", "name"]))
        return found.isEmpty ? "未命名" : found
    }

    /// `enabled(item)` — `Enable === true || Enable === 1 || Enable === 'true'`.
    ///
    /// Deliberately not `ServiceRecord.isEnabled`, which reads any truthy value as on: a rule whose
    /// `Enable` is the string `"1"` shows as stopped in the original too, and the switch below has
    /// to agree with the list it was drawn from or it will flicker on every poll.
    static func isEnabled(_ item: JSONValue) -> Bool {
        guard let value = item["Enable"] else { return false }
        if value.boolValue == true { return true }
        if value.doubleValue == 1 { return true }
        return value.stringValue == "true"
    }

    /// `record(item.Params)`, as a value so `first` can walk it.
    static func params(_ item: JSONValue) -> JSONValue { .object((item["Params"] ?? .null).record) }

    /// `icons[kind]`, drawn from the shared module table so that a STUN rule here and the STUN
    /// entry in 模块 carry the same mark.
    static func symbol(_ kind: TunnelKind) -> String { LuckySymbol.module(kind.rawValue) }

    /// `collectionTitles[mode]`. `TunnelCollection` itself stays free of display copy — it is the
    /// service layer's type and names the request field, not the heading.
    static func title(_ collection: TunnelCollection) -> String {
        switch collection {
        case .ingress: return "域名路由"
        case .proxies: return "代理规则"
        case .visitors: return "访问者"
        }
    }
}

// MARK: - Row copy

extension TunnelRecord {
    /// The row's state word. `Running` is only consulted when the module actually sent a boolean —
    /// `typeof item.Running === 'boolean'` — so a rule that omits it falls through to `Status`,
    /// then to `State`, and only then to the enabled flag.
    static func state(_ item: JSONValue) -> String {
        if let running = item["Running"], running.isBool {
            return running.boolValue == true ? "运行中" : "未运行"
        }
        let reported = text(first(item, ["Status", "State"]))
        guard reported.isEmpty else { return reported }
        return isEnabled(item) ? "已启用" : "已停用"
    }

    /// The chip's colour, decided on the same three-step fallback as the word itself.
    ///
    /// `LuckyTone.state` cannot be asked about 已启用 / 已停用: its vocabulary is the Docker and task
    /// spellings, and those two words are this screen's own invention, so they resolve here.
    static func tone(_ item: JSONValue) -> LuckyTone {
        if let running = item["Running"], running.isBool {
            return running.boolValue == true ? .ok : .idle
        }
        let reported = text(first(item, ["Status", "State"]))
        guard reported.isEmpty else { return LuckyTone.state(reported) }
        return isEnabled(item) ? .ok : .idle
    }

    /// The row's one-line summary — a different shape per module, all three built from `text`, so a
    /// missing field leaves a bare separator behind exactly as the template literal does.
    static func summary(_ item: JSONValue, kind: TunnelKind) -> String {
        switch kind {
        case .stun: return stunSummary(item)
        case .frp: return frpSummary(item)
        case .cloudflared:
            guard text(item["Type"]) == "access" else { return "Cloudflare Tunnel" }
            return "Access · \(text(params(item)["Hostname"]))"
        }
    }

    /// The STUN shape: the listen pair, an arrow, the joined `TargetAddressList` and the target
    /// port — with `'自动监听'` and `'自动'` standing in for an unset IP or port.
    ///
    /// `join` is not `text`: it renders a boolean as `true` and a record as `[object Object]`,
    /// while a null entry collapses to the empty string — which is what `TunnelSpec.stringify`
    /// reproduces.
    private static func stunSummary(_ item: JSONValue) -> String {
        let listen = text(item["ListenIP"])
        let port = text(item["ListenPort"])
        let targets = (item["TargetAddressList"]?.arrayValue ?? [])
            .map { $0.isNull ? "" : TunnelSpec.stringify($0) }
            .joined(separator: ", ")
        let head = "\(listen.isEmpty ? "自动监听" : listen):\(port.isEmpty ? "自动" : port)"
        return "\(head) → \(targets):\(text(item["TargetPort"]))"
    }

    /// A server instance binds a port and a client dials one, so the two halves of the address come
    /// from different keys and `??` picks whichever the record carries.
    private static func frpSummary(_ item: JSONValue) -> String {
        let role = text(item["Type"]) == "server" ? "服务端" : "客户端"
        let inner = params(item)
        let host = text(first(inner, ["ServerAddr", "BindAddr"]))
        let port = text(first(inner, ["ServerPort", "BindPort"]))
        return "\(role) · \(host):\(port)"
    }

    /// `text(child.name ?? child.hostname) || '默认路由'` — a catch-all ingress rule has neither.
    static func childTitle(_ child: JSONValue) -> String {
        let found = text(first(child, ["name", "hostname"]))
        return found.isEmpty ? "默认路由" : found
    }

    /// The child row's summary, one shape per collection.
    static func childSummary(_ child: JSONValue, collection: TunnelCollection) -> String {
        let type = text(child["type"]).uppercased()
        switch collection {
        case .ingress:
            let path = text(child["path"])
            return "\(path.isEmpty ? "/" : path) → \(text(child["service"]))"
        case .proxies:
            // `remotePort || serverName || '域名代理'`: a visitor-style proxy publishes a name
            // instead of a port, and a plugin proxy publishes neither.
            var target = text(child["remotePort"])
            if target.isEmpty { target = text(child["serverName"]) }
            if target.isEmpty { target = "域名代理" }
            let local = "\(text(child["localIP"])):\(text(child["localPort"]))"
            return "\(type) · \(local) → \(target)"
        case .visitors:
            let bind = "\(text(child["bindAddr"])):\(text(child["bindPort"]))"
            return "\(type) · \(bind) → \(text(child["serverName"]))"
        }
    }
}

// MARK: - Modal subjects

/// `editor` — the subject of the editor modal, for any of the seven form types.
///
/// `id` is a fresh `UUID` per open rather than something derived from the record, because the
/// original's modal remounts on every `setEditor` and `useState(() => structuredClone(value))` is
/// what makes a half-typed record from the previous open impossible to inherit.
struct TunnelEditor: Identifiable {
    let id = UUID()
    var title: String
    var type: TunnelFormType
    var value: JSONObject
    /// The child as it stood before the edit — `saveChild` sends it so the module can find the row
    /// it is replacing when the name or path has changed.
    var previous: JSONValue?
    /// The rule a child form belongs to. Nil for the six top-level forms.
    var parent: JSONValue?
    var editing: Bool
}

/// `detail` — the subject of the logs / 运行详情 / child-list modal.
struct TunnelDetail: Identifiable {
    /// `'logs' | 'status' | 'ingress' | 'proxies' | 'visitors'`, as a type that cannot hold a
    /// collection name the service layer does not know.
    enum Mode: Equatable, Sendable {
        case logs
        case status
        case collection(TunnelCollection)

        /// Part of the original's query key, and so part of the `.task(id:)` that stands in for it.
        var slug: String {
            switch self {
            case .logs: return "logs"
            case .status: return "status"
            case .collection(let collection): return collection.rawValue
            }
        }

        /// The first half of the modal's title.
        var title: String {
            switch self {
            case .logs: return "日志"
            case .status: return "运行详情"
            case .collection(let collection): return TunnelRecord.title(collection)
            }
        }

        var collection: TunnelCollection? {
            guard case .collection(let collection) = self else { return nil }
            return collection
        }
    }

    let id = UUID()
    var mode: Mode
    /// The rule the modal belongs to, or an empty record for the module-wide log.
    var item: JSONValue
}

// MARK: - The screen

/// `TunnelScreen({kind})` — 内网穿透, one screen for STUN, Cloudflared and FRP alike.
///
/// The three modules disagree about what a rule is and about which verbs it exposes, but they share
/// one list, one editor, one five-second poll and one reorder endpoint, which is why the original
/// keeps them in a single dynamic route instead of three screens.
struct TunnelScreen: View {
    var kind: TunnelKind

    /// `AppState.currentState !== 'background'`. The original ands that with `useIsFocused`, but a
    /// pushed SwiftUI screen only exists while it is on top of its stack, so the focus half of
    /// `active` needs no equivalent here.
    @Environment(\.scenePhase) private var phase

    @State private var all: [LuckyListItem] = []
    @State private var raw: JSONValue = .object(JSONObject())
    @State private var listFailure = ""
    @State private var loaded = false
    @State private var fetching = false

    @State private var search = ""
    @State private var editor: TunnelEditor?
    @State private var detail: TunnelDetail?
    @State private var natOpen = false

    /// `error` and `notice` — the mutation banners, shared by every verb on the screen.
    @State private var failure = ""
    @State private var notice = ""
    @State private var pending = false
    @State private var loadingEditor = false

    @State private var page = 1
    @State private var detailValue: JSONValue?
    @State private var detailFailure = ""
    @State private var detailLoaded = false
    @State private var detailFetching = false
    @State private var dnsResult: JSONValue?

    @State private var toast: LuckyToast?
    @State private var confirmation: ServiceConfirmation?

    /// `operation.isPending || loadingEditor` — the flag every verb is disabled by.
    private var busy: Bool { pending || loadingEditor }

    /// The search filter. The haystack is the five fields the original joins, and the needle is
    /// trimmed while the haystack is not, so a rule named with a trailing space still matches.
    private var items: [LuckyListItem] {
        let needle = search.jsTrimmed.lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter { item in
            ["Name", "Remark", "Type", "StunType", "PublicAddr"]
                .map { TunnelRecord.text(item[$0]) }
                .joined(separator: " ")
                .lowercased()
                .contains(needle)
        }
    }

    var body: some View {
        frame
            .luckyActionBar { actionBar }
            .searchable(text: $search, prompt: "搜索名称、类型或公网地址")
            .searchToolbarBehavior(.minimize)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await loadList() }
                    } label: {
                        Image(systemName: LuckySymbol.refresh)
                    }
                    .disabled(fetching)
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
            .sheet(item: modalBinding) { modal in sheet(modal) }
            .task(id: listTaskID) { await pollList() }
            .task(id: detailTaskID) { await pollDetail() }
    }

    private var confirming: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }
}

// MARK: - The list

extension TunnelScreen {
    private var frame: some View {
        ZStack {
            LuckyBackdrop()
            list
        }
    }

    /// `<FlatList>` with its header and empty components. The header's action row has moved to the
    /// glass bar and its search field to the navigation bar, so what is left of it is four banners.
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LuckyTheme.Space.m) {
                banners
                if !loaded {
                    LuckySkeleton(rows: 4)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    row(item)
                }
                emptyState
            }
            .padding(.horizontal, LuckyTheme.Space.gutter)
            .padding(.top, LuckyTheme.Space.s)
            .padding(.bottom, LuckyTheme.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollIndicators(.hidden)
        .refreshable { await loadList() }
    }

    /// The mutation error, the list error, the success notice and the 模块未启用 warning, in the
    /// order the original stacks them.
    @ViewBuilder
    private var banners: some View {
        if !failure.isEmpty {
            LuckyErrorCard(message: failure, title: "操作失败")
        }
        if !listFailure.isEmpty {
            LuckyErrorCard(message: listFailure) { Task { await loadList() } }
        }
        if !notice.isEmpty {
            Text(notice)
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.success)
        }
        // `list.data?.raw.ModuleEnable === false` — strictly false, so a module that omits the flag
        // is assumed on. Only STUN reports it.
        if kind == .stun, raw["ModuleEnable"]?.boolValue == false {
            Text("STUN 模块未启用")
                .font(LuckyTheme.Text.label)
                .foregroundStyle(LuckyTheme.warning)
        }
        if loadingEditor {
            LuckyLoadingView(text: "读取配置中…")
        }
    }

    /// `ListEmptyComponent`. The failed case draws nothing, because the error card above already
    /// explains it; the loading case is the skeleton's job. `search` is tested untrimmed, as it is
    /// in the original, so a needle of one space reports 没有匹配的规则 rather than 暂无规则.
    @ViewBuilder
    private var emptyState: some View {
        if loaded, listFailure.isEmpty, items.isEmpty {
            LuckyEmptyState(symbol: TunnelRecord.symbol(kind),
                            title: search.isEmpty ? "暂无规则" : "没有匹配的规则")
        }
    }

    /// The original's wrapping 新增 / 全局设置 / NAT 检测 / 模块日志 row, lifted out of the scroll
    /// view: glass may not sit inside scrolling content, and this bar is where it belongs.
    @ViewBuilder
    private var actionBar: some View {
        LuckyPillButton(title: "新增", symbol: LuckySymbol.add, prominent: true) {
            Task { await openEditor() }
        }
        .disabled(busy)
        if kind == .stun {
            LuckyGlassIconButton(symbol: LuckySymbol.settings, label: "全局设置") {
                Task { await openEditor(settings: true) }
            }
            .disabled(busy)
            LuckyGlassIconButton(symbol: LuckySymbol.network, label: "NAT 检测") {
                natOpen = true
            }
            .disabled(busy)
        } else {
            LuckyGlassIconButton(symbol: LuckySymbol.logs, label: "模块日志") {
                openDetail(.logs, .object(JSONObject()))
            }
            .disabled(busy)
        }
    }
}

// MARK: - Rows

extension TunnelScreen {
    /// One `Panel`. `index` is the row's place in the *unfiltered* list, because that is what 上移
    /// and 下移 reorder — searching the list does not change what a swap means.
    private func row(_ item: LuckyListItem) -> some View {
        let key = TunnelRecord.key(item)
        let index = all.firstIndex { TunnelRecord.key($0) == key } ?? -1
        return LuckyCard(spacing: LuckyTheme.Space.s) {
            rowHeader(item, key: key)
            Text(TunnelRecord.summary(item, kind: kind))
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textSecondary)
                .textSelection(.enabled)
            if kind == .stun {
                publicAddress(item)
            }
            verbs(item, key: key, index: index)
        }
    }

    private func rowHeader(_ item: LuckyListItem, key: String) -> some View {
        let name = TunnelRecord.name(item)
        let state = TunnelRecord.state(item)
        let type = TunnelRecord.text(item["StunType"])
        return HStack(alignment: .top, spacing: LuckyTheme.Space.m) {
            LuckyIconTile(symbol: TunnelRecord.symbol(kind))
            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(LuckyTheme.Text.bodyMedium)
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .lineLimit(2)
                // `{text(item.StunType)} {state}` — one caption in the original, a word plus a chip
                // here, which also drops the leading space the template emits without a `StunType`.
                HStack(spacing: LuckyTheme.Space.xs) {
                    if !type.isEmpty {
                        Text(type)
                            .font(LuckyTheme.Text.caption)
                            .foregroundStyle(LuckyTheme.textSecondary)
                    }
                    LuckyChip(text: state, tone: TunnelRecord.tone(item))
                }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { TunnelRecord.isEnabled(item) },
                                     set: { next in toggleRule(key: key, enable: next) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(LuckyTheme.accent)
                .disabled(busy || key.isEmpty)
                .accessibilityLabel("启用 \(name)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `公网地址：{PublicAddr || '等待穿透'}`. The colour follows the raw value's truthiness while the
    /// text goes through `text`, so a `PublicAddr` the module answers as `true` prints 等待穿透 in
    /// green — a contradiction the original also draws, and one that says the field is malformed.
    private func publicAddress(_ item: LuckyListItem) -> some View {
        let address = TunnelRecord.text(item["PublicAddr"])
        let present = item["PublicAddr"]?.isTruthy == true
        return Text("公网地址：\(address.isEmpty ? "等待穿透" : address)")
            .font(LuckyTheme.Text.label)
            .foregroundStyle(present ? LuckyTheme.success : LuckyTheme.textSecondary)
            .textSelection(.enabled)
    }
}

// MARK: - Verbs

extension TunnelScreen {
    /// The row's verb row. `flexGrow: 1, flexBasis: 105` under `flexWrap` is an adaptive grid with
    /// a 105pt minimum, and the original's `primarySoft` / `dangerBg` fills are both `.soft`.
    private func verbs(_ item: LuckyListItem, key: String, index: Int) -> some View {
        LuckyTileGrid(minimum: 105, spacing: 7) {
            verb("编辑", LuckySymbol.edit, disabled: busy || key.isEmpty) {
                Task { await openEditor(item) }
            }
            verb("日志", LuckySymbol.logs, disabled: busy || key.isEmpty) {
                openDetail(.logs, item)
            }
            childVerbs(item, key: key)
            // The one verb the original leaves enabled during a mutation: it writes to the
            // pasteboard, not to the server.
            if kind == .stun, item["PublicAddr"]?.isTruthy == true {
                verb("复制地址", LuckySymbol.copy, disabled: false) { copyAddress(item) }
            }
            verb("上移", "arrow.up", disabled: busy || key.isEmpty || index <= 0) {
                move(item, -1)
            }
            verb("下移", "arrow.down",
                 disabled: busy || key.isEmpty || index == all.count - 1) {
                move(item, 1)
            }
            verb("删除", LuckySymbol.delete, disabled: busy || key.isEmpty, tone: .danger) {
                confirm("删除 \(TunnelRecord.name(item))？") {
                    try await TunnelsService.delete(kind, key: key)
                }
            }
        }
    }

    /// The verbs only some of the modules carry: a Cloudflared tunnel publishes hostnames, an FRP
    /// instance always reports status, and only an FRP client owns proxies and visitors.
    @ViewBuilder
    private func childVerbs(_ item: LuckyListItem, key: String) -> some View {
        if kind == .cloudflared, item["Type"]?.stringValue == "tunnel" {
            verb("域名路由", "globe.asia.australia", disabled: busy || key.isEmpty) {
                openDetail(.collection(.ingress), item)
            }
        }
        if kind == .frp {
            verb("运行详情", LuckySymbol.monitor, disabled: busy || key.isEmpty) {
                openDetail(.status, item)
            }
            if item["Type"]?.stringValue == "client" {
                verb("代理规则", LuckySymbol.network, disabled: busy || key.isEmpty) {
                    openDetail(.collection(.proxies), item)
                }
                verb("访问者", "person.2.wave.2", disabled: busy || key.isEmpty) {
                    openDetail(.collection(.visitors), item)
                }
            }
        }
    }

    /// `<Action>` — 42pt tall, 12pt radius, a tinted fill, and dimmed rather than hidden when it
    /// does not apply, so the row's shape does not shift as a mutation runs.
    private func verb(_ title: String, _ symbol: String, disabled: Bool,
                      tone: LuckyTone = .brand,
                      action: @escaping () -> Void) -> some View {
        ServiceActionButton(title: title, symbol: symbol, tone: tone, fill: .soft, height: 42,
                            radius: 12, disabled: disabled, action: action)
    }
}

// MARK: - Opening

extension TunnelScreen {
    /// `openDetail(mode, item)`. The page starts at 0 — the module's 最新日志 endpoint — only for a
    /// rule's own log; the module-wide log has no live variant and so starts at page 1.
    ///
    /// The original's query cache would hand a re-opened modal its previous payload at once and
    /// refresh behind it; there is no cache here, so the panes clear and load again.
    private func openDetail(_ mode: TunnelDetail.Mode, _ item: JSONValue) {
        failure = ""
        dnsResult = nil
        page = (mode == .logs && !TunnelRecord.key(item).isEmpty) ? 0 : 1
        detailValue = nil
        detailFailure = ""
        detailLoaded = false
        detail = TunnelDetail(mode: mode, item: item)
    }

    /// `openEditor(item?, settings)`. A 新增 opens on the defaults without a request; everything else
    /// reads the record back first, because the list rows are summaries and posting one of those
    /// would drop every key the list does not carry.
    ///
    /// The original aborts an in-flight read before starting another; the `guard !busy` here
    /// already makes a second read impossible, so the abort controller has no counterpart.
    private func openEditor(_ item: JSONValue? = nil, settings: Bool = false) async {
        guard !busy else { return }
        failure = ""
        let type: TunnelFormType = settings ? .stunSettings : TunnelFormType(kind)
        guard item != nil || settings else {
            editor = TunnelEditor(title: "新增\(kind.title)", type: type,
                                  value: TunnelSpec.defaults(type), editing: false)
            return
        }
        loadingEditor = true
        defer { loadingEditor = false }
        let subject = item ?? .object(JSONObject())
        do {
            var value = JSONValue.object(JSONObject())
            if settings {
                value = try await TunnelsService.stunSettings()
            } else {
                value = try await TunnelsService.get(kind, key: TunnelRecord.key(subject))
            }
            let title = settings ? "STUN 全局设置" : "编辑 \(TunnelRecord.name(subject))"
            editor = TunnelEditor(title: title, type: type, value: value.record, editing: true)
        } catch {
            guard !error.isCancellation else { return }
            failure = error.luckyMessage("读取配置失败")
        }
    }

    /// `move(item, direction)` — a swap in the unfiltered order, posted as the whole key list.
    ///
    /// The missing-key complaint is written straight to the banner rather than thrown through the
    /// mutation, so it does not clear the notice or trigger a reload: nothing was sent.
    private func move(_ item: JSONValue, _ direction: Int) {
        let key = TunnelRecord.key(item)
        guard let index = all.firstIndex(where: { TunnelRecord.key($0) == key }) else { return }
        let target = index + direction
        guard target >= 0, target < all.count else { return }
        var keys = all.map { TunnelRecord.key($0) }
        guard !keys.contains(where: \.isEmpty) else {
            failure = "列表中缺少规则标识，无法排序"
            return
        }
        keys.swapAt(index, target)
        let ordered = keys
        Task { await operate { try await TunnelsService.reorder(kind, keys: ordered) } }
    }

    /// `operation.mutate(() => Clipboard.setStringAsync(…))`. A local copy is not a server change,
    /// so it reports through a toast instead of borrowing the mutation's 操作已完成 notice — and it
    /// skips the reload of the whole list that the original pays for.
    private func copyAddress(_ item: JSONValue) {
        LuckyClipboard.copy(TunnelRecord.text(item["PublicAddr"]))
        toast = .ok("已复制公网地址")
    }
}

// MARK: - Mutations

extension TunnelScreen {
    /// `operation` — the one mutation behind every verb on the screen, which is why the notice and
    /// the failure banner are shared, and why any success reloads both the list and the open modal.
    ///
    /// The closure is `@MainActor` because 检测 DNS writes its answer to `dnsResult` from inside it.
    private func operate(_ work: @MainActor @escaping () async throws -> Void) async {
        guard !pending else { return }
        pending = true
        failure = ""
        notice = ""
        defer { pending = false }
        do {
            try await work()
            notice = "操作已完成"
            await invalidate()
        } catch {
            guard !error.isCancellation else { return }
            failure = error.luckyMessage()
        }
    }

    /// `Alert.alert(title, '此操作将修改服务器配置。', […])` — the same two buttons for every verb that
    /// asks first, with the title carrying the whole question.
    private func confirm(_ title: String,
                         _ work: @MainActor @escaping () async throws -> Void) {
        confirmation = ServiceConfirmation(title: title, message: "此操作将修改服务器配置。",
                                           confirm: "确认") {
            Task { await operate(work) }
        }
    }

    /// `queryClient.invalidateQueries({ queryKey: ['tunnels', kind] })`. The key prefix covers the
    /// list and the details query alike, so both reload — the list first, since the rows are what
    /// the modal was opened from.
    private func invalidate() async {
        await loadList()
        guard detail != nil else { return }
        await loadDetail()
    }

    /// The row switch. Not confirmed: the original asks before the six changes it treats as
    /// destructive, and flipping a rule on or off is not one of them.
    private func toggleRule(key: String, enable: Bool) {
        Task {
            await operate { try await TunnelsService.setEnabled(kind, key: key, enable: enable) }
        }
    }

    /// `save(value)` — the editor sheet's `mutationFn`, so it throws and the sheet keeps the
    /// message rather than the list banner showing it. The success notice belongs to the screen.
    private func save(_ value: JSONObject) async throws {
        guard let editor else { return }
        let payload = JSONValue.object(value)
        if editor.type == .stunSettings {
            try await TunnelsService.saveStunSettings(payload)
        } else if let collection = editor.type.collection {
            guard kind != .stun else { throw LuckyError("操作类型无效") }
            let parent = TunnelRecord.key(editor.parent ?? .null)
            try await TunnelsService.saveChild(kind, key: parent, collection: collection,
                                              value: payload, previous: editor.previous)
        } else {
            try await saveRule(value, editing: editor.editing)
        }
        notice = "配置已保存"
        Task { await invalidate() }
    }

    /// The two runtime aliases a GET leaves behind. Dropping them is what stops a save from
    /// overwriting the child lists the detail modal owns — and it is the lowercase pair only,
    /// because `Proxies` and `Visitors` are the keys the defaults seed and the module expects back.
    private func saveRule(_ value: JSONObject, editing: Bool) async throws {
        var cleaned = value
        if kind == .frp {
            cleaned.removeValue(forKey: "proxies")
            cleaned.removeValue(forKey: "visitors")
        }
        try await TunnelsService.save(kind, value: .object(cleaned), editing: editing)
    }
}

// MARK: - Child records

extension TunnelScreen {
    /// 新增规则 — a child editor opened from inside the detail modal, which the single sheet replaces
    /// and then restores when the editor closes.
    private func addChild(_ collection: TunnelCollection, _ parent: JSONValue) {
        let type = TunnelFormType(collection)
        editor = TunnelEditor(title: "新增\(TunnelRecord.title(collection))", type: type,
                              value: TunnelSpec.defaults(type), parent: parent, editing: false)
    }

    /// 编辑 — `{ ...tunnelDefaults(mode), ...child }`, so a key the daemon's own config file omits
    /// still gets a field, and `previous` carries the child the module has to match to replace it.
    private func editChild(_ collection: TunnelCollection, _ parent: JSONValue,
                           _ child: JSONValue) {
        let type = TunnelFormType(collection)
        editor = TunnelEditor(title: "编辑规则", type: type,
                              value: TunnelSpec.defaults(type).merging(child.record),
                              previous: child, parent: parent, editing: true)
    }

    /// 启用 / 停用 — the same child saved back with `disabled` flipped, where the flip is the JS `!`
    /// on the raw value and so treats any truthy spelling as already stopped.
    ///
    /// The original hard-codes `'frp'` for this one request even with `kind` in scope. The verb is
    /// hidden for ingress, Cloudflared's only collection, so the two never disagree in practice —
    /// the constant is kept rather than quietly corrected.
    private func toggleChild(_ collection: TunnelCollection, _ parent: JSONValue,
                            _ child: JSONValue) {
        var next = child.record
        next["disabled"] = .bool(!(child["disabled"]?.isTruthy ?? false))
        let key = TunnelRecord.key(parent)
        Task {
            await operate {
                try await TunnelsService.saveChild(.frp, key: key, collection: collection,
                                                  value: .object(next), previous: child)
            }
        }
    }

    /// 删除 — the child travels whole, because the module identifies it by name, or by hostname and
    /// path for an ingress rule.
    private func removeChild(_ collection: TunnelCollection, _ parent: JSONValue,
                             _ child: JSONValue) {
        let key = TunnelRecord.key(parent)
        confirm("删除此规则？") {
            try await TunnelsService.deleteChild(kind, key: key, collection: collection,
                                                value: child)
        }
    }

    /// 检测 DNS / 创建 DNS / 删除 DNS. Only the check writes its answer to the screen; the other two
    /// change the zone, so they ask first and report through the shared 操作已完成 notice.
    private func runDns(_ action: TunnelsService.DnsAction, _ parent: JSONValue,
                        _ hostname: String) {
        let key = TunnelRecord.key(parent)
        guard action != .check else {
            Task {
                await operate {
                    dnsResult = try await TunnelsService.cloudflareDns(key: key,
                                                                      hostname: hostname,
                                                                      action: .check)
                }
            }
            return
        }
        confirm("\(action == .create ? "创建" : "删除") \(hostname) 的 CNAME？") {
            try await TunnelsService.cloudflareDns(key: key, hostname: hostname, action: action)
        }
    }
}

// MARK: - Loading

extension TunnelScreen {
    /// `enabled: active` and `refetchInterval: active && !editor ? 5000 : false`. Both halves live
    /// in the task id, so opening the editor ends the loop and closing it starts a fresh one.
    private var listTaskID: String { "\(phase == .active)|\(editor == nil)" }

    /// The original leaves the list query enabled while the editor is open and merely stops its
    /// interval, so it does not refetch when the editor closes. This does — one reload earlier than
    /// the save's own invalidate, and the only reload at all after an edit that was cancelled.
    private func pollList() async {
        guard phase == .active, editor == nil else { return }
        await loadList()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await loadList()
        }
    }

    private func loadList() async {
        guard !fetching else { return }
        fetching = true
        defer {
            fetching = false
            loaded = true
        }
        do {
            let answer = try await TunnelsService.list(kind)
            all = answer.items
            raw = answer.raw
            listFailure = ""
        } catch {
            guard !error.isCancellation else { return }
            listFailure = error.luckyMessage()
        }
    }

    /// `enabled: active && Boolean(detail) && !editor`, with the page in the key as well. `"off"`
    /// stands for the disabled query, so the loop is torn down rather than left spinning.
    private var detailTaskID: String {
        guard let detail, editor == nil, phase == .active else { return "off" }
        return "\(detail.id)|\(detail.mode.slug)|\(TunnelRecord.key(detail.item))|\(page)"
    }

    /// Only a live log page and the FRP status refresh themselves: a historical page never changes,
    /// and a child list changes only when this screen changes it.
    private func pollDetail() async {
        guard let detail, editor == nil, phase == .active else { return }
        await loadDetail()
        let live = (detail.mode == .logs && page <= 1) || detail.mode == .status
        guard live else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await loadDetail()
        }
    }

    private func loadDetail() async {
        guard let detail, !detailFetching else { return }
        detailFetching = true
        defer {
            detailFetching = false
            detailLoaded = true
        }
        do {
            detailValue = try await fetchDetail(detail)
            detailFailure = ""
        } catch {
            guard !error.isCancellation else { return }
            detailFailure = error.luckyMessage()
        }
    }

    /// The details `queryFn`. `page === 0` is the module's 最新日志 endpoint, which exists only for a
    /// rule that has a key — the module-wide log has to be paged from 1.
    private func fetchDetail(_ detail: TunnelDetail) async throws -> JSONValue {
        let key = TunnelRecord.key(detail.item)
        switch detail.mode {
        case .logs:
            guard page == 0, !key.isEmpty else {
                return try await TunnelsService.logs(kind, key: key, page: page)
            }
            return try await TunnelsService.lastLogs(kind, key: key)
        case .status:
            return try await TunnelsService.frpStatus(key: key)
        case .collection(let collection):
            // Unreachable: STUN exposes no child lists, so no verb opens one. The original throws
            // here all the same, and the message is the one it would show.
            guard kind != .stun else { throw LuckyError("STUN 不支持此操作") }
            let children = try await TunnelsService.children(kind, key: key,
                                                            collection: collection)
            return .object(JSONObject([("items", .array(children))]))
        }
    }
}

// MARK: - Modals

extension TunnelScreen {
    /// `natOpen ? <NatDetector/> : editor ? <EditorModal/> : detail ? <ScreenModal/> : null`.
    ///
    /// The precedence is what makes an editor opened from inside a detail modal *replace* it and
    /// the detail return when that editor closes, so all three share one `.sheet(item:)` over this.
    private enum TunnelModal: Identifiable {
        case nat
        case editor(TunnelEditor)
        case detail(TunnelDetail)

        /// Derived from the stored `UUID`s: a fresh one per computed value would re-present the
        /// sheet on every redraw.
        var id: String {
            switch self {
            case .nat: return "nat"
            case .editor(let editor): return "editor-\(editor.id)"
            case .detail(let detail): return "detail-\(detail.id)"
            }
        }
    }

    private var modal: TunnelModal? {
        if natOpen { return .nat }
        if let editor { return .editor(editor) }
        if let detail { return .detail(detail) }
        return nil
    }

    /// A swipe-down dismisses whichever of the three is showing, in the same precedence order — so
    /// dismissing an editor that was opened over a detail leaves the detail behind, as it does in
    /// the original.
    private var modalBinding: Binding<TunnelModal?> {
        Binding(get: { modal }, set: { next in
            guard next == nil else { return }
            if natOpen {
                natOpen = false
            } else if editor != nil {
                editor = nil
            } else if detail != nil {
                closeDetail()
            }
        })
    }

    @ViewBuilder
    private func sheet(_ modal: TunnelModal) -> some View {
        switch modal {
        case .nat:
            TunnelNatDetector { natOpen = false }
        case .editor(let request):
            TunnelEditorSheet(editor: request, close: { editor = nil },
                              save: { value in try await save(value) })
        case .detail(let request):
            detailSheet(request)
        }
    }

    /// `onClose` clears the banner as well: an operation started from the detail modal reports into
    /// the list's error state, and leaving that behind after the modal is gone reads as a bug.
    private func closeDetail() {
        detail = nil
        failure = ""
    }

    private func detailSheet(_ request: TunnelDetail) -> some View {
        TunnelDetailSheet(
            kind: kind,
            detail: request,
            value: detailValue,
            actionFailure: failure,
            failure: detailFailure,
            loaded: detailLoaded,
            fetching: detailFetching,
            pending: pending,
            page: page,
            dnsResult: dnsResult,
            close: { closeDetail() },
            refresh: { await loadDetail() },
            setPage: { next in page = next },
            add: { collection, parent in addChild(collection, parent) },
            edit: { collection, parent, child in editChild(collection, parent, child) },
            toggle: { collection, parent, child in toggleChild(collection, parent, child) },
            remove: { collection, parent, child in removeChild(collection, parent, child) },
            dns: { action, parent, hostname in runDns(action, parent, hostname) }
        )
    }
}
