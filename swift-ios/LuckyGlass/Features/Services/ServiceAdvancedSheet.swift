import SwiftUI

/// `ServiceAdvancedSheet` — the 高级操作 sheet behind 更多操作 and 排序.
///
/// Everything the two list screens can do to a record but cannot fit in a row: reordering the whole
/// list, a DDNS task's per-record controls, the IP-command and webhook probes, the odhcpd client
/// list, and cancelling an in-flight ACME order. `kind` is normalised to `.ddns` or `.ssl` by the
/// caller, since the other two lists never open it.
struct ServiceAdvancedSheet: View {
    var kind: LuckyServiceKind
    var itemKey: String
    var name: String
    var item: JSONValue
    var orderKeys: [String]
    var close: () -> Void
    /// Awaited so a rejected reorder can put the rows back and report why.
    var reorder: ([String]) async throws -> Void
    var changed: () async -> Void
    var showLogs: () -> Void

    @State private var detail: JSONValue?
    @State private var detailFailure = ""
    @State private var detailLoading = true

    /// `records` is optimistic: a move writes the new order locally, then rolls back if the server
    /// refuses it. `order` behaves the same way for the task list.
    @State private var records: [JSONValue] = []
    @State private var order: [String] = []
    @State private var orderBusy = false

    @State private var option = "enable"
    @State private var ipType = "IPv4"
    @State private var command = ""
    @State private var operationError = ""
    @State private var operationResult = ""

    @State private var clientsOpen = false
    @State private var clients: [JSONValue] = []
    @State private var clientsLoading = false
    @State private var clientsFailure = ""

    /// The original's `actionBusy` string, which both disables the buttons and names the one that
    /// is working — several of them show 测试中 / 取消中... while it holds their label.
    @State private var actionBusy = ""
    @State private var confirmation: ServiceConfirmation?

    /// `detailQuery.data ? editableValue(detailQuery.data) : item` — the sheet works on the freshly
    /// read record when it has one and the list's summary until then.
    private var current: JSONValue {
        guard let detail else { return item }
        return ServiceRecord.editableValue(detail)
    }

    var body: some View {
        ServiceSheet(title: "高级操作", subtitle: name, close: close) {
            LuckyPillButton(title: "完成", symbol: "checkmark", prominent: true) { close() }
        } content: {
            statusCards
            orderCard
            if kind == .ddns {
                ddnsCards
            } else {
                acmeCard
            }
            logsCard
        }
        .alert(confirmation?.title ?? "", isPresented: confirming,
               presenting: confirmation) { request in
            Button("取消", role: .cancel) {}
            Button(request.confirm, role: .destructive) { request.perform() }
        } message: { request in
            Text(request.message)
        }
        .task {
            order = orderKeys
            records = ServiceRecord.recordItems(item)
            await loadDetail()
        }
        .task(id: clientsOpen) {
            guard kind == .ddns, clientsOpen else { return }
            await loadClients()
        }
        .onChange(of: orderKeys) { order = orderKeys }
    }

    private var confirming: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    /// `Boolean(actionBusy)` — every button in the sheet is disabled while any one of them works.
    private var busy: Bool { !actionBusy.isEmpty }
}

// MARK: - Cards

extension ServiceAdvancedSheet {
    /// The four transient cards at the top: the read, its failure, an operation's failure, and an
    /// operation's output. All four can be on screen at once, which is why they are siblings rather
    /// than a switch.
    @ViewBuilder
    var statusCards: some View {
        if detailLoading {
            LuckyCard {
                Text("正在读取详细配置...")
                    .font(LuckyTheme.Text.body)
                    .foregroundStyle(LuckyTheme.textSecondary)
            }
        }
        if !detailFailure.isEmpty {
            LuckyErrorCard(message: detailFailure) { Task { await loadDetail() } }
        }
        if !operationError.isEmpty {
            LuckyErrorCard(message: operationError)
        }
        if !operationResult.isEmpty {
            LuckyCard(spacing: LuckyTheme.Space.s) {
                Text("操作结果")
                    .font(LuckyTheme.Text.captionMedium)
                    .foregroundStyle(LuckyTheme.success)
                LuckyCodeBlock(text: operationResult, maxHeight: 220)
            }
        }
    }

    /// The 任务顺序 card. It lists the *whole* screen's order, not just this record — the sheet is
    /// also the 排序 entry point, and moving a row here reorders the list behind it.
    var orderCard: some View {
        LuckyCard(spacing: LuckyTheme.Space.s) {
            advancedHeader("任务顺序", symbol: "list.number", trailing: "\(order.count) 项")
            if order.isEmpty {
                Text("暂无排序数据")
                    .font(LuckyTheme.Text.body)
                    .foregroundStyle(LuckyTheme.textSecondary)
            } else {
                ForEach(Array(order.enumerated()), id: \.offset) { index, key in
                    orderRow(index, key)
                }
            }
        }
    }

    /// `${index + 1}. ${key === itemKeyValue ? name : key}` — the row for *this* record prints its
    /// name and takes the accent colour, so the user can see what they are moving.
    func orderRow(_ index: Int, _ key: String) -> some View {
        let mine = key == itemKey
        return VStack(alignment: .leading, spacing: 0) {
            if index > 0 { LuckyHairline() }
            HStack(spacing: LuckyTheme.Space.s) {
                Text("\(index + 1). \(mine ? name : key)")
                    .font(LuckyTheme.Text.label)
                    .foregroundStyle(mine ? LuckyTheme.accent : LuckyTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AdvancedIconButton(label: "上移", symbol: "arrow.up",
                                   disabled: index == 0 || orderBusy) {
                    Task { await moveTask(index, -1) }
                }
                AdvancedIconButton(label: "下移", symbol: "arrow.down",
                                   disabled: index == order.count - 1 || orderBusy) {
                    Task { await moveTask(index, 1) }
                }
            }
            .frame(minHeight: 42)
        }
    }

    /// The bold inline header every panel in the original opens with: an 18pt accent glyph, the
    /// title, and either a count or a second glyph on the right.
    func advancedHeader(_ title: String, symbol: String, trailing: String = "",
                        trailingSymbol: String = "") -> some View {
        HStack(spacing: LuckyTheme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LuckyTheme.accent)
            Text(title)
                .font(LuckyTheme.Text.cardTitle)
                .foregroundStyle(LuckyTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textSecondary)
            }
            if !trailingSymbol.isEmpty {
                Image(systemName: trailingSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LuckyTheme.textSecondary)
            }
        }
    }
}

// MARK: - DDNS cards

extension ServiceAdvancedSheet {
    @ViewBuilder
    var ddnsCards: some View {
        recordsCard
        commandCard
        webhookCard
        clientsCard
    }

    /// The DNS 记录 card. Capped at 100 rows because a task with a wildcard can carry thousands and
    /// the original refuses to render them all — it says so in the footnote.
    var recordsCard: some View {
        LuckyCard(spacing: LuckyTheme.Space.s) {
            advancedHeader("DNS 记录", symbol: "list.number", trailing: "\(records.count) 项")
            if records.isEmpty {
                Text("当前任务没有记录")
                    .font(LuckyTheme.Text.body)
                    .foregroundStyle(LuckyTheme.textSecondary)
            } else {
                ForEach(Array(records.prefix(100).enumerated()), id: \.offset) { index, entry in
                    recordRow(entry, index)
                }
            }
            if records.count > 100 {
                Text("仅显示前 100 条记录，请在编辑器中继续管理。")
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textSecondary)
            }
        }
    }

    /// One record: the label, 上移记录 / 下移记录 / 删除记录, and the shared 选项 field.
    ///
    /// The field really is shared — the original binds every row's `TextInput` to the same `option`
    /// state, so typing in one row types in all of them and 应用选项 applies that one value to
    /// whichever row was tapped. Kept as written.
    func recordRow(_ entry: JSONValue, _ index: Int) -> some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            if index > 0 { LuckyHairline() }
            HStack(spacing: LuckyTheme.Space.s) {
                Text(ServiceRecord.recordLabel(entry, index))
                    .font(LuckyTheme.Text.label)
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                AdvancedIconButton(label: "上移记录", symbol: "arrow.up", size: 32, radius: 8,
                                   glyph: 15, disabled: index == 0 || busy) {
                    Task { await moveRecord(index, -1) }
                }
                AdvancedIconButton(label: "下移记录", symbol: "arrow.down", size: 32, radius: 8,
                                   glyph: 15, disabled: index == records.count - 1 || busy) {
                    Task { await moveRecord(index, 1) }
                }
                AdvancedIconButton(label: "删除记录", symbol: LuckySymbol.delete,
                                   color: LuckyTheme.danger, fill: LuckyTheme.dangerSoft,
                                   size: 32, radius: 8, glyph: 15, disabled: busy) {
                    confirmRemoveRecord(entry, index)
                }
            }
            HStack(spacing: LuckyTheme.Space.s) {
                AdvancedField(placeholder: "选项，如 enable", text: $option, height: 40,
                              font: LuckyTheme.Text.caption)
                ServiceActionButton(title: "应用选项", fill: .soft, height: 40, radius: 10,
                                    expands: false, disabled: busy) {
                    changeRecordOption(entry, index)
                }
            }
        }
        .padding(.vertical, 1)
    }

    /// IP 命令测试. The original's IPv4/IPv6 control is a pressable that *cycles* rather than a
    /// picker, and it is sized `flex: 0.35` against the command field — here it takes a fixed 78pt,
    /// which is the same proportion at iPhone widths and stops it stretching on an iPad.
    var commandCard: some View {
        LuckyCard(spacing: LuckyTheme.Space.s) {
            advancedHeader("IP 命令测试", symbol: "terminal", trailingSymbol: "testtube.2")
            HStack(spacing: LuckyTheme.Space.s) {
                Button {
                    ipType = ipType == "IPv4" ? "IPv6" : "IPv4"
                } label: {
                    Text(ipType)
                        .font(LuckyTheme.Text.body)
                        .foregroundStyle(LuckyTheme.textPrimary)
                        .frame(width: 78, height: 44)
                        .background(AdvancedField.box)
                        .overlay(AdvancedField.stroke)
                        .contentShape(AdvancedField.shape)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("IP 类型 \(ipType)")
                AdvancedField(placeholder: "输入获取 IP 的命令", text: $command)
                ServiceActionButton(title: actionBusy == "test-command" ? "测试中" : "测试",
                                    fill: .solid, height: 44, radius: 11, expands: false,
                                    disabled: busy) { testCommand() }
            }
        }
    }

    var webhookCard: some View {
        LuckyCard(spacing: LuckyTheme.Space.s) {
            advancedHeader("Webhook 测试", symbol: "arrow.triangle.branch")
            Text("使用当前任务配置发送一次测试请求，不会改变任务内容。")
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textSecondary)
            ServiceActionButton(title: actionBusy == "test-webhook" ? "发送中..." : "发送测试",
                                symbol: "arrow.triangle.branch", fill: .soft, height: 44,
                                radius: 11, disabled: busy) { testWebhook() }
        }
    }

    /// odhcpd 客户端 — a fold whose open state drives the fetch, which is why it is hand-built
    /// rather than a `LuckyDisclosureCard` (that one owns its own `expanded`).
    var clientsCard: some View {
        LuckyCard(spacing: LuckyTheme.Space.s) {
            Button {
                withAnimation(LuckyTheme.Motion.snap) { clientsOpen.toggle() }
            } label: {
                HStack(spacing: LuckyTheme.Space.s) {
                    Image(systemName: "wifi")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LuckyTheme.accent)
                    Text("odhcpd 客户端")
                        .font(LuckyTheme.Text.cardTitle)
                        .foregroundStyle(LuckyTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: clientsOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LuckyTheme.textSecondary)
                }
                .frame(minHeight: 42)
            }
            .buttonStyle(.plain)
            .accessibilityHint(clientsOpen ? "收起客户端列表" : "展开客户端列表")
            if clientsOpen {
                clientsBody
            }
        }
    }

    @ViewBuilder
    var clientsBody: some View {
        if clientsLoading {
            Text("正在读取客户端...")
                .font(LuckyTheme.Text.body)
                .foregroundStyle(LuckyTheme.textSecondary)
        } else if !clientsFailure.isEmpty {
            LuckyErrorCard(message: clientsFailure) { Task { await loadClients() } }
        } else if clients.isEmpty {
            Text("暂无客户端")
                .font(LuckyTheme.Text.body)
                .foregroundStyle(LuckyTheme.textSecondary)
        } else {
            ForEach(Array(clients.prefix(100).enumerated()), id: \.offset) { index, client in
                clientRow(client, index)
            }
        }
    }

    func clientRow(_ client: JSONValue, _ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if index > 0 { LuckyHairline() }
            HStack(spacing: LuckyTheme.Space.s) {
                Image(systemName: "person.2")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LuckyTheme.textSecondary)
                Text(ServiceRecord.pick(client, ["Hostname", "hostname", "Name", "name",
                                                 "IP", "ip"], "客户端"))
                    .font(LuckyTheme.Text.label)
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(ServiceRecord.pick(client, ["Mac", "MAC", "mac", "IP", "ip"]))
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textSecondary)
            }
            .frame(minHeight: 40)
        }
    }
}

// MARK: - SSL and logs cards

extension ServiceAdvancedSheet {
    /// ACME 操作 — the only thing a certificate's 高级操作 offers beyond ordering, and only while an
    /// order is actually in flight.
    var acmeCard: some View {
        LuckyCard(spacing: LuckyTheme.Space.s) {
            advancedHeader("ACME 操作", symbol: "checkmark.shield")
            if ServiceRecord.isAcmeIssuing(current) {
                ServiceActionButton(
                    title: actionBusy == "cancel-acme" ? "取消中..." : "取消 ACME 签发",
                    symbol: "xmark", tone: .danger, fill: .soft, height: 44, radius: 11,
                    disabled: busy
                ) { confirmCancelAcme() }
            } else {
                Text("当前没有正在签发的 ACME 任务。")
                    .font(LuckyTheme.Text.body)
                    .foregroundStyle(LuckyTheme.textSecondary)
            }
        }
    }

    /// 运行日志 — a door back to the screen's own 日志 mode, focused on this record.
    var logsCard: some View {
        LuckyCard(spacing: LuckyTheme.Space.s) {
            advancedHeader("运行日志", symbol: LuckySymbol.logs)
            ServiceActionButton(title: "查看分页日志", symbol: LuckySymbol.logs, fill: .soft,
                                height: 44, radius: 11) { showLogs() }
        }
    }
}

// MARK: - Operations

extension ServiceAdvancedSheet {
    /// The original's `perform(label, task)`: one busy label, one result, one error, and a
    /// `changed()` callback that reloads the list behind the sheet on success. The return value is
    /// what `moveRecord` uses to decide whether to roll its optimistic swap back.
    @discardableResult
    func perform(_ label: String, _ task: () async throws -> JSONValue) async -> Bool {
        actionBusy = label
        operationError = ""
        operationResult = ""
        defer { actionBusy = "" }
        do {
            let result = try await task()
            let text = ServiceRecord.resultText(result)
            operationResult = text.isEmpty ? "操作成功" : text
            await changed()
            return true
        } catch {
            guard !error.isCancellation else { return false }
            operationError = error.luckyMessage("请求失败")
            return false
        }
    }

    /// Optimistic reorder of one task's DNS records: swap, post, and put the old array back if the
    /// server refuses.
    func moveRecord(_ index: Int, _ direction: Int) async {
        let target = index + direction
        guard target >= 0, target < records.count, actionBusy.isEmpty else { return }
        let previous = records
        var next = records
        next.swapAt(index, target)
        records = next
        let keys = next.enumerated().map { ServiceRecord.recordKey($1, $0) }
        let ordered = JSONValue.array(keys.map { JSONValue.string($0) })
        let succeeded = await perform("reorder-record") {
            try await DdnsService.reorderRecords(taskKey: itemKey, keys: ordered)
        }
        if !succeeded { records = previous }
    }

    /// The same move for the list behind the sheet. It does not go through `perform`, because the
    /// caller owns the request and reports through `orderBusy` and `operationError` instead.
    func moveTask(_ index: Int, _ direction: Int) async {
        let target = index + direction
        guard target >= 0, target < order.count, !orderBusy else { return }
        let previous = order
        var next = order
        next.swapAt(index, target)
        order = next
        orderBusy = true
        operationError = ""
        defer { orderBusy = false }
        do {
            try await reorder(next)
        } catch {
            order = previous
            guard !error.isCancellation else { return }
            operationError = error.luckyMessage("排序失败")
        }
    }

    func changeRecordOption(_ entry: JSONValue, _ index: Int) {
        let key = ServiceRecord.recordKey(entry, index)
        let value = option.jsTrimmed
        guard !value.isEmpty else {
            operationError = "请输入记录选项"
            return
        }
        Task {
            await perform("record-option") {
                try await DdnsService.setRecordOption(taskKey: itemKey, recordKey: key,
                                                      option: value)
            }
        }
    }

    func testCommand() {
        let value = command.jsTrimmed
        guard !value.isEmpty else {
            operationError = "请输入要测试的命令"
            return
        }
        Task {
            await perform("test-command") {
                try await DdnsService.testIpCommand(iptype: ipType, command: value)
            }
        }
    }

    /// The probe posts the record the sheet is holding, so it tests the *saved* webhook rather than
    /// anything typed into the editor.
    func testWebhook() {
        Task {
            await perform("test-webhook") {
                try await DdnsService.testWebhook(itemKey, current)
            }
        }
    }
}

// MARK: - Confirmations

extension ServiceAdvancedSheet {
    /// The record delete drops the row locally on success rather than re-reading the task — the
    /// original returns the literal 记录已删除 as the operation result, so there is nothing to show
    /// from the response either way.
    func confirmRemoveRecord(_ entry: JSONValue, _ index: Int) {
        let key = ServiceRecord.recordKey(entry, index)
        confirmation = ServiceConfirmation(
            title: "删除记录",
            message: "确定删除“\(ServiceRecord.recordLabel(entry, index))”吗？",
            confirm: "删除"
        ) {
            Task {
                await perform("delete-record") {
                    try await DdnsService.deleteRecord(taskKey: itemKey, recordKey: key)
                    var next = records
                    if index < next.count { next.remove(at: index) }
                    records = next
                    return .string("记录已删除")
                }
            }
        }
    }

    func confirmCancelAcme() {
        confirmation = ServiceConfirmation(
            title: "取消 ACME 签发",
            message: "确定取消“\(name)”当前的证书签发吗？",
            confirm: "取消签发"
        ) {
            Task {
                await perform("cancel-acme") { try await SslService.cancelAcme(itemKey) }
            }
        }
    }
}

// MARK: - Loaders

extension ServiceAdvancedSheet {
    /// `detailQuery` plus the `useEffect` that re-derives `records` from it. The 正在读取详细配置...
    /// line only shows while there is nothing to work on, matching `isLoading` rather than
    /// `isFetching`.
    func loadDetail() async {
        detailFailure = ""
        detailLoading = detail == nil
        do {
            let payload: JSONValue
            if kind == .ddns {
                payload = try await DdnsService.task(itemKey)
            } else {
                payload = try await SslService.certificate(itemKey)
            }
            detail = payload
            records = ServiceRecord.recordItems(ServiceRecord.editableValue(payload))
        } catch {
            guard !error.isCancellation else { return }
            detailFailure = error.luckyMessage("读取失败")
        }
        detailLoading = false
    }

    /// `clientsQuery`. It re-runs every time the fold opens, because react-query's default
    /// `staleTime` of zero refetches as soon as the query is re-enabled.
    func loadClients() async {
        clientsFailure = ""
        clientsLoading = clients.isEmpty
        do {
            let payload = try await DdnsService.odhcpdClients()
            clients = ServiceRecord.recordList(payload, ["clients", "list", "data", "result"])
        } catch {
            guard !error.isCancellation else { return }
            clientsFailure = error.luckyMessage("读取失败")
        }
        clientsLoading = false
    }
}

/// The bare `TextInput`s inside 高级操作: no label, a hairline box on the card fill, 40 or 44 tall.
/// `LuckyTextField` always prints a label above the box, which is right for the editors and wrong
/// for these three inline controls.
struct AdvancedField: View {
    var placeholder: String
    @Binding var text: String
    var height: CGFloat = 44
    var font: Font = LuckyTheme.Text.body

    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LuckyTheme.Radius.field, style: .continuous)
    }

    /// Shared with the IPv4/IPv6 pressable next door, which is a button drawn as a field.
    static var box: some View { shape.fill(LuckyTheme.surface) }
    static var stroke: some View {
        shape.strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth)
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(LuckyTheme.textPrimary)
            .tint(LuckyTheme.accent)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, LuckyTheme.Space.m)
            .frame(height: height)
            .background(Self.box)
            .overlay(Self.stroke)
    }
}

/// The square icon buttons the sheet reorders and deletes with — 34pt for tasks, 32pt for a
/// record. A disabled one greys its glyph rather than fading the whole tile, which is what the
/// original does by swapping the icon colour for `colors.disabled`.
struct AdvancedIconButton: View {
    var label: String
    var symbol: String
    var color: Color = LuckyTheme.textPrimary
    var fill: Color = LuckyTheme.surfaceRaised
    var size: CGFloat = 34
    var radius: CGFloat = 9
    var glyph: CGFloat = 16
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(disabled ? LuckyTheme.textTertiary : color)
                .frame(width: size, height: size)
                .background(shape.fill(fill))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
