import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// `app/endpoints/[id].tsx` — the debugger that can call any of the 328 registry endpoints.
///
/// Three things here are easy to get subtly wrong, so they are spelled out:
///
/// * **The method drives everything.** Changing it abandons the in-flight request and drops the
///   previous response, because a body, a file panel and a danger classification all depend on it.
/// * **`pathValues` is ordered by `endpoint.pathVariables`, not by the dictionary.** The danger
///   check joins the dynamic parts into a candidate path, and a Swift dictionary has no order.
/// * **The suffix is trimmed for the request but tested untrimmed for presence**, matching the
///   original's `suffix.trim()` at the call site and `!suffix.trim()` in the validation.
///
/// The two root editors (`StructuredForm`, `StructuredDataView`) live in `StructuredForm.swift`;
/// everything array-shaped is local to this screen because only this screen offers array mode.

/// `type RootMode = 'object' | 'array'`, drawn in the original as a two-up pressable pair with the
/// `Braces` and `List` glyphs.
private enum RootMode: String, Hashable, CaseIterable {
    case object, array

    var title: String {
        switch self {
        case .object: "对象"
        case .array: "数组"
        }
    }

    var symbol: String {
        switch self {
        case .object: "curlybraces"
        case .array: "list.bullet"
        }
    }

    static var segments: [LuckySegment<RootMode>] {
        allCases.map { LuckySegment($0, $0.title, symbol: $0.symbol) }
    }
}

/// The screen's `inputStyle`, which the original re-declares as an object literal in four places:
/// one sunken 44pt field, monospaced when it carries a path, a key or a field name.
private struct EndpointInput: View {
    @Binding var text: String
    var placeholder: String
    var mono: Bool = true
    var keyboard: UIKeyboardType = .default
    /// Fires on both edges. The numeric row commits on the falling one, which is `onBlur`.
    var onFocusChange: ((Bool) -> Void)?

    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LuckyTheme.Radius.row, style: .continuous)
        return TextField(placeholder, text: $text)
            .font(mono ? LuckyTheme.Text.code : LuckyTheme.Text.caption)
            .foregroundStyle(LuckyTheme.textPrimary)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)
            .padding(.horizontal, LuckyTheme.Space.m)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(shape.fill(LuckyTheme.surfaceSunken))
            .overlay(
                shape.strokeBorder(
                    focused ? LuckyTheme.accent.opacity(0.7) : LuckyTheme.hairline,
                    lineWidth: focused ? 1.6 : LuckyTheme.strokeWidth
                )
            )
            .onChange(of: focused) { onFocusChange?(focused) }
    }
}

/// `<NumberArrayInput>` — a numeric row of the body array.
///
/// Deliberately *not* the structured form's numeric field: this one re-syncs from the value whether
/// or not it has focus, and it commits anything `Number` accepts, so `1e3` is a live number here
/// while the structured form would refuse it.
private struct EndpointNumberInput: View {
    var value: Double
    var placeholder: String
    var onChange: (Double) -> Void

    @State private var draft = ""

    /// The partial tokens the original refuses to commit. Without the guard, clearing the field
    /// would commit `Number('') === 0` and the user would lose the value mid-edit.
    private static let partial: Set<String> = ["-", "+", ".", "-.", "+."]

    var body: some View {
        EndpointInput(
            text: $draft,
            placeholder: placeholder,
            mono: false,
            keyboard: .numbersAndPunctuation
        ) { isFocused in
            if !isFocused { commit() }
        }
        .onSubmit { commit() }
        .onChange(of: draft) { live() }
        .onChange(of: value, initial: true) { sync() }
    }

    /// `useEffect(…, [value])`. A blank draft, or one that no longer parses to the value, is
    /// overwritten — there is no focus guard because the original does not have one either.
    private func sync() {
        guard draft.jsTrimmed.isEmpty || JSCompat.number(draft) != value else { return }
        draft = JSONSerializer.numberString(value)
    }

    private func live() {
        let trimmed = draft.jsTrimmed
        guard !trimmed.isEmpty, !Self.partial.contains(trimmed) else { return }
        let next = JSCompat.number(trimmed)
        if next.isFinite { onChange(next) }
    }

    /// `onBlur` and `onSubmitEditing`: a finite draft is normalised, anything else reverts.
    private func commit() {
        let trimmed = draft.jsTrimmed
        let next = JSCompat.number(trimmed)
        guard !trimmed.isEmpty, next.isFinite else {
            draft = JSONSerializer.numberString(value)
            return
        }
        onChange(next)
        draft = JSONSerializer.numberString(next)
    }
}

/// `DocumentPickerAsset`, reduced to what a multipart part needs.
///
/// Divergence: `copyToCacheDirectory: true` lets the original re-read the file at upload time,
/// while this holds the bytes from the moment they are picked. The endpoints that accept an upload
/// take a config archive or an image, so the trade is memory for a much simpler lifetime.
private struct EndpointPickedFile: Equatable {
    var name: String
    var mimeType: String
    var data: Data

    /// `${name}${size ? ` · ${size} bytes` : ''}`
    var caption: String {
        data.isEmpty ? name : "\(name) · \(data.count) bytes"
    }
}

/// `<QueryArrayForm>` — query parameters as an ordered list of `{key, value}` records, which is how
/// the original expresses a repeated name (`?port=1&port=2`) that an object cannot hold.
private struct QueryArrayForm: View {
    @Binding var value: [JSONObject]

    var body: some View {
        VStack(spacing: 9) {
            ForEach(value.indices, id: \.self) { index in
                row(index)
            }
            Button {
                value.append(JSONObject([("key", .string("")), ("value", .string(""))]))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: LuckySymbol.add).font(.system(size: 15, weight: .semibold))
                    Text("添加查询参数").font(LuckyTheme.Text.captionMedium)
                }
                .foregroundStyle(LuckyTheme.accent)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: LuckyTheme.Radius.field, style: .continuous)
                        .strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth)
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// `参数名` at flex 0.9 against `参数值` at flex 1.1 in the original; an even split is used here
    /// because at iPhone width that ratio is a four-point difference nobody can see.
    private func row(_ index: Int) -> some View {
        HStack(spacing: 7) {
            EndpointInput(text: field(index, "key"), placeholder: "参数名")
                .frame(maxWidth: .infinity)
            EndpointInput(text: field(index, "value"), placeholder: "参数值")
                .frame(maxWidth: .infinity)
            Button {
                guard value.indices.contains(index) else { return }
                value.remove(at: index)
            } label: {
                Image(systemName: LuckySymbol.delete)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LuckyTheme.danger)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LuckyTheme.dangerSoft)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除查询参数")
        }
    }

    /// Reads `entry.key ?? entry.Key` but always writes the lowercase form, exactly as the original
    /// does: a capitalised pair pasted in from a config is shown, then normalised on first edit.
    private func field(_ index: Int, _ key: String) -> Binding<String> {
        let fallback = key == "key" ? "Key" : "Value"
        return Binding(
            get: {
                guard value.indices.contains(index) else { return "" }
                let entry = value[index]
                return (entry[key] ?? entry[fallback])?.asDisplayString ?? ""
            },
            set: { text in
                guard value.indices.contains(index) else { return }
                value[index][key] = .string(text)
            }
        )
    }
}

/// `<RootArrayForm>` — the request body as a bare array. Only this screen offers it, because only
/// this screen has to reach the handful of Lucky endpoints whose body is a list rather than an
/// object (bulk rule ordering, batch deletes).
private struct RootArrayForm: View {
    @Binding var value: [JSONValue]

    /// The five append chips, in the original's order. Note 数组 here against 列表 in the structured
    /// form: the same `[]` under two labels, and the labels are kept verbatim.
    private static let kinds: [(String, JSONValue)] = [
        ("文本", .string("")),
        ("数字", .number(0)),
        ("开关", .bool(false)),
        ("对象", .object(JSONObject())),
        ("数组", .array([])),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(value.indices, id: \.self) { index in
                row(index)
            }
            append
        }
    }

    private func row(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: LuckyTheme.Space.s) {
            field(index)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                guard value.indices.contains(index) else { return }
                value.remove(at: index)
            } label: {
                Image(systemName: LuckySymbol.delete)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LuckyTheme.danger)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LuckyTheme.dangerSoft)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除数组项")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: LuckyTheme.Radius.row, style: .continuous)
                .strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth)
        )
    }

    /// `AnyView` because the nested-array branch mentions `RootArrayForm` again, and a `body` may
    /// not name its own type. The branch order is the original's chain of `Array.isArray` →
    /// `isRecord` → `typeof === 'boolean'` → `'number'` → everything else.
    private func field(_ index: Int) -> AnyView {
        let current = item(index)
        if current.isArray {
            return AnyView(VStack(alignment: .leading, spacing: 7) {
                Text("嵌套数组")
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textTertiary)
                RootArrayForm(value: arrayBinding(index))
            })
        }
        if current.isRecord {
            return AnyView(StructuredForm(value: recordBinding(index)))
        }
        if let flag = current.boolValue {
            return AnyView(HStack(spacing: LuckyTheme.Space.s) {
                Text("第 \(index + 1) 项")
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: Binding(get: { flag }, set: { set(index, .bool($0)) }))
                    .labelsHidden()
                    .tint(LuckyTheme.accent)
            }
            .frame(minHeight: 42))
        }
        if case .number(let number) = current {
            return AnyView(EndpointNumberInput(value: number, placeholder: "第 \(index + 1) 项") {
                set(index, .number($0))
            })
        }
        return AnyView(EndpointInput(text: stringBinding(index),
                                     placeholder: "第 \(index + 1) 项", mono: false))
    }

    private var append: some View {
        LuckyTileGrid(minimum: 92) {
            ForEach(Self.kinds, id: \.0) { label, initial in
                Button {
                    value.append(initial)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: LuckySymbol.add)
                            .font(.system(size: 14, weight: .semibold))
                        Text("\(label)项").font(LuckyTheme.Text.captionMedium).lineLimit(1)
                    }
                    .foregroundStyle(LuckyTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(
                        RoundedRectangle(cornerRadius: LuckyTheme.Radius.field, style: .continuous)
                            .strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func item(_ index: Int) -> JSONValue {
        value.indices.contains(index) ? value[index] : .null
    }

    /// Every write is bounds-checked: SwiftUI can evaluate a deleted row's binding once more, and
    /// an unchecked subscript would trap there.
    private func set(_ index: Int, _ next: JSONValue) {
        guard value.indices.contains(index) else { return }
        value[index] = next
    }

    private func stringBinding(_ index: Int) -> Binding<String> {
        Binding(get: { item(index).asDisplayString }, set: { set(index, .string($0)) })
    }

    private func recordBinding(_ index: Int) -> Binding<JSONObject> {
        Binding(get: { item(index).record }, set: { set(index, .object($0)) })
    }

    private func arrayBinding(_ index: Int) -> Binding<[JSONValue]> {
        Binding(get: { item(index).list }, set: { set(index, .array($0)) })
    }
}

/// `EndpointRunnerScreen` — `/endpoints/[id]`, reached from a module's接口列表.
struct EndpointScreen: View {
    var endpointID: String

    /// Resolved once in `init`. The registry is a static JSON bundle, so an endpoint that is not
    /// there at launch will never appear later.
    private let endpoint: LuckyEndpointDefinition?

    @State private var method: LuckyHttpMethod
    @State private var pathValues: [String: String]
    @State private var suffix = ""
    @State private var queryMode: RootMode = .object
    @State private var queryObject = JSONObject()
    @State private var queryArray: [JSONObject] = []
    @State private var bodyMode: RootMode = .object
    @State private var bodyObject = JSONObject()
    @State private var bodyArray: [JSONValue] = []
    @State private var sendBody = true
    @State private var selectedFile: EndpointPickedFile?
    @State private var fileField = "file"
    @State private var picking = false
    @State private var saving = false
    @State private var savedPath = ""
    @State private var inputError = ""
    @State private var requestError = ""
    @State private var confirming = false
    @State private var result: LuckyEndpointResult?
    @State private var task: Task<Void, Never>?
    @State private var toast: LuckyToast?

    /// The original's `useEffect([endpoint])` seeding block, hoisted into `init` so the first frame
    /// is already correct: the default method is the endpoint's first, and every path variable
    /// starts as an empty string so the missing-parameter check has something to test.
    init(endpointID: String) {
        self.endpointID = endpointID
        let found = LuckyEndpointRegistry.endpoint(id: endpointID)
        endpoint = found
        _method = State(initialValue: found?.methods.first ?? .get)
        var seeded: [String: String] = [:]
        for name in found?.pathVariables ?? [] { seeded[name] = "" }
        _pathValues = State(initialValue: seeded)
    }

    /// No `.luckyTitle` here: 接口调试 comes from `LuckyRoute.title` on the pushing stack.
    var body: some View {
        if let endpoint {
            form(endpoint)
        } else {
            LuckyPage {
                LuckyPageHero(title: "接口不存在")
                LuckyEmptyState(symbol: LuckySymbol.debugger, title: "无法在接口清单中找到该端点")
            }
        }
    }

    /// `<Page … scrollable={false}>` around a `ScrollView` with `gap: 14` — which is exactly what
    /// `LuckyPage` is, so the extra scroll container is dropped.
    private func form(_ endpoint: LuckyEndpointDefinition) -> some View {
        LuckyPage {
            identity(endpoint)
            configuration(endpoint)
            queryPanel
            if method != .get { bodyPanel }
            if fileCapable { filePanel }
            errors
            if let result { response(result) }
        }
        .luckyActionBar { submit(endpoint) }
        .luckyToast($toast)
        .alert("确认执行高风险接口", isPresented: $confirming) {
            Button("取消", role: .cancel) {}
            Button("确认执行", role: .destructive) { execute(endpoint) }
        } message: {
            Text(verbatim: "\(method.rawValue) \(endpoint.path)\n\n"
                 + "该请求可能修改或删除系统、网络、证书或容器数据。")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { pick($0) }
        // The original does this inside the method pressable; here it covers every path that can
        // change the method, and it is why a GET's response never lingers under a DELETE verb.
        .onChange(of: method) { reset() }
        .onDisappear { task?.cancel() }
    }

    /// The `Route` panel. The page subtitle `${module} · ${id}` moves in here because the nav bar
    /// already carries 接口调试 and an inline subtitle would be truncated.
    private func identity(_ endpoint: LuckyEndpointDefinition) -> some View {
        LuckyCard(spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LuckyTheme.accent)
                Text(endpoint.path)
                    .font(LuckyTheme.Text.code)
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: "\(endpoint.module) · \(endpoint.id)")
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textTertiary)
            Text(verbatim: "来源：\(endpoint.source.isEmpty ? "开发文档" : endpoint.source)")
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textTertiary)
        }
    }

    /// 请求配置: everything that shapes the URL. Grouped into one child so the page's `ViewBuilder`
    /// stays well under ten, with the same 14pt rhythm inside as outside.
    private func configuration(_ endpoint: LuckyEndpointDefinition) -> some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.stack) {
            LuckySectionHeader(title: "请求配置", symbol: "slider.horizontal.3")
            // A wrapped row of pressables in the original. An endpoint declares at most five
            // methods, which is what a segmented control is for; `glass: false` because it scrolls.
            LuckyGlassSegmentedControl(
                selection: $method,
                segments: endpoint.methods.map { LuckySegment($0, $0.rawValue) },
                glass: false
            )
            if dangerous { dangerBanner }
            ForEach(endpoint.pathVariables, id: \.self) { name in
                LuckyTextField(label: "路径参数 \(name)", text: pathBinding(name),
                               placeholder: "输入 ID、Key 或资源名称", mono: true)
            }
            // Only when there is no named variable: an endpoint with both would be ambiguous about
            // which part of the path the suffix fills.
            if endpoint.pathVariables.isEmpty, endpoint.requiresSuffix {
                LuckyTextField(label: "资源 Key / 路径后缀", text: $suffix,
                               placeholder: "输入资源名称或路径后缀", mono: true)
            }
        }
    }

    private var dangerBanner: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: LuckySymbol.danger)
                .font(.system(size: 16, weight: .semibold))
            Text("高风险请求，执行前会再次确认。")
                .font(LuckyTheme.Text.caption)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(LuckyTheme.danger)
        .padding(LuckyTheme.Space.m)
        .background(
            RoundedRectangle(cornerRadius: LuckyTheme.Radius.row, style: .continuous)
                .fill(LuckyTheme.dangerSoft)
        )
    }

    @ViewBuilder
    private var errors: some View {
        if !inputError.isEmpty || !requestError.isEmpty {
            VStack(spacing: LuckyTheme.Space.stack) {
                // `ErrorState` carries no title of its own, and a missing path parameter is not a
                // 请求失败 — so the validation card says what it actually is.
                if !inputError.isEmpty {
                    LuckyErrorCard(message: inputError, title: "无法执行")
                }
                if !requestError.isEmpty {
                    LuckyErrorCard(message: requestError)
                }
            }
        }
    }

    private var queryPanel: some View {
        LuckyCard(spacing: 10) {
            Text("查询参数")
                .font(LuckyTheme.Text.label)
                .foregroundStyle(LuckyTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            LuckyGlassSegmentedControl(selection: $queryMode, segments: RootMode.segments,
                                       glass: false)
            if queryMode == .array {
                QueryArrayForm(value: $queryArray)
            } else {
                StructuredForm(value: $queryObject)
            }
        }
    }

    /// Only for a verb that can carry one. Turning 发送请求体 off keeps the editor's contents — the
    /// original does the same, so a mis-click does not discard a body someone just typed.
    private var bodyPanel: some View {
        LuckyCard(spacing: 10) {
            LuckyToggleRow(label: "发送请求体", isOn: $sendBody)
            if sendBody {
                LuckyGlassSegmentedControl(selection: $bodyMode, segments: RootMode.segments,
                                           glass: false)
                if bodyMode == .array {
                    RootArrayForm(value: $bodyArray)
                } else {
                    StructuredForm(value: $bodyObject)
                }
            }
        }
    }

    private var filePanel: some View {
        LuckyCard(spacing: 10) {
            HStack(spacing: LuckyTheme.Space.s) {
                Image(systemName: LuckySymbol.upload)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LuckyTheme.accent)
                Text("上传文件")
                    .font(LuckyTheme.Text.label)
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if selectedFile != nil {
                    Button { selectedFile = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(LuckyTheme.danger)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(LuckyTheme.dangerSoft)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("移除文件")
                }
            }
            EndpointInput(text: $fileField, placeholder: "Multipart 字段名")
            fileRow
        }
    }

    /// The picker row. Its border turns success-tinted once a file is held, so the state reads at a
    /// glance even when the name is elided.
    private var fileRow: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return Button {
            inputError = ""
            picking = true
        } label: {
            HStack(spacing: LuckyTheme.Space.s) {
                Image(systemName: LuckySymbol.upload)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selectedFile == nil ? LuckyTheme.accent : LuckyTheme.success)
                Text(selectedFile?.caption ?? "选择文件")
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(selectedFile == nil
                                     ? LuckyTheme.textTertiary : LuckyTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 44)
            .background(shape.fill(LuckyTheme.surfaceSunken))
            .overlay(
                shape.strokeBorder(selectedFile == nil ? LuckyTheme.hairline : LuckyTheme.success,
                                   lineWidth: LuckyTheme.strokeWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var pending: Bool { task != nil }

    private func pathBinding(_ name: String) -> Binding<String> {
        Binding(get: { pathValues[name] ?? "" }, set: { pathValues[name] = $0 })
    }

    /// `[suffix, ...Object.values(pathValues)].filter(Boolean).join('/')`, iterating
    /// `pathVariables` instead of the dictionary — a Swift dictionary has no order, and the danger
    /// classifier matches on this joined path.
    private var dynamicPath: String {
        guard let endpoint else { return suffix }
        let parts = [suffix] + endpoint.pathVariables.map { pathValues[$0] ?? "" }
        return parts.filter { !$0.isEmpty }.joined(separator: "/")
    }

    private var dangerous: Bool {
        guard let endpoint else { return false }
        return EndpointRunner.isDangerous(endpoint, method: method, dynamicPath: dynamicPath)
    }

    /// `/\/(?:upload|import|load|restore|build-from-zip)(?:[/?]|$)/i`: a whole trailing segment, so
    /// `/api/loadbalance/list` is not mistaken for an upload endpoint.
    private var fileCapable: Bool {
        guard let endpoint, method != .get else { return false }
        let path = (endpoint.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "")
            .lowercased()
        return Self.uploadSegments.contains { path.contains("/\($0)/") || path.hasSuffix("/\($0)") }
    }

    private static let uploadSegments: Set<String> = [
        "upload", "import", "load", "restore", "build-from-zip",
    ]

    /// The `mutationFn`'s request assembly. The suffix appears twice on purpose: trimmed into
    /// `pathValues.e` when the endpoint declares no named variable, and trimmed again as the call's
    /// own suffix — the runner needs both because only it knows which one the path template uses.
    private func call(_ endpoint: LuckyEndpointDefinition) -> LuckyEndpointCall {
        let trimmed = suffix.jsTrimmed
        var values = pathValues
        if endpoint.pathVariables.isEmpty, !trimmed.isEmpty { values["e"] = trimmed }
        let query: JSONValue = queryMode == .array
            ? .array(queryArray.map { .object($0) })
            : .object(queryObject)
        let payload: JSONValue = bodyMode == .array ? .array(bodyArray) : .object(bodyObject)
        var request = LuckyEndpointCall(endpoint: endpoint, method: method, pathValues: values,
                                        suffix: trimmed, query: query)
        guard method != .get else { return request }
        if fileCapable, let file = selectedFile {
            let field = fileField.jsTrimmed.isEmpty ? "file" : fileField.jsTrimmed
            request.form = Self.multipart(file, field: field,
                                          value: sendBody ? payload : .object(JSONObject()))
        } else if sendBody {
            request.body = payload
        }
        return request
    }

    /// `multipartBody`. Two rules are load-bearing: an array body travels whole under `payload`,
    /// and a record entry whose key collides with the file's field is skipped so the text part
    /// cannot overwrite the upload.
    private static func multipart(_ file: EndpointPickedFile, field: String,
                                  value: JSONValue) -> MultipartBody {
        var form = MultipartBody()
        form.append(field, filename: file.name, mimeType: file.mimeType, content: file.data)
        if let items = value.arrayValue {
            form.append("payload", value: JSONSerializer.stringify(.array(items)))
            return form
        }
        // `appendMultipartValue`: an empty key, a null and an empty string are dropped, a composite
        // is JSON, everything else is `String(value)` — so `false` and `0` are still sent.
        for (key, item) in value.record where key != field && !key.isEmpty && !item.isNull {
            if item.isRecord || item.isArray {
                form.append(key, value: JSONSerializer.stringify(item))
            } else {
                let text = item.asDisplayString
                if !text.isEmpty { form.append(key, value: text) }
            }
        }
        return form
    }

    /// `run()`. Validation first, then the confirmation for a dangerous verb.
    private func run(_ endpoint: LuckyEndpointDefinition) {
        inputError = ""
        let missing = endpoint.pathVariables.filter { (pathValues[$0] ?? "").jsTrimmed.isEmpty }
        let needsSuffix = endpoint.pathVariables.isEmpty && endpoint.requiresSuffix
            && suffix.jsTrimmed.isEmpty
        if !missing.isEmpty || needsSuffix {
            let names = missing.isEmpty ? "资源 Key / 路径后缀" : missing.joined(separator: ", ")
            inputError = "请填写路径参数 \(names)"
            return
        }
        if dangerous { confirming = true } else { execute(endpoint) }
    }

    private func execute(_ endpoint: LuckyEndpointDefinition) {
        let request = call(endpoint)
        task?.cancel()
        result = nil
        requestError = ""
        savedPath = ""
        task = Task {
            do {
                let outcome = try await EndpointRunner.run(request)
                guard !Task.isCancelled else { return }
                result = outcome
            } catch {
                // The runner rewraps its own cancellation as 请求已取消, so both tests are needed:
                // a cancelled request has already been reported by the button changing back.
                guard !Task.isCancelled, !error.isCancellation else { return }
                requestError = error.luckyMessage()
            }
            task = nil
        }
    }

    /// `cancelRequest`, which also clears the last response — the original's `mutation.reset()`.
    private func cancel() {
        reset()
        inputError = ""
    }

    private func reset() {
        task?.cancel()
        task = nil
        result = nil
        requestError = ""
        savedPath = ""
    }

    /// `loading: false` even while a request is in flight: the pill is the cancel button then, and
    /// a disabled spinner would strand the user until the server answered.
    private func submit(_ endpoint: LuckyEndpointDefinition) -> some View {
        LuckyPillButton(title: pending ? "取消请求" : "执行 \(method.rawValue)",
                        symbol: pending ? "xmark" : LuckySymbol.send,
                        tone: pending || dangerous ? .danger : .brand,
                        prominent: true,
                        loading: false) {
            if pending { cancel() } else { run(endpoint) }
        }
    }

    /// `SectionHeader icon={CheckCircle2} title="响应" meta={`HTTP ${status}`}` — the glyph is the
    /// checkmark whatever the status is, and the status itself carries the tone.
    private func response(_ result: LuckyEndpointResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LuckySectionHeader(title: "响应", symbol: LuckyTone.ok.symbol) {
                LuckyChip(text: "HTTP \(result.status)", tone: LuckyTone.httpStatus(result.status))
            }
            LuckyCard(spacing: 10) {
                switch result.kind {
                case .json:
                    StructuredDataView(value: result.data ?? .null)
                case .binary:
                    StructuredDataView(value: .object(Self.binarySummary(result)))
                    // The library's one sanctioned glass-in-scroll case, as in `LuckyErrorCard`:
                    // the action belongs to the card it sits in, not to the page.
                    LuckyPillButton(title: saving ? "保存中..." : "保存文件",
                                    symbol: LuckySymbol.download,
                                    loading: saving) {
                        save(result)
                    }
                    // `Alert.alert('保存成功', location)` cannot survive as a toast — a file path is
                    // too long to read in one — so the location stays on screen and is selectable.
                    if !savedPath.isEmpty {
                        Text(verbatim: savedPath)
                            .font(LuckyTheme.Text.codeSmall)
                            .foregroundStyle(LuckyTheme.textTertiary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .empty:
                    Text("响应体为空")
                        .font(LuckyTheme.Text.body)
                        .foregroundStyle(LuckyTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .text:
                    Text(verbatim: result.data?.asDisplayString ?? "")
                        .font(LuckyTheme.Text.caption)
                        .foregroundStyle(LuckyTheme.textPrimary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// `formatBinary` — an ordered summary, because a binary response has nothing to show but its
    /// envelope. `StructuredDataView` renders it exactly like any other record.
    private static func binarySummary(_ result: LuckyEndpointResult) -> JSONObject {
        let type = result.contentType.isEmpty ? "application/octet-stream" : result.contentType
        let name = (result.filename ?? "").isEmpty ? "未命名文件" : (result.filename ?? "")
        return JSONObject([
            ("状态", .number(Double(result.status))),
            ("类型", .string(type)),
            ("文件名", .string(name)),
            ("大小", .string("\(result.byteLength ?? 0) bytes")),
        ])
    }

    /// `saveBinary`. The write happens off the main actor because a config archive or a container
    /// image export can be tens of megabytes and `Data.write` is synchronous.
    private func save(_ result: LuckyEndpointResult) {
        guard result.kind == .binary, !saving else { return }
        saving = true
        Task {
            do {
                let location = try await Task.detached { try EndpointFile.save(result) }.value
                savedPath = location
                toast = .ok("保存成功")
            } catch {
                toast = .failed("保存失败 · \(error.luckyMessage("无法保存文件"))")
            }
            saving = false
        }
    }

    /// `chooseFile`. The bytes are read now rather than at upload time, so the security-scoped URL
    /// does not have to outlive the picker.
    private func pick(_ selection: Result<URL, any Error>) {
        switch selection {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                selectedFile = EndpointPickedFile(name: url.lastPathComponent,
                                                 mimeType: mime ?? "application/octet-stream",
                                                 data: data)
            } catch {
                inputError = error.luckyMessage("无法读取所选文件")
            }
        case .failure(let error):
            // Dismissing the sheet arrives here as `NSUserCancelledError`, which is not a failure
            // worth a banner — the original's `selection.canceled` branch does nothing either.
            let cancelled = error.isCancellation || (error as NSError).code == NSUserCancelledError
            guard !cancelled else { return }
            inputError = error.luckyMessage("无法读取所选文件")
        }
    }
}

/// `saveBinaryResult`, without the web download branch and without Android's directory picker: on
/// iOS the original writes into `Paths.document`, which is the app's Documents directory — the one
/// `UIFileSharingEnabled` exposes in the Files app, so a saved archive is reachable afterwards.
private enum EndpointFile {
    static func save(_ result: LuckyEndpointResult) throws -> String {
        guard let blob = result.blob else { throw LuckyError("响应中没有可保存的文件") }
        let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let target = available(directory, safeFilename(result.filename))
        do {
            try blob.write(to: target, options: .withoutOverwriting)
        } catch {
            // The original deletes the file it created before rethrowing; a truncated archive that
            // looks like a successful download is worse than no file at all.
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return target.path(percentEncoded: false)
    }

    /// `safeFilename`: an empty or blank name becomes `lucky-download.bin`, then the nine reserved
    /// characters `< > : " / \ | ? *` and every C0 control (U+0000 through U+001F) become `_`. The
    /// set is Windows-hostile rather than POSIX-hostile, and it is kept as-is: these names arrive
    /// in a `Content-Disposition` header written by a server that may itself run on Windows.
    static func safeFilename(_ value: String?) -> String {
        let trimmed = (value ?? "").jsTrimmed
        let name = trimmed.isEmpty ? "lucky-download.bin" : trimmed
        let forbidden: Set<Character> = ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]
        return String(name.map { character -> Character in
            if forbidden.contains(character) { return "_" }
            if character.unicodeScalars.count == 1,
               let scalar = character.unicodeScalars.first, scalar.value <= 0x1f {
                return "_"
            }
            return character
        })
    }

    /// `availableFile`: the plain name, then ` (1)` … ` (999)`, then a millisecond stamp. The split
    /// is at the *last* dot and a leading dot does not count, so `.env` keeps its whole name and
    /// `backup.tar.gz` becomes `backup.tar (1).gz` — which is what the original produces too.
    static func available(_ directory: URL, _ filename: String) -> URL {
        let manager = FileManager.default
        var candidate = directory.appending(path: filename)
        if !manager.fileExists(atPath: candidate.path(percentEncoded: false)) { return candidate }
        var base = filename
        var suffix = ""
        if let dot = filename.lastIndex(of: "."), dot != filename.startIndex {
            base = String(filename[filename.startIndex..<dot])
            suffix = String(filename[dot...])
        }
        for index in 1...999 {
            candidate = directory.appending(path: "\(base) (\(index))\(suffix)")
            if !manager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return directory.appending(path: "\(base)-\(stamp)\(suffix)")
    }
}
