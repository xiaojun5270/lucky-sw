import SwiftUI
import UniformTypeIdentifiers

/// The two 证书 sheets from `app/services/[kind].tsx` — 添加证书 and 编辑证书.
///
/// They are the only editors in the app that do *not* go through `StructuredForm`: a certificate is
/// not a flat record but three mutually exclusive shapes (an uploaded pair, a path pair, an ACME
/// order) plus a distribution list, and the ACME shape hides four dozen switches under half a dozen
/// spellings each. So the original hand-writes both, and so does this port.

/// `methods` — the three ways Lucky will accept a certificate.
enum SslAddMethod: String, CaseIterable, Identifiable {
    case file, path, acme

    var id: String { rawValue }

    var label: String {
        switch self {
        case .file: "文件"
        case .path: "文件路径"
        case .acme: "ACME 自动签发"
        }
    }
}

/// Which of the two file rows is being read. The original's `fileBusy: 'cert' | 'key' | ''`.
enum SslFileSlot: String, Identifiable {
    case cert, key

    var id: String { rawValue }
}

/// One entry of a `SslDropdown`'s option list.
struct SslOption: Identifiable, Sendable {
    var label: String
    var value: String

    var id: String { value }
}

/// The inline expanding select shared by both editors.
///
/// A glass `Menu` would be the native answer, but these live *inside* a scroll view where glass may
/// not go — and the original's behaviour is load-bearing besides: one `openSelect` key is shared by
/// all six selects in the ACME editor, so opening one closes the others. That is reproduced by
/// keeping the open field's name in the parent and passing it down.
struct SslDropdown: View {
    var label: String
    var options: [SslOption]
    var current: String
    var open: Bool
    var toggle: () -> Void
    var choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            LuckyFieldLabel(label: label)
            Button(action: toggle) {
                HStack(spacing: LuckyTheme.Space.s) {
                    Text(title)
                        .font(LuckyTheme.Text.body)
                        .foregroundStyle(LuckyTheme.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(open ? LuckyTheme.accent : LuckyTheme.textTertiary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, LuckyTheme.Space.m)
                .frame(height: 44)
                .background(AdvancedField.box)
                .overlay(AdvancedField.stroke)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(LuckyTheme.Motion.snap, value: open)
            if open { list }
        }
    }

    /// `options.find(item => item.value === current)?.label ?? current` — an unrecognised value
    /// prints itself rather than showing an empty field.
    private var title: String {
        options.first(where: { $0.value == current })?.label ?? current
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LuckyTheme.Radius.concentricFloor, style: .continuous)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { pair in
                row(pair.offset, pair.element)
            }
        }
        .background(shape.fill(LuckyTheme.surface))
        .overlay(shape.strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth))
        .clipShape(shape)
    }

    private func row(_ index: Int, _ option: SslOption) -> some View {
        let selected = option.value == current
        return Button {
            choose(option.value)
        } label: {
            VStack(spacing: 0) {
                if index > 0 { LuckyHairline() }
                HStack(spacing: LuckyTheme.Space.s) {
                    Text(option.label)
                        .font(selected ? LuckyTheme.Text.bodyMedium : LuckyTheme.Text.body)
                        .foregroundStyle(selected ? LuckyTheme.accent : LuckyTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(LuckyTheme.accent)
                    }
                }
                .padding(.horizontal, LuckyTheme.Space.m)
                .frame(minHeight: 42)
                .background(selected ? LuckyTheme.accentSoft : Color.clear)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }
}

/// One of the editors' bordered groups — 更多设置, 代理设置, 证书同步.
///
/// The original draws a hairline around each; here the raised inset fill is what separates a group
/// from the card, which is how every other grouped panel in the port reads.
struct SslGroup<Content: View>: View {
    var title: String = ""
    var spacing: CGFloat = 9
    @ViewBuilder var content: () -> Content

    var body: some View {
        LuckyInset(padding: 14, spacing: spacing) {
            if !title.isEmpty {
                Text(title)
                    .font(LuckyTheme.Text.cardTitle)
                    .foregroundStyle(LuckyTheme.textPrimary)
            }
            content()
        }
    }
}

/// The 证书同步 group. Both editors print the switch and the client checkboxes; only 添加证书 prints
/// the 同步客户端列表 caption above the list, and the 将同步到当前全部 N 个客户端 line in its place.
struct SslSyncSection: View {
    var clients: [LuckyListItem]
    @Binding var syncAll: Bool
    @Binding var selected: [String]
    var verbose: Bool

    var body: some View {
        SslGroup(title: "证书同步", spacing: 11) {
            LuckyToggleRow(label: "同步到所有同步客户端", isOn: $syncAll)
            if syncAll {
                if verbose { caption("将同步到当前全部 \(clients.count) 个客户端") }
            } else {
                picker
            }
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 7) {
            if verbose { caption("同步客户端列表") }
            if clients.isEmpty {
                caption("暂无可用同步客户端")
            } else {
                ForEach(Array(clients.enumerated()), id: \.offset) { pair in
                    row(pair.element, ServiceRecord.clientKey(pair.element, pair.offset))
                }
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(LuckyTheme.Text.caption)
            .foregroundStyle(LuckyTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ client: LuckyListItem, _ key: String) -> some View {
        let active = selected.contains(key)
        let shape = RoundedRectangle(cornerRadius: LuckyTheme.Radius.concentricFloor,
                                     style: .continuous)
        return Button {
            toggle(key)
        } label: {
            HStack(spacing: 9) {
                checkbox(active)
                Text(ServiceRecord.pick(client, ["Name", "ClientName", "DeviceName"], key))
                    .font(LuckyTheme.Text.label)
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 42)
            .background(shape.fill(active ? LuckyTheme.accentSoft : LuckyTheme.surface))
            .overlay(shape.strokeBorder(active ? LuckyTheme.accent : LuckyTheme.hairline,
                                       lineWidth: LuckyTheme.strokeWidth))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private func checkbox(_ active: Bool) -> some View {
        let box = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ZStack {
            box.fill(active ? LuckyTheme.accent : LuckyTheme.surface)
            box.strokeBorder(active ? LuckyTheme.accent : LuckyTheme.hairline,
                             lineWidth: LuckyTheme.strokeWidth)
            if active {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LuckyTheme.textOnAccent)
            }
        }
        .frame(width: 20, height: 20)
    }

    /// `toggleClient(key)`.
    private func toggle(_ key: String) {
        if let index = selected.firstIndex(of: key) {
            selected.remove(at: index)
        } else {
            selected.append(key)
        }
    }
}

// MARK: - 添加证书

/// `SslCertificateEditor` — the 添加证书 sheet.
///
/// The three 添加方式 shapes are mutually exclusive in the payload, not just in the form: whichever
/// one is showing supplies its fields and the other two post empty, which is why `submit` writes
/// all eight keys unconditionally.
struct SslCertificateAddSheet: View {
    var busy: Bool
    var syncClients: [LuckyListItem]
    var close: () -> Void
    var save: (JSONObject) -> Void

    @State private var remark = ""
    @State private var addFrom: SslAddMethod = .file
    @State private var methodOpen = false
    @State private var certName = ""
    @State private var keyName = ""
    @State private var certBase64 = ""
    @State private var keyBase64 = ""
    @State private var certPath = ""
    @State private var keyPath = ""
    @State private var domains = ""
    @State private var syncAll = false
    @State private var selectedClients: [String] = []
    /// Set when the row is tapped rather than when the bytes arrive, so 正在读取... shows for as long
    /// as the picker is up — which is what the original's awaited `getDocumentAsync` does.
    @State private var fileBusy: SslFileSlot?
    @State private var pickingCert = false
    @State private var pickingKey = false
    @State private var failure = ""

    private static var methods: [SslOption] {
        SslAddMethod.allCases.map { SslOption(label: $0.label, value: $0.rawValue) }
    }

    var body: some View {
        ServiceSheet(title: "添加证书", close: close) {
            // The original weights 取消 at `flex: 1` against 添加 at `flex: 1.35`; two glass pills in
            // a bar split the width evenly instead.
            LuckyPillButton(title: "取消", symbol: "xmark") { close() }
                .disabled(busy)
            LuckyPillButton(title: busy ? "添加中..." : "添加", symbol: "plus",
                            prominent: true, loading: busy) {
                submit()
            }
            .disabled(fileBusy != nil)
        } content: {
            LuckyCard {
                LuckyTextField(label: "证书备注", text: $remark, placeholder: "可留空")
                SslDropdown(label: "添加方式", options: Self.methods,
                            current: addFrom.rawValue, open: methodOpen) {
                    methodOpen.toggle()
                } choose: { value in
                    addFrom = SslAddMethod(rawValue: value) ?? .file
                    methodOpen = false
                    failure = ""
                }
                method
                SslSyncSection(clients: syncClients, syncAll: $syncAll,
                               selected: $selectedClients, verbose: true)
            }
            if !failure.isEmpty {
                LuckyErrorCard(message: failure, title: "无法添加")
            }
        }
        .fileImporter(isPresented: $pickingCert, allowedContentTypes: [.item]) { result in
            load(.cert, result)
        }
        .fileImporter(isPresented: $pickingKey, allowedContentTypes: [.item]) { result in
            load(.key, result)
        }
    }

    @ViewBuilder
    private var method: some View {
        switch addFrom {
        case .file:
            filePicker("证书", slot: .cert, name: certName, loaded: !certBase64.isEmpty,
                       symbol: "arrow.up.doc", placeholder: "选择要上传的证书文件")
            filePicker("Key", slot: .key, name: keyName, loaded: !keyBase64.isEmpty,
                       symbol: "key.horizontal", placeholder: "选择要上传的 Key 文件")
        case .path:
            LuckyTextField(label: "证书路径", text: $certPath, mono: true)
            LuckyTextField(label: "Key 路径", text: $keyPath, mono: true)
        case .acme:
            LuckyTextField(label: "签发域名", text: $domains, placeholder: "每行填写一个域名",
                           multiline: true)
        }
    }
}

// MARK: - File selection

extension SslCertificateAddSheet {
    /// One of the two 44pt file rows. The border turns green once bytes are in hand, which is the
    /// only confirmation the user gets that the pair is complete.
    func filePicker(_ label: String, slot: SslFileSlot, name: String, loaded: Bool,
                    symbol: String, placeholder: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: LuckyTheme.Radius.concentricFloor,
                                     style: .continuous)
        return VStack(alignment: .leading, spacing: 7) {
            LuckyFieldLabel(label: label, tone: loaded ? .ok : nil)
            Button {
                fileBusy = slot
                failure = ""
                switch slot {
                case .cert: pickingCert = true
                case .key: pickingKey = true
                }
            } label: {
                HStack(spacing: LuckyTheme.Space.s) {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(loaded ? LuckyTheme.success : LuckyTheme.accent)
                    Text(fileBusy == slot ? "正在读取..." : (name.isEmpty ? placeholder : name))
                        .font(LuckyTheme.Text.body)
                        .foregroundStyle(name.isEmpty ? LuckyTheme.textSecondary
                                                      : LuckyTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if loaded {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(LuckyTheme.success)
                    }
                }
                .padding(.horizontal, LuckyTheme.Space.m)
                .frame(minHeight: 44)
                .background(shape.fill(LuckyTheme.surface))
                .overlay(shape.strokeBorder(loaded ? LuckyTheme.success : LuckyTheme.hairline,
                                            lineWidth: LuckyTheme.strokeWidth))
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .disabled(fileBusy != nil)
        }
    }

    /// `chooseFile(type)`. The original filters on five MIME types, one of which is
    /// `application/octet-stream` — so the effective filter is "any file", which is `.item`.
    /// A cancelled pick leaves every field untouched, exactly like `result.canceled`.
    func load(_ slot: SslFileSlot, _ result: Result<URL, Error>) {
        defer { fileBusy = nil }
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let encoded = try Data(contentsOf: url).base64EncodedString()
            switch slot {
            case .cert:
                certName = url.lastPathComponent
                certBase64 = encoded
            case .key:
                keyName = url.lastPathComponent
                keyBase64 = encoded
            }
        } catch {
            guard !error.isCancellation,
                  (error as NSError).code != NSUserCancelledError else { return }
            failure = "无法读取所选文件"
        }
    }

    /// `submit()`. Every key is written on every method so the server never sees a stale path next
    /// to fresh bytes, and `SyncInfo` repeats the two distribution fields because different Lucky
    /// builds read one or the other.
    func submit() {
        let acmeDomains = ServiceRecord.splitList(domains)
        if addFrom == .file, certBase64.isEmpty { failure = "请选择证书文件"; return }
        if addFrom == .file, keyBase64.isEmpty { failure = "请选择 Key 文件"; return }
        if addFrom == .path, certPath.jsTrimmed.isEmpty { failure = "请填写证书文件路径"; return }
        if addFrom == .path, keyPath.jsTrimmed.isEmpty { failure = "请填写 Key 文件路径"; return }
        if addFrom == .acme, acmeDomains.isEmpty { failure = "请至少填写一个签发域名"; return }
        let all = syncClients.enumerated().map { ServiceRecord.clientKey($1, $0) }
        let keys = JSONValue.array((syncAll ? all : selectedClients).map(JSONValue.string))
        let issued = JSONValue.array(acmeDomains.map(JSONValue.string))
        var params = JSONObject()
        if addFrom == .acme { params["acmeDomains"] = issued }
        var info = JSONObject()
        info["SyncAllClients"] = .bool(syncAll)
        info["SyncClients"] = keys
        var value = JSONObject()
        value["Remark"] = .string(remark.jsTrimmed)
        value["AddFrom"] = .string(addFrom.rawValue)
        value["Enable"] = .bool(true)
        value["CertBase64"] = .string(addFrom == .file ? certBase64 : "")
        value["KeyBase64"] = .string(addFrom == .file ? keyBase64 : "")
        value["CertFile"] = .string(addFrom == .path ? certPath.jsTrimmed : certName)
        value["KeyFile"] = .string(addFrom == .path ? keyPath.jsTrimmed : keyName)
        value["Domains"] = addFrom == .acme ? issued : .array([])
        value["ExtParams"] = .object(params)
        value["SyncAllClients"] = .bool(syncAll)
        value["SyncClients"] = keys
        value["SyncInfo"] = .object(info)
        failure = ""
        save(value)
    }
}

// MARK: - 编辑证书

/// `SslAcmeEditor` — the 编辑证书 sheet, for a certificate whose 添加方式 is ACME.
///
/// Everything it edits lives in `ExtParams`, and every field there has two to four accepted
/// spellings depending on the Lucky build. So `read`/`write` address a *list* of names and write
/// back to whichever one the record already used — editing never adds a second casing of a field
/// the server is already reading.
struct SslAcmeEditor: View {
    var request: ServiceEditorRequest
    var busy: Bool
    var syncClients: [LuckyListItem]
    var close: () -> Void
    var save: (JSONObject) -> Void

    /// The record as it arrived. `submit` spreads it back out, so the two dozen ACME fields this
    /// form does not show survive the round trip.
    private let initial: JSONObject
    private let initialSync: JSONObject

    @State private var remark: String
    @State private var ext: JSONObject
    @State private var syncAll: Bool
    @State private var selected: [String]
    /// `openSelect` — the one open dropdown, keyed by its first field name, so opening any select
    /// closes the others.
    @State private var openSelect = ""
    @State private var failure = ""

    init(request: ServiceEditorRequest, busy: Bool, syncClients: [LuckyListItem],
         close: @escaping () -> Void, save: @escaping (JSONObject) -> Void) {
        self.request = request
        self.busy = busy
        self.syncClients = syncClients
        self.close = close
        self.save = save
        let record = request.value
        let sync = ServiceRecord.child(.object(record), "SyncInfo").record
        initial = record
        initialSync = sync
        _remark = State(initialValue: record["Remark"]?.asDisplayString ?? "")
        _ext = State(initialValue: ServiceRecord.child(.object(record), "ExtParams").record)
        let flag = Self.coalesce(record["SyncAllClients"], sync["SyncAllClients"])
        _syncAll = State(initialValue: flag?.isTruthy ?? false)
        let list = Self.coalesce(record["SyncClients"], sync["SyncClients"])
        _selected = State(initialValue: list?.arrayValue?.map(\.asDisplayString) ?? [])
    }

    /// `a ?? b`, which falls through on `null` as well as on a missing key.
    private static func coalesce(_ first: JSONValue?, _ second: JSONValue?) -> JSONValue? {
        guard let first, !first.isNull else { return second }
        return first
    }
}

// MARK: - ExtParams access

extension SslAcmeEditor {
    /// `childRecord(ext, 'DNS')`.
    var dns: JSONObject { ServiceRecord.child(.object(ext), "DNS").record }

    /// `existingKey(keys)` — the spelling this record already uses, or the canonical one.
    func existingKey(_ keys: [String]) -> String {
        keys.first(where: { ext.has($0) }) ?? keys[0]
    }

    /// `read(keys, fallback)` — `ext[key] !== undefined`, so an explicit `null` wins over the
    /// fallback and prints as an empty field.
    func read(_ keys: [String], _ fallback: JSONValue = .string("")) -> JSONValue {
        for key in keys {
            if let value = ext[key] { return value }
        }
        return fallback
    }

    func write(_ keys: [String], _ next: JSONValue) {
        ext[existingKey(keys)] = next
    }

    /// `readDns(keys, fallback)` — the nested credential first, then the flat one.
    func readDns(_ keys: [String], _ fallback: JSONValue = .string("")) -> JSONValue {
        let nested = dns
        for key in keys {
            if let value = nested[key] { return value }
        }
        return read(keys, fallback)
    }

    /// Provider credentials sit under `ExtParams.DNS` in newer builds and flat in older ones, so a
    /// write only nests when the record already has something nested.
    func writeDns(_ keys: [String], _ next: JSONValue) {
        var nested = dns
        guard !nested.isEmpty else {
            write(keys, next)
            return
        }
        nested[keys.first(where: { nested.has($0) }) ?? keys[0]] = next
        ext["DNS"] = .object(nested)
    }
}

// MARK: - Generated fields

extension SslAcmeEditor {
    /// `Field` — an array in the record joins with newlines, and is written back as an array only
    /// for the domain and list fields, matching the original's `/domains|list/i` on the key names.
    func binding(_ keys: [String], _ fallback: JSONValue,
                 dnsField: Bool, multiline: Bool) -> Binding<String> {
        let asList = multiline && keys.contains { JSRegex.containsAny($0, ["domains", "list"]) }
        return Binding(
            get: {
                let raw = dnsField ? readDns(keys, fallback) : read(keys, fallback)
                guard let items = raw.arrayValue else { return raw.asDisplayString }
                return items.map(\.asDisplayString).joined(separator: "\n")
            },
            set: { next in
                let value: JSONValue = asList
                    ? .array(ServiceRecord.splitList(next).map(JSONValue.string))
                    : .string(next)
                if dnsField {
                    writeDns(keys, value)
                } else {
                    write(keys, value)
                }
            }
        )
    }

    /// The port's machine-value fields are monospaced: `LuckyTextField` couples "never capitalise,
    /// never autocorrect" — which is what the original sets on every one of these — to `mono`.
    func field(_ label: String, _ keys: [String], fallback: JSONValue = .string(""),
               dnsField: Bool = false, multiline: Bool = false,
               secret: Bool = false) -> some View {
        LuckyTextField(
            label: label,
            text: binding(keys, fallback, dnsField: dnsField, multiline: multiline),
            mono: !secret,
            secure: secret,
            multiline: multiline
        )
    }

    /// `Toggle` — `Boolean(read(keys, false))`, JavaScript truthiness, under which the *string*
    /// `"false"` reads as on. `Format.asEnabled` would read it as off; the original does not, and
    /// the value round-trips through this form untouched either way.
    func toggle(_ label: String, _ keys: [String]) -> some View {
        LuckyToggleRow(label: label, isOn: Binding(
            get: { read(keys, .bool(false)).isTruthy },
            set: { write(keys, .bool($0)) }
        ))
    }

    /// `SelectField` — `openSelect === keys[0]`, so the six selects share one open slot.
    func select(_ label: String, _ keys: [String], _ options: [SslOption],
                dnsField: Bool = false) -> some View {
        let field = keys[0]
        let fallback = JSONValue.string(options.first?.value ?? "")
        let current = dnsField ? readDns(keys, fallback) : read(keys, fallback)
        return SslDropdown(label: label, options: options, current: current.asDisplayString,
                           open: openSelect == field) {
            openSelect = openSelect == field ? "" : field
        } choose: { value in
            if dnsField {
                writeDns(keys, .string(value))
            } else {
                write(keys, .string(value))
            }
            openSelect = ""
        }
    }

    /// `Stepper` — `Number(read(keys, fallback)) || fallback`, so a 0 in the record reads as the
    /// default rather than as zero.
    func stepper(_ label: String, _ keys: [String], _ fallback: Int) -> some View {
        let stored = read(keys, .number(Double(fallback)))
        let value = stored.asNumber == 0 ? fallback : stored.asInt
        return SslStepperRow(label: label, value: value) { next in
            write(keys, .number(Double(next)))
        }
    }
}

/// The −10 / +10 pair around a numeric field, which is how the original exposes the two ACME
/// timeouts. Both buttons are `AdvancedIconButton`s, the same in-card control the 高级操作 sheet uses.
struct SslStepperRow: View {
    var label: String
    var value: Int
    var change: (Int) -> Void

    var body: some View {
        HStack(spacing: LuckyTheme.Space.s) {
            Text(label)
                .font(LuckyTheme.Text.label)
                .foregroundStyle(LuckyTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            AdvancedIconButton(label: "减少", symbol: "minus", color: LuckyTheme.accent,
                               fill: LuckyTheme.surface, size: 34, radius: 8, glyph: 15) {
                change(max(0, value - 10))
            }
            entry
            AdvancedIconButton(label: "增加", symbol: "plus", color: LuckyTheme.accent,
                               fill: LuckyTheme.surface, size: 34, radius: 8, glyph: 15) {
                change(value + 10)
            }
        }
        .frame(minHeight: 42)
    }

    private var entry: some View {
        let box = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return TextField("", text: Binding(
            get: { String(value) },
            set: { change(Self.parseInt($0)) }
        ))
        .textFieldStyle(.plain)
        .font(LuckyTheme.Text.body)
        .foregroundStyle(LuckyTheme.textPrimary)
        .tint(LuckyTheme.accent)
        .multilineTextAlignment(.center)
        .keyboardType(.numberPad)
        .frame(width: 64, height: 36)
        .background(box.fill(LuckyTheme.surface))
        .overlay(box.strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth))
    }

    /// `Number.parseInt(text, 10) || 0` — a leading sign and the digits that follow it, and 0 for
    /// anything else. The keyboard is a number pad, so the general case never arrives.
    private static func parseInt(_ text: String) -> Int {
        var digits = ""
        for character in text.jsTrimmed {
            if digits.isEmpty, character == "-" || character == "+" {
                digits.append(character)
                continue
            }
            guard character.isASCII, character.isNumber else { break }
            digits.append(character)
        }
        return Int(digits) ?? 0
    }
}

// MARK: - The ACME option lists

extension SslAcmeEditor {
    static let addOptions = [SslOption(label: "ACME", value: "acme")]

    static let caOptions = [
        SslOption(label: "Let's Encrypt", value: "letsencrypt"),
        SslOption(label: "ZeroSSL", value: "zerossl"),
        SslOption(label: "Google Trust Services", value: "google"),
        SslOption(label: "自定义 ACME", value: "custom"),
    ]

    static let dnsOptions = [
        SslOption(label: "阿里云", value: "alidns"),
        SslOption(label: "腾讯云 DNSPod", value: "dnspod"),
        SslOption(label: "Cloudflare", value: "cloudflare"),
        SslOption(label: "华为云", value: "huaweicloud"),
        SslOption(label: "手动 DNS", value: "manual"),
    ]

    static let algorithmOptions = [
        SslOption(label: "RSA2048", value: "RSA2048"),
        SslOption(label: "RSA4096", value: "RSA4096"),
        SslOption(label: "EC256", value: "EC256"),
        SslOption(label: "EC384", value: "EC384"),
    ]

    static let certConfigOptions = [
        SslOption(label: "默认（普通域名证书）", value: "default"),
        SslOption(label: "短期证书", value: "shortlived"),
        SslOption(label: "自定义", value: "custom"),
    ]

    static let proxyOptions = [
        SslOption(label: "禁用", value: "disabled"),
        SslOption(label: "HTTP", value: "http"),
        SslOption(label: "SOCKS5", value: "socks5"),
    ]

    static let eabKeys = ["enableEAB", "EnableEAB", "EABEnable"]
    static let domainKeys = ["acmeDomains", "Domains"]
    static let proxyKeys = ["proxyType", "ProxyType"]
}

// MARK: - The ACME form

extension SslAcmeEditor {
    var body: some View {
        ServiceSheet(title: "编辑证书", close: close) {
            LuckyPillButton(title: "取消", symbol: "xmark") { close() }
                .disabled(busy)
            LuckyPillButton(title: busy ? "保存中..." : "修改", symbol: "square.and.arrow.down",
                            prominent: true, loading: busy) {
                submit()
            }
        } content: {
            LuckyCard {
                identityFields
                dnsFields
                moreSettingsGroup
                proxyGroup
                mappingGroup
                SslSyncSection(clients: syncClients, syncAll: $syncAll,
                               selected: $selected, verbose: false)
            }
            if !failure.isEmpty {
                LuckyErrorCard(message: failure, title: "无法保存")
            }
        }
    }

    @ViewBuilder
    var identityFields: some View {
        LuckyTextField(label: "证书备注", text: $remark)
        select("添加方式", ["AddFrom"], Self.addOptions)
        select("证书颁发机构", ["acmeCA", "ACMECA", "CA"], Self.caOptions)
        toggle("EAB 认证", Self.eabKeys)
        if read(Self.eabKeys, .bool(false)).isTruthy {
            field("EAB Key ID", ["eabKid", "EABKid", "EABKeyID"])
            field("EAB HMAC Key", ["eabHmacKey", "EABHmacKey"], secret: true)
        }
    }

    @ViewBuilder
    var dnsFields: some View {
        select("验证方式", ["dnsProvider", "DNSProvider", "Provider", "Type"], Self.dnsOptions,
               dnsField: true)
        field("ID", ["ID", "id", "AccessKeyID", "AccessKeyId"], dnsField: true)
        field("Secret", ["Secret", "secret", "AccessKeySecret"], dnsField: true, secret: true)
        field("域名/IP 列表", Self.domainKeys, fallback: .string(initialDomains), multiline: true)
        field("电子邮箱", ["email", "Email"])
        select("算法选择", ["algorithm", "Algorithm", "KeyType"], Self.algorithmOptions)
        select("证书配置", ["certConfig", "CertConfig", "CertificateProfile"],
               Self.certConfigOptions)
    }

    /// The 域名/IP 列表 fallback: the record's own `Domains`, one per line.
    var initialDomains: String {
        guard let items = initial["Domains"]?.arrayValue else { return "" }
        return items.map(\.asDisplayString).joined(separator: "\n")
    }
}

// MARK: - The ACME groups

extension SslAcmeEditor {
    var moreSettingsGroup: some View {
        SslGroup(title: "更多设置") {
            keyToggles
            dnsToggles
            steppers
        }
    }

    @ViewBuilder
    var keyToggles: some View {
        toggle("每次请求轮换私钥", ["renewPrivateKey", "RenewPrivateKey"])
        toggle("使用全局私钥", ["useGlobalPrivateKey", "UseGlobalPrivateKey"])
        toggle("串行化验证", ["sequential", "Sequential"])
        toggle("通过 DNS 查询获取主域名", ["findZoneByFqdn", "FindZoneByFqdn"])
        toggle("CNAME 支持", ["cnameSupport", "CNAMEFollow"])
        toggle("使用 IPv4 网络申请证书", ["useIPv4", "UseIPv4"])
    }

    @ViewBuilder
    var dnsToggles: some View {
        toggle("DNS 查询强制 IPv4", ["dnsQueryIPv4", "DNSQueryIPv4"])
        toggle("DNS 查询仅使用 TCP", ["dnsQueryTCP", "DNSQueryTCP"])
        toggle("禁用完整传播要求", ["disableCompletePropagationRequirement",
                              "DisableCompletePropagationRequirement"])
        toggle("忽略传播检查错误", ["ignorePropagationCheckError",
                              "IgnorePropagationCheckError"])
        toggle("禁用权威 NS 传播检查", ["disableAuthoritativeNssPropagationRequirement",
                                "DisableAuthoritativeNssPropagationRequirement"])
    }

    @ViewBuilder
    var steppers: some View {
        stepper("传播检测超时（秒）", ["propagationTimeout", "PropagationTimeout"], 600)
        stepper("等待证书最长时间（秒）",
                ["certTimeout", "CertTimeout", "WaitCertificateTimeout"], 120)
    }

    var proxyGroup: some View {
        SslGroup(title: "代理设置") {
            select("代理类型", Self.proxyKeys, Self.proxyOptions)
            if read(Self.proxyKeys, .string("disabled")).asDisplayString != "disabled" {
                field("代理地址", ["proxyURL", "ProxyURL"])
            }
        }
    }

    var mappingGroup: some View {
        SslGroup {
            toggle("证书映射", ["enableCertMapping", "EnableCertMapping", "CertMapping"])
        }
    }

    /// `submit()`. The domain list is read back out of `ExtParams` rather than off a state field,
    /// because that is where every keystroke went — and it is written to *both* `Domains` and the
    /// spelling `ExtParams` already used, since Lucky renews from the latter and lists from the
    /// former.
    func submit() {
        let raw = initial["Domains"] ?? .array([])
        let stored = read(Self.domainKeys, raw.isNull ? .array([]) : raw)
        let domains: [String]
        if let items = stored.arrayValue {
            domains = items.map(\.asDisplayString).filter { !$0.jsTrimmed.isEmpty }
        } else {
            domains = ServiceRecord.splitList(stored.asDisplayString)
        }
        guard !domains.isEmpty else {
            failure = "请至少填写一个域名或 IP"
            return
        }
        let all = syncClients.enumerated().map { ServiceRecord.clientKey($1, $0) }
        let keys = JSONValue.array((syncAll ? all : selected).map(JSONValue.string))
        let issued = JSONValue.array(domains.map(JSONValue.string))
        var params = ext
        params[existingKey(Self.domainKeys)] = issued
        var sync = initialSync
        sync["SyncAllClients"] = .bool(syncAll)
        sync["SyncClients"] = keys
        var value = initial
        value["Remark"] = .string(remark.jsTrimmed)
        value["AddFrom"] = .string("acme")
        value["Domains"] = issued
        value["ExtParams"] = .object(params)
        value["SyncAllClients"] = .bool(syncAll)
        value["SyncClients"] = keys
        value["SyncInfo"] = .object(sync)
        failure = ""
        save(value)
    }
}
