import SwiftUI

/// `src/components/structured-form.tsx` — a recursive editor for an arbitrary JSON body and a
/// recursive viewer for an arbitrary JSON response.
///
/// Three things make this file worth reading before changing it:
///
/// * **Order matters.** The user types fields in a sequence and the request must go out in that
///   sequence, so every object here is a `JSONObject` (insertion-ordered) and never a `Dictionary`.
/// * **Recursion is erased.** A SwiftUI `body` cannot mention its own type — the opaque return type
///   would reference itself — so each recursive step is wrapped in `AnyView`. That costs the
///   compiler's diffing shortcuts and buys a form that nests arbitrarily deep, which is the whole
///   point of the screen.
/// * **No glass, no shadow, no per-field animation.** One request body can generate fifty of these
///   rows; the cheapest possible field is what keeps the debugger scrolling.
enum LuckyFieldName {
    /// `fieldLabel(key)`: a curated Chinese label when Lucky's key is known, otherwise the key made
    /// readable. The original tests `labels[key]` for truthiness, so an empty entry would fall
    /// through — hence the `isEmpty` check rather than a plain lookup.
    static func label(_ key: String) -> String {
        if let known = table[key], !known.isEmpty { return known }
        return humanised(key)
    }

    /// `key.replace(/_/g, " ").replace(/([a-z])([A-Z])/g, "$1 $2")` in one pass. The second regex
    /// runs on the output of the first, which is why an underscore leaves a space behind as the
    /// previous character and therefore never triggers a camel-case split.
    private static func humanised(_ key: String) -> String {
        var out = ""
        var previous: Character?
        for character in key {
            if character == "_" {
                out.append(" ")
                previous = " "
                continue
            }
            if let previous, previous.isASCIILower, character.isASCIIUpper {
                out.append(" ")
            }
            out.append(character)
            previous = character
        }
        return out
    }

    /// `labels`, verbatim. Lucky mixes snake_case request fields with the PascalCase keys its Go
    /// structs marshal, so both spellings of the same concept appear — `driver`/`Driver`,
    /// `images`/`Images`, `labels`/`Labels` — and they do not always mean the same thing:
    /// `containers` is 容器 while `Containers` is 关联容器.
    static let table: [String: String] = [
        "name": "名称",
        "Name": "名称",
        "image": "镜像",
        "tag": "标签",
        "repository": "仓库",
        "architecture": "架构",
        "config": "配置",
        "operation": "操作",
        "path": "路径",
        "content": "内容",
        "project_name": "项目名称",
        "project_path": "项目路径",
        "scan_path": "扫描路径",
        "working_dir": "工作目录",
        "filename": "文件名",
        "file_path": "文件路径",
        "target_path": "目标路径",
        "config_file_name": "配置文件名",
        "auto_start": "恢复后自动启动",
        "volume_name": "数据卷名称",
        "driver": "驱动",
        "Driver": "驱动",
        "Options": "选项",
        "IPAM": "IP 地址管理",
        "DriverOpts": "驱动选项",
        "Labels": "标签",
        "backup": "备份文件",
        "mirror": "镜像加速地址",
        "containers": "容器",
        "images": "镜像",
        "networks": "网络",
        "volumes": "数据卷",
        "build_cache": "构建缓存",
        "disk_usage": "磁盘使用情况",
        "LayersSize": "镜像层大小",
        "Images": "镜像",
        "Containers": "关联容器",
        "Created": "创建时间",
        "Size": "占用空间",
        "SharedSize": "共享空间",
        "VirtualSize": "虚拟大小",
        "ContainersRunning": "运行中容器",
        "ContainersStopped": "已停止容器",
        "DockerRootDir": "Docker 数据目录",
        "labels": "容器标签",
        "containerGroups": "容器分组",
        "collapsedStates": "分组折叠状态",
        "orderMapping": "容器排序映射",
        "composeBackup": "Compose 备份",
        "volumeBackup": "数据卷备份",
        "imageUpgrades": "镜像升级状态",
        "imageRef": "镜像标签",
        "checked": "检测结果",
        "checkedCount": "检测成功",
        "completedCount": "已完成",
        "totalCount": "总数",
        "inProgress": "检测中",
        "statusError": "状态读取错误",
        "removed": "已删除镜像",
        "removedCount": "删除成功",
        "unused": "未使用镜像",
        "unusedCount": "未使用数量",
        "used": "使用中镜像",
        "usedCount": "使用中数量",
        "failed": "失败项目",
        "failedCount": "失败数量",
        "error": "请求错误",
        "TaskName": "任务名称",
        "DDNSTaskName": "任务名称",
        "Enable": "启用",
        "Records": "域名记录",
        "DNSProvider": "DNS 服务商",
        "Domain": "域名",
        "Domains": "域名",
        "Remark": "备注名称",
        "AddFrom": "证书来源",
        "CertFile": "证书文件",
        "KeyFile": "私钥文件",
        "ExtParams": "扩展参数",
        "CertsInfo": "证书信息",
        "NotBeforeTime": "生效时间",
        "NotAfterTime": "到期时间",
        "SyncInfo": "同步信息",
        "SyncClients": "同步客户端",
        "ACMEing": "正在签发",
    ]
}

private extension Character {
    /// `[a-z]` and `[A-Z]` are ASCII-only in JavaScript's regex without the `u` flag.
    var isASCIILower: Bool { isASCII && isLowercase }
    var isASCIIUpper: Bool { isASCII && isUppercase }
}

/// `FieldHeader`: the field's Chinese name, and a trash button when the field can be removed.
private struct StructuredFieldHeader: View {
    var name: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: LuckyTheme.Space.s) {
            Text(LuckyFieldName.label(name))
                .font(LuckyTheme.Text.captionMedium)
                .foregroundStyle(LuckyTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let onRemove {
                StructuredTrashButton(field: name, size: 28, radius: 8, action: onRemove)
            }
        }
        .frame(minHeight: 24)
    }
}

/// Every delete in the form. The label is `删除${fieldLabel(name)}` for a field and 删除列表项 for an
/// array item, which is what a screen reader announces — the glyph alone is ambiguous when fifty of
/// them are on screen.
private struct StructuredTrashButton: View {
    var field: String?
    var size: CGFloat
    var radius: CGFloat
    var fill: Color = .clear
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: LuckySymbol.delete)
                .font(.system(size: size > 32 ? 15 : 14, weight: .semibold))
                .foregroundStyle(LuckyTheme.danger)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(field.map { "删除\(LuckyFieldName.label($0))" } ?? "删除列表项")
    }
}

/// The text box shared by every leaf field. Compact by design: the original's inputs are 12pt in a
/// 44pt box, and a request body with forty fields has to stay scannable.
private struct StructuredInput: View {
    @Binding var text: String
    var placeholder: String = ""
    var multiline: Bool = false
    var mono: Bool = false
    var keyboard: UIKeyboardType = .default
    var onFocusChange: ((Bool) -> Void)?

    @FocusState private var focused: Bool

    var body: some View {
        field
            .font(mono ? LuckyTheme.Text.code : LuckyTheme.Text.caption)
            .foregroundStyle(LuckyTheme.textPrimary)
            .keyboardType(keyboard)
            // `autoCapitalize="none" autoCorrect={false}`: these are keys, paths and shell
            // fragments, and autocorrect on a Dockerfile is actively harmful.
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)
            .padding(.horizontal, LuckyTheme.Space.m)
            .padding(.vertical, multiline ? 10 : 8)
            .frame(minHeight: multiline ? 112 : 44,
                   alignment: multiline ? .topLeading : .leading)
            .background(background)
            .onChange(of: focused) { onFocusChange?(focused) }
    }

    @ViewBuilder
    private var field: some View {
        if multiline {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(4...14)
        } else {
            TextField(placeholder, text: $text)
        }
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: LuckyTheme.Radius.field, style: .continuous)
        return shape
            .fill(LuckyTheme.surfaceSunken)
            .overlay(
                shape.strokeBorder(
                    focused ? LuckyTheme.accent.opacity(0.7) : LuckyTheme.hairline,
                    lineWidth: focused ? 1.6 : LuckyTheme.strokeWidth
                )
            )
    }
}

/// `NumericField`. The draft is what the user is typing; `value` is what the request will carry.
///
/// The two only synchronise while the field is *not* focused, which is the whole trick: typing `-`
/// or `1.` must not be rewritten under the cursor, but a value changed from outside — or a rejected
/// edit — must snap the text back. A digits-only draft commits live so the request stays current
/// without waiting for a blur.
private struct StructuredNumericField: View {
    var name: String
    var value: Double
    var onChange: (Double) -> Void
    var onRemove: (() -> Void)?

    @State private var draft = ""
    @State private var focused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StructuredFieldHeader(name: name, onRemove: onRemove)
            StructuredInput(text: $draft, keyboard: .numbersAndPunctuation) { isFocused in
                focused = isFocused
                if !isFocused { commit() }
            }
            .onChange(of: draft) {
                // `/^-?\d+(?:\.\d+)?$/.test(text)`: a complete number commits immediately, and
                // anything mid-edit (`-`, `1.`, `1e3`) waits for the blur.
                if Self.isPlainNumber(draft) { onChange(JSCompat.number(draft)) }
            }
            .onChange(of: value, initial: true) { sync() }
        }
    }

    /// `useEffect(() => { if (!focused) setDraft(String(value)); }, [focused, value])`
    private func sync() {
        guard !focused else { return }
        draft = JSONSerializer.numberString(value)
    }

    /// `commit()` — `Number(draft)` must be non-blank and finite, otherwise the draft reverts.
    private func commit() {
        let parsed = JSCompat.number(draft)
        if !draft.jsTrimmed.isEmpty, parsed.isFinite {
            onChange(parsed)
            // The parent may hold the same number (12 → "12.0" → 12), in which case no value
            // change arrives to re-normalise the text, so do it here.
            draft = JSONSerializer.numberString(parsed)
        } else {
            draft = JSONSerializer.numberString(value)
        }
    }

    private static func isPlainNumber(_ text: String) -> Bool {
        var digits = Substring(text)
        if digits.first == "-" { digits.removeFirst() }
        guard let dot = digits.firstIndex(of: ".") else {
            return !digits.isEmpty && digits.allSatisfy(\.isASCIIDigit)
        }
        let whole = digits[..<dot]
        let fraction = digits[digits.index(after: dot)...]
        return !whole.isEmpty && !fraction.isEmpty
            && whole.allSatisfy(\.isASCIIDigit) && fraction.allSatisfy(\.isASCIIDigit)
    }
}

/// `PrimitiveField`: a leaf. Which control appears is decided by the *current* value's type, not by
/// a schema — Lucky has none — so switching a field from text to a number means replacing its value.
private struct StructuredPrimitiveField: View {
    var name: String
    @Binding var value: JSONValue
    var onRemove: (() -> Void)?

    /// `/content|script|dockerfile|forbidden|indexnames|paths|command/i` — the fields whose values
    /// are documents rather than words.
    private static let multilineKeys = ["content", "script", "dockerfile", "forbidden",
                                       "indexnames", "paths", "command"]
    /// `/content|script|dockerfile|command/i` — of those, the ones where alignment carries meaning.
    private static let monoKeys = ["content", "script", "dockerfile", "command"]

    var body: some View {
        if let flag = value.boolValue {
            toggleRow(flag)
        } else if let number = value.doubleValue {
            StructuredNumericField(name: name, value: number,
                                   onChange: { value = .number($0) }, onRemove: onRemove)
        } else {
            textRow
        }
    }

    private func toggleRow(_ flag: Bool) -> some View {
        HStack(spacing: LuckyTheme.Space.m) {
            Text(LuckyFieldName.label(name))
                .font(LuckyTheme.Text.label)
                .foregroundStyle(LuckyTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                // The toggle below carries the same label for VoiceOver; announcing it twice would
                // read as "名称 名称 开关".
                .accessibilityHidden(true)
            Toggle(LuckyFieldName.label(name),
                   isOn: Binding(get: { flag }, set: { value = .bool($0) }))
                .labelsHidden()
                .tint(LuckyTheme.accent)
            if let onRemove {
                StructuredTrashButton(field: name, size: 32, radius: 9, action: onRemove)
            }
        }
        .frame(minHeight: 44)
    }

    private var textRow: some View {
        let multiline = JSRegex.containsAny(name, Self.multilineKeys)
        return VStack(alignment: .leading, spacing: 6) {
            StructuredFieldHeader(name: name, onRemove: onRemove)
            StructuredInput(text: text, multiline: multiline,
                            mono: multiline && JSRegex.containsAny(name, Self.monoKeys))
        }
    }

    /// `value === null || value === undefined ? "" : String(value)` on the way in, and a plain string
    /// on the way out — editing a null field turns it into text, exactly as the original does.
    private var text: Binding<String> {
        Binding(get: { value.asDisplayString }, set: { value = .string($0) })
    }
}

/// `AddField`: closed it is one 添加字段 row; open it is a name, a kind and two verbs. The name is
/// trimmed before the duplicate test, so ` name ` collides with `name`.
private struct StructuredAddField: View {
    var existingKeys: [String]
    var onAdd: (String, JSONValue) -> Void

    @State private var open = false
    @State private var key = ""
    @State private var kind: Kind = .text

    /// The original's five kinds. `switch` is a Swift keyword, so that case is `flag`; the label the
    /// user sees is unchanged.
    private enum Kind: Hashable, CaseIterable {
        case text, number, flag, object, list

        var title: String {
            switch self {
            case .text: "文本"
            case .number: "数字"
            case .flag: "开关"
            case .object: "对象"
            case .list: "列表"
            }
        }

        var initial: JSONValue {
            switch self {
            case .text: .string("")
            case .number: .number(0)
            case .flag: .bool(false)
            case .object: .object(JSONObject())
            case .list: .array([])
            }
        }
    }

    private var normalizedKey: String { key.jsTrimmed }
    private var duplicate: Bool { existingKeys.contains(normalizedKey) }
    private var addable: Bool { !normalizedKey.isEmpty && !duplicate }

    var body: some View {
        if open { editor } else { trigger }
    }

    private var trigger: some View {
        Button {
            withAnimation(LuckyTheme.Motion.snap) { open = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: LuckySymbol.add).font(.system(size: 15, weight: .semibold))
                Text("添加字段").font(LuckyTheme.Text.captionMedium)
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

    private var editor: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            LuckyHairline()
            StructuredInput(text: $key, placeholder: "字段名称")
            if duplicate {
                Text("该字段已存在")
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.danger)
            }
            // Five chips in the original. A segmented control is the native shape for one-of-five,
            // and `glass: false` because this lives inside scrolling content.
            LuckyGlassSegmentedControl(
                selection: $kind,
                segments: Kind.allCases.map { LuckySegment($0, $0.title) },
                glass: false
            )
            HStack(spacing: LuckyTheme.Space.s) {
                verb("取消", filled: false) { close() }
                verb("添加", filled: true) {
                    onAdd(normalizedKey, kind.initial)
                    close()
                }
                .disabled(!addable)
            }
        }
        .padding(.top, LuckyTheme.Space.s)
    }

    private func verb(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(LuckyTheme.Text.captionMedium)
                .foregroundStyle(color(filled: filled))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(background(filled: filled))
        }
        .buttonStyle(.plain)
    }

    private func color(filled: Bool) -> Color {
        guard filled else { return LuckyTheme.textSecondary }
        return addable ? LuckyTheme.textOnAccent : LuckyTheme.textTertiary
    }

    @ViewBuilder
    private func background(filled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: LuckyTheme.Radius.field, style: .continuous)
        if filled {
            shape.fill(addable ? LuckyTheme.accent : LuckyTheme.idleSoft)
        } else {
            shape.strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth)
        }
    }

    private func close() {
        withAnimation(LuckyTheme.Motion.snap) { open = false }
        key = ""
    }
}

/// `ArrayField`: a list whose items may be anything, including more lists.
private struct StructuredArrayField: View {
    var name: String
    @Binding var value: [JSONValue]
    var depth: Int
    var onRemove: (() -> Void)?

    /// The append row, in the original's order. Each button adds one item of that kind.
    private static let kinds: [(String, JSONValue)] = [
        ("文本", .string("")),
        ("数字", .number(0)),
        ("开关", .bool(false)),
        ("对象", .object(JSONObject())),
        ("列表", .array([])),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            StructuredFieldHeader(name: name, onRemove: onRemove)
            ForEach(value.indices, id: \.self) { index in
                row(index)
            }
            append
        }
    }

    /// The original keeps a synthetic key per item so React does not remount the tail when one item
    /// is deleted. SwiftUI has no equivalent for an untyped array, so identity here is the index;
    /// what that trick protected — a numeric field's in-progress draft — self-heals anyway, because
    /// the draft re-reads its value whenever the field is not focused.
    private func row(_ index: Int) -> some View {
        let composite = item(index).isRecord || item(index).isArray
        return HStack(alignment: .top, spacing: LuckyTheme.Space.s) {
            field(index)
                .frame(maxWidth: .infinity, alignment: .leading)
            StructuredTrashButton(field: nil, size: 38, radius: 12, fill: LuckyTheme.dangerSoft) {
                guard value.indices.contains(index) else { return }
                value.remove(at: index)
            }
            // A primitive item's control sits below its own header, so the delete button drops to
            // meet it; a nested record or list starts at the top of the row.
            .padding(.top, composite ? 0 : 30)
        }
    }

    private func field(_ index: Int) -> AnyView {
        let current = item(index)
        if current.isRecord {
            return AnyView(StructuredRecordFields(value: recordBinding(index), depth: depth + 1))
        }
        if current.isArray {
            return AnyView(StructuredArrayField(name: "第 \(index + 1) 项",
                                                value: arrayBinding(index), depth: depth + 1))
        }
        return AnyView(StructuredPrimitiveField(name: "第 \(index + 1) 项",
                                                value: binding(index)))
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
                    .frame(maxWidth: .infinity, minHeight: 40)
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

    /// Bindings are index-based and bounds-checked: SwiftUI can evaluate a row's binding once more
    /// after the row has been deleted, and an unchecked subscript would trap there.
    private func binding(_ index: Int) -> Binding<JSONValue> {
        Binding(get: { item(index) },
                set: { next in
                    guard value.indices.contains(index) else { return }
                    value[index] = next
                })
    }

    private func recordBinding(_ index: Int) -> Binding<JSONObject> {
        let entry = binding(index)
        return Binding(get: { entry.wrappedValue.record },
                       set: { entry.wrappedValue = .object($0) })
    }

    private func arrayBinding(_ index: Int) -> Binding<[JSONValue]> {
        let entry = binding(index)
        return Binding(get: { entry.wrappedValue.list },
                       set: { entry.wrappedValue = .array($0) })
    }
}

/// `RecordFields`: the object editor. Nested levels get a border and an inset so the tree is legible
/// without indentation guides.
struct StructuredRecordFields: View {
    @Binding var value: JSONObject
    var depth: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.m) {
            // Insertion order, which is the order the user created the fields in and the order they
            // will be serialised in.
            ForEach(value.keys, id: \.self) { key in
                entry(key)
            }
            StructuredAddField(existingKeys: value.keys) { key, item in
                value[key] = item
            }
        }
        .padding(depth > 0 ? LuckyTheme.Space.m : 0)
        .background {
            if depth > 0 {
                RoundedRectangle(cornerRadius: LuckyTheme.Radius.row, style: .continuous)
                    .strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth)
            }
        }
    }

    private func entry(_ key: String) -> AnyView {
        let current = value[key] ?? .null
        if current.isRecord {
            // A nested object has no field header of its own, so the label and its delete sit above
            // the sub-editor rather than inside it.
            return AnyView(VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: LuckyTheme.Space.s) {
                    Text(LuckyFieldName.label(key))
                        .font(LuckyTheme.Text.captionMedium)
                        .foregroundStyle(LuckyTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    StructuredTrashButton(field: key, size: 24, radius: 6) { remove(key) }
                }
                StructuredRecordFields(value: recordBinding(key), depth: depth + 1)
            })
        }
        if current.isArray {
            // `depth` rather than `depth + 1`: a list inside an object is not a new box, so it does
            // not gain a border.
            return AnyView(StructuredArrayField(name: key, value: arrayBinding(key), depth: depth,
                                                onRemove: { remove(key) }))
        }
        return AnyView(StructuredPrimitiveField(name: key, value: binding(key),
                                                onRemove: { remove(key) }))
    }

    private func remove(_ key: String) {
        value.removeValue(forKey: key)
    }

    /// Setting through the subscript keeps the key in place — a field must not jump to the end of the
    /// form because its value changed.
    private func binding(_ key: String) -> Binding<JSONValue> {
        Binding(get: { value[key] ?? .null }, set: { value[key] = $0 })
    }

    private func recordBinding(_ key: String) -> Binding<JSONObject> {
        let entry = binding(key)
        return Binding(get: { entry.wrappedValue.record },
                       set: { entry.wrappedValue = .object($0) })
    }

    private func arrayBinding(_ key: String) -> Binding<[JSONValue]> {
        let entry = binding(key)
        return Binding(get: { entry.wrappedValue.list },
                       set: { entry.wrappedValue = .array($0) })
    }
}

/// `StructuredForm` — the exported entry point, and the only name the screens use.
struct StructuredForm: View {
    @Binding var value: JSONObject

    var body: some View {
        StructuredRecordFields(value: $value)
    }
}

/// `StructuredDataView`: the read-only twin of the form, used for every response body in the app.
///
/// It never parses and never formats — whatever `JSONValue` the client produced is what appears, so
/// a response the port cannot interpret still shows all of its fields.
struct StructuredDataView: View {
    var value: JSONValue
    var depth: Int = 0

    /// Every Lucky response carries `{ret, msg}`; the screen shows the status and the message above
    /// the body, so repeating them inside it is noise.
    private static let envelopeKeys = ["ret", "msg"]
    /// A container listing can hold thousands of entries. The original caps the rendered count and
    /// says so, which is also what keeps this view off the main thread's critical path.
    private static let cap = 200

    var body: some View {
        if let object = value.objectValue {
            record(object)
        } else if let items = value.arrayValue {
            list(items)
        } else {
            scalar
        }
    }

    private func record(_ object: JSONObject) -> AnyView {
        let entries = object.pairs.filter { !Self.envelopeKeys.contains($0.key) }
        guard !entries.isEmpty else { return AnyView(hint("暂无数据")) }
        return AnyView(
            VStack(alignment: .leading, spacing: 9) {
                ForEach(entries.prefix(Self.cap), id: \.key) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(LuckyFieldName.label(entry.key))
                            .font(LuckyTheme.Text.captionMedium)
                            .foregroundStyle(LuckyTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        StructuredDataView(value: entry.value, depth: depth + 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, depth > 0 ? 10 : 0)
                    // The rule sits outside the padding, at the group's own leading edge — a
                    // depth marker rather than a table border.
                    .overlay(alignment: .leading) {
                        if depth > 0 {
                            Rectangle()
                                .fill(LuckyTheme.hairline)
                                .frame(width: LuckyTheme.strokeWidth)
                        }
                    }
                }
                if entries.count > Self.cap {
                    note("仅显示前 200 个字段，共 \(entries.count) 个")
                }
            }
        )
    }

    private func list(_ items: [JSONValue]) -> AnyView {
        guard !items.isEmpty else { return AnyView(hint("暂无项目")) }
        return AnyView(
            VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
                ForEach(Array(items.prefix(Self.cap).enumerated()), id: \.offset) { index, item in
                    LuckyInset(padding: 10, spacing: 5) {
                        Text(verbatim: "第 \(index + 1) 项")
                            .font(LuckyTheme.Text.captionMedium)
                            .foregroundStyle(LuckyTheme.textTertiary)
                        StructuredDataView(value: item, depth: depth + 1)
                    }
                }
                if items.count > Self.cap {
                    note("仅显示前 200 项，共 \(items.count) 项")
                }
            }
        )
    }

    /// `value ? '是' : '否'` for a bool, `--` for null and for the empty string, `String(value)`
    /// otherwise. Selectable because a response often holds the token, path or ID the user came for.
    private var scalar: some View {
        Text(text)
            .font(LuckyTheme.Text.caption)
            .foregroundStyle(LuckyTheme.textPrimary)
            .lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var text: String {
        if let flag = value.boolValue { return flag ? "是" : "否" }
        if value.isNull { return "--" }
        let rendered = value.asDisplayString
        return rendered.isEmpty ? "--" : rendered
    }

    private func hint(_ message: String) -> some View {
        Text(message)
            .font(LuckyTheme.Text.caption)
            .foregroundStyle(LuckyTheme.textSecondary)
    }

    /// `Text(verbatim:)` so the count is not grouped — the original interpolates the raw number.
    private func note(_ message: String) -> some View {
        Text(verbatim: message)
            .font(LuckyTheme.Text.caption)
            .foregroundStyle(LuckyTheme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
