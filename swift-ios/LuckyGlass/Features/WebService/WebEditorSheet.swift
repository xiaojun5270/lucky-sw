import SwiftUI

/// `webRuleDraftSequence` / `nextWebRuleDraftId()` — the counter that gives every sub-rule card an
/// identity independent of its index, so removing the second one cannot leave the third expanded in
/// its place.
///
/// `nonisolated(unsafe)` rather than a lock: the only caller is the editor, which is main-actor by
/// way of `View`, and the counter exists solely to keep two cards apart.
enum WebDraftId {
    nonisolated(unsafe) private static var sequence = 0

    /// `` `web-rule-draft-${++webRuleDraftSequence}` ``
    static func next() -> String {
        sequence += 1
        return "web-rule-draft-\(sequence)"
    }
}

/// The 移除子规则 confirmation, which outlives the row that raised it — hence the captured index and
/// name rather than a lookup at button time.
struct WebProxyRemoval: Identifiable {
    var index: Int
    var draftId: String
    var name: String

    var id: String { draftId }
}

/// §20–§23 `WebServiceEditor` — the one sheet behind all six editor kinds.
///
/// `request.kind` decides both the initial state (§20) and the form (§21): a rule is folded onto
/// `newRule()` with its proxies normalised, a stand-alone sub-rule is normalised on its own, and
/// everything else is edited as it arrived — 分组 and CGI by named rows, anything else by the raw
/// `StructuredForm`.
struct WebEditorSheet: View {
    var request: WebEditorRequest
    var busy: Bool
    /// The screen's `editorFailure`. Drawn only while `formError` is empty, which is the original's
    /// `!formError && serverError`.
    var failure: String
    var filterOptions: [WebOption]
    var groupOptions: [WebOption]
    var wafOptions: [WebOption]
    var subWafOptions: [WebOption]
    var close: () -> Void
    var save: (JSONObject) -> Void

    /// `useState(() => …)` — seeded once and never re-derived, so a refetch behind the sheet cannot
    /// overwrite what is being typed.
    @State private var value: JSONObject
    /// `proxyDraftIds`, one per `ProxyList` entry, travelling with the entry and not the index.
    @State private var proxyDraftIds: [String]
    @State private var expandedProxyId = ""
    @State private var openSelect = ""
    @State private var formError = ""
    /// `Alert.alert` inside `removeProxy`. A screen-level alert cannot present over an open sheet,
    /// so the confirmation is state on the sheet itself.
    @State private var removal: WebProxyRemoval?

    init(request: WebEditorRequest, busy: Bool, failure: String, filterOptions: [WebOption],
         groupOptions: [WebOption], wafOptions: [WebOption], subWafOptions: [WebOption],
         close: @escaping () -> Void, save: @escaping (JSONObject) -> Void) {
        self.request = request
        self.busy = busy
        self.failure = failure
        self.filterOptions = filterOptions
        self.groupOptions = groupOptions
        self.wafOptions = wafOptions
        self.subWafOptions = subWafOptions
        self.close = close
        self.save = save
        let seeded = Self.initialValue(request)
        _value = State(initialValue: seeded)
        let entries = WebRecord.array(.object(seeded), ["ProxyList"])
        _proxyDraftIds = State(initialValue: entries.map { _ in WebDraftId.next() })
    }

    var body: some View {
        ServiceSheet(title: request.title, close: close) {
            LuckyPillButton(title: saveLabel, symbol: "square.and.arrow.down",
                            prominent: true, loading: busy) {
                commit()
            }
            .disabled(busy)
        } content: {
            form
            // The original pins both cards between the scroll view and the button row; here they
            // trail the content, which is where a message about the form above belongs anyway.
            if !formError.isEmpty {
                LuckyErrorCard(message: formError, title: "无法保存")
            } else if !failure.isEmpty {
                LuckyErrorCard(message: failure)
            }
        }
        .alert("移除子规则", isPresented: removing, presenting: removal) { target in
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) { removeProxy(target) }
        } message: { target in
            Text("确定从当前规则中移除“\(target.name)”吗？")
        }
    }
}

extension WebEditorSheet {
    /// `busy ? "保存中" : type === "subrule" ? (key ? "保存子规则" : "添加子规则") : "保存配置"`
    private var saveLabel: String {
        if busy { return "保存中" }
        guard request.kind == .subrule else { return "保存配置" }
        return (request.key ?? "").isEmpty ? "添加子规则" : "保存子规则"
    }

    private var removing: Binding<Bool> {
        Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })
    }
}

// MARK: - §20 初始状态

extension WebEditorSheet {
    /// `clone(editor.value)` — which is the assignment itself, `JSONObject` being a value type.
    ///
    /// Only 规则 and 子规则 are folded onto a factory record; every other kind is edited exactly as it
    /// arrived, because the editor has no idea what shape those carry.
    private static func initialValue(_ request: WebEditorRequest) -> JSONObject {
        let initial = request.value.record
        if request.kind == .subrule {
            return WebRecord.normalizeProxy(.object(initial), WebService.newSubRule().record)
        }
        guard request.kind == .rule else { return initial }
        let defaults = WebService.newRule().record
        var next = defaults.merging(initial)
        next["DiaglogShowMode"] = showMode(initial, defaults)
        next["CorazaWAFInstance"] = .string(wafInstance(initial, defaults))
        let proxyDefaults = defaults["DefaultProxy"]?.record ?? JSONObject()
        next["DefaultProxy"] = .object(WebRecord.normalizeProxy(initial["DefaultProxy"],
                                                               proxyDefaults))
        next["ProxyList"] = .array(WebRecord.array(.object(initial), ["ProxyList"]).map {
            .object(WebRecord.normalizeProxy($0, WebService.newSubRule().record))
        })
        // `delete`, not `= null`: a null would travel back to the module as a real value.
        next.removeValue(forKey: "CorazaWAFKey")
        return next
    }

    /// `initial.DiaglogShowMode === "full" ? "diy" : initial.DiaglogShowMode ?? defaults…` — `full`
    /// is Lucky's old name for 定制模式, and `??` skips null as well as absent.
    private static func showMode(_ initial: JSONObject, _ defaults: JSONObject) -> JSONValue {
        let mode = initial["DiaglogShowMode"]
        if mode?.stringValue == "full" { return .string("diy") }
        if let mode, !mode.isNull { return mode }
        return defaults["DiaglogShowMode"] ?? .string("simple")
    }

    /// `String(a.CorazaWAFInstance || a.CorazaWAFKey || defaults.CorazaWAFInstance || "")` — `||`
    /// walks past an empty string too, which is what folds the renamed key in.
    private static func wafInstance(_ initial: JSONObject, _ defaults: JSONObject) -> String {
        let candidates = [initial["CorazaWAFInstance"], initial["CorazaWAFKey"],
                          defaults["CorazaWAFInstance"]]
        for candidate in candidates where candidate?.isTruthy == true {
            return candidate?.asDisplayString ?? ""
        }
        return ""
    }
}

// MARK: - 写入

extension WebEditorSheet {
    private var context: WebEditorContext {
        WebEditorContext(filterOptions: filterOptions, groupOptions: groupOptions,
                         wafOptions: wafOptions, subWafOptions: subWafOptions)
    }

    /// `{...current, [key]: next}` — `JSONObject`'s setter overwrites in place and appends a new
    /// key at the end, so this is the spread exactly.
    private func update(_ key: String, _ next: JSONValue) {
        value[key] = next
    }

    private var proxyDefaults: JSONObject { WebService.newDefaultProxy().record }

    /// `{...newWebServiceDefaultProxy(), ...object(value.DefaultProxy)}` — a plain merge and *not*
    /// `normalizeWebProxy`, so §21.2 draws whatever the rule stored and the migrations happen once,
    /// at mount and at save.
    private var defaultProxy: JSONObject {
        proxyDefaults.merging(value["DefaultProxy"]?.record ?? JSONObject())
    }

    /// Rebuilt from the factory on every keystroke, which is how a default proxy stored without a
    /// key gains one.
    private func updateDefaultProxy(_ key: String, _ next: JSONValue) {
        var proxy = defaultProxy
        proxy[key] = next
        value["DefaultProxy"] = .object(proxy)
    }

    private var proxies: [JSONValue] { WebRecord.array(.object(value), ["ProxyList"]) }

    /// `{...item, [key]: next}` for the one entry at `index`. An entry that is not an object reads
    /// as `{}` here, where the original would spread its characters — a shape nothing writes.
    private func updateProxy(_ index: Int, _ key: String, _ next: JSONValue) {
        value["ProxyList"] = .array(proxies.enumerated().map { offset, item in
            guard offset == index else { return item }
            var record = item.record
            record[key] = next
            return .object(record)
        })
    }

    /// A new entry, a new draft id, and the new card opened — the one place the accordion expands
    /// without a tap.
    private func addProxy() {
        let draftId = WebDraftId.next()
        value["ProxyList"] = .array(proxies + [WebService.newSubRule()])
        proxyDraftIds.append(draftId)
        expandedProxyId = draftId
    }
}

extension WebEditorSheet {
    /// The 移除 button only raises the confirmation.
    ///
    /// `pick(item ?? {}, ["Remark"], `子规则 ${index + 1}`)` — and here, unlike the card's own title,
    /// there is **no** `|| fallback`, so an entry whose remark is an explicit empty string is asked
    /// about as 确定从当前规则中移除“”吗？
    private func confirmRemove(_ index: Int, _ draftId: String) {
        let list = proxies
        let item = index < list.count ? list[index] : nil
        let name = WebRecord.pick(item, ["Remark"], "子规则 \(index + 1)")
        removal = WebProxyRemoval(index: index, draftId: draftId, name: name)
    }

    /// `filter((_, i) => i !== index)` over both arrays, and the accordion closed if it was showing
    /// the entry that just went away.
    private func removeProxy(_ target: WebProxyRemoval) {
        value["ProxyList"] = .array(proxies.enumerated()
            .filter { $0.offset != target.index }
            .map(\.element))
        proxyDraftIds = proxyDraftIds.enumerated()
            .filter { $0.offset != target.index }
            .map(\.element)
        if expandedProxyId == target.draftId { expandedProxyId = "" }
    }

    /// `applyWafToAllProxies` — the rule's own instance copied into the default proxy and every
    /// sub-rule, which is what makes the button under §21.1's WAF row worth having.
    private func applyWafToAllProxies() {
        let instance = value["CorazaWAFInstance"]?.asDisplayString ?? ""
        var proxy = defaultProxy
        proxy["CorazaWAFInstance"] = .string(instance)
        value["DefaultProxy"] = .object(proxy)
        value["ProxyList"] = .array(proxies.map { item in
            var record = item.record
            record["CorazaWAFInstance"] = .string(instance)
            return .object(record)
        })
    }

    /// `String(value.Network ?? "tcp6")` — the reading `ListenTypeSelector` also uses, where a null
    /// network means tcp6 rather than nothing.
    private var networkValue: String {
        guard let raw = value["Network"], !raw.isNull else { return "tcp6" }
        return raw.asDisplayString
    }

    /// Turning off the only remaining family is refused rather than clamped, so a rule can never
    /// end up listening on neither.
    private func toggleListenType(_ type: String) {
        let network = networkValue
        var ipv4 = network == "tcp" || network == "tcp4"
        var ipv6 = network == "tcp" || network == "tcp6"
        if type == "tcp4" { ipv4 = !ipv4 } else { ipv6 = !ipv6 }
        guard ipv4 || ipv6 else { return }
        update("Network", .string(ipv4 && ipv6 ? "tcp" : ipv4 ? "tcp4" : "tcp6"))
    }
}

// MARK: - §22 校验

extension WebEditorSheet {
    private func commit() {
        guard let next = validated() else { return }
        formError = ""
        save(next)
    }

    /// A kind the editor has no rules for saves exactly what it holds.
    private func validated() -> JSONObject? {
        if request.kind == .subrule { return validatedSubRule() }
        guard request.kind == .rule else { return value }
        return validatedRule()
    }

    private func validatedSubRule() -> JSONObject? {
        guard let normalized = normalizeProxy(.object(value), "子规则") else { return nil }
        // `!editor.tlsEnabled` — an absent flag is falsy, so a sub-rule opened without a parent is
        // treated as though TLS were off.
        let type = normalized["WebServiceType"]?.asDisplayString ?? ""
        if request.tlsEnabled != true, WebEditorContext.tlsOnlyTypes.contains(type) {
            formError = "当前服务类型需要先在主规则中启用 TLS"
            return nil
        }
        return normalized
    }

    /// `normalizeProxy(item, label)` — the per-proxy check, returning nil after setting the message
    /// the original sets, and otherwise the canonical record with both address lists cleaned.
    ///
    /// The Basic-auth arm reads raw truthiness rather than `asBoolean`, faithfully: a
    /// `UseRuleGlobalAuthSettings` holding the *string* `"false"` is truthy and skips the check.
    private func normalizeProxy(_ item: JSONValue?, _ label: String) -> JSONObject? {
        var canonical = WebRecord.normalizeProxy(item, WebService.newSubRule().record)
        let domains = WebRecord.lines(canonical["Domains"])
        let locations = WebRecord.lines(canonical["Locations"])
        if domains.isEmpty {
            formError = "\(label)至少需要一个前端地址"
            return nil
        }
        let type = canonical["WebServiceType"]?.asDisplayString ?? ""
        if ["reverseproxy", "redirect", "url"].contains(type), locations.isEmpty {
            formError = "\(label)必须填写目标地址"
            return nil
        }
        if canonical["UseRuleGlobalAuthSettings"]?.isTruthy != true,
           canonical["EnableBasicAuth"]?.isTruthy == true,
           basicAuthList(canonical).isEmpty {
            formError = "\(label)启用 Basic 认证后必须填写认证用户"
            return nil
        }
        canonical["Domains"] = .array(domains.map { .string($0) })
        canonical["Locations"] = .array(locations.map { .string($0) })
        return canonical
    }

    /// `String(record.BasicAuthUserList ?? "").trim()`
    private func basicAuthList(_ record: JSONObject) -> String {
        (record["BasicAuthUserList"]?.asDisplayString ?? "").jsTrimmed
    }
}

extension WebEditorSheet {
    /// `Number.isInteger(value)` — finite with no fractional part, so NaN fails and so does 443.5.
    private static func isInteger(_ value: Double) -> Bool {
        value.isFinite && value == value.rounded(.towardZero)
    }

    /// §22's ladder for a rule, in the original's order: listen types, port, TLS version, the
    /// default proxy, then every sub-rule. The first failure wins and nothing is saved.
    private func validatedRule() -> JSONObject? {
        // `String(value.Network ?? "")` — and note the default is the empty string here, not the
        // `"tcp6"` the toggle reads with, so a rule that lost its network fails the first check.
        let network = value["Network"]?.asDisplayString ?? ""
        let port = WebRecord.jsNumber(value["ListenPort"])
        let version = WebRecord.jsNumber(value["TLSMinVersion"])
        let tls = WebRecord.bool(value["EnableTLS"])
        if !["tcp", "tcp4", "tcp6"].contains(network) {
            formError = "请选择至少一种监听类型"
            return nil
        }
        if !Self.isInteger(port) || port < 1 || port > 65535 {
            formError = "监听端口必须在 1 到 65535 之间"
            return nil
        }
        if tls, !Self.isInteger(version) || version < 0 || version > 3 {
            formError = "请选择有效的 TLS 最低版本"
            return nil
        }
        guard let proxy = validatedDefaultProxy(tls), let list = validatedProxies(tls) else {
            return nil
        }
        var next = value
        next["Network"] = .string(network)
        // A `TLSMinVersion` that is NaN only gets this far with TLS off, and `JSON.stringify(NaN)`
        // is `null` — which is what the serializer writes for a non-finite number too.
        next["ListenPort"] = .number(port)
        next["TLSMinVersion"] = .number(version)
        next["DefaultProxy"] = .object(proxy)
        next["ProxyList"] = .array(list)
        return next
    }

    /// The default proxy carries no 前端地址, so it is checked for a target only when it redirects.
    private func validatedDefaultProxy(_ tls: Bool) -> JSONObject? {
        let proxy = WebRecord.normalizeProxy(value["DefaultProxy"], proxyDefaults)
        let type = proxy["WebServiceType"]?.asDisplayString ?? ""
        if !tls, WebEditorContext.tlsOnlyTypes.contains(type) {
            formError = "默认规则的当前服务类型需要启用 TLS"
            return nil
        }
        let locations = WebRecord.lines(proxy["Locations"])
        if ["redirect", "url"].contains(type), locations.isEmpty {
            formError = "默认规则使用跳转服务时必须填写目标地址"
            return nil
        }
        if proxy["UseRuleGlobalAuthSettings"]?.isTruthy != true,
           proxy["EnableBasicAuth"]?.isTruthy == true, basicAuthList(proxy).isEmpty {
            formError = "默认规则启用 Basic 认证后必须填写认证用户"
            return nil
        }
        var next = proxy
        next["Locations"] = .array(locations.map { .string($0) })
        return next
    }

    private func validatedProxies(_ tls: Bool) -> [JSONValue]? {
        var result: [JSONValue] = []
        for (index, item) in proxies.enumerated() {
            // The label carries a trailing space, so the message reads 子规则 1 至少需要一个前端地址.
            guard let normalized = normalizeProxy(item, "子规则 \(index + 1) ") else { return nil }
            let type = normalized["WebServiceType"]?.asDisplayString ?? ""
            if !tls, WebEditorContext.tlsOnlyTypes.contains(type) {
                formError = "子规则 \(index + 1) 的当前服务类型需要启用 TLS"
                return nil
            }
            result.append(.object(normalized))
        }
        return result
    }
}

// MARK: - §21 表单

extension WebEditorSheet {
    @ViewBuilder
    private var form: some View {
        switch request.kind {
        case .rule: ruleForm
        case .subrule: subRuleForm
        case .group: groupForm
        case .cgi: cgiForm
        // 模块设置 and 模板 have no named rows, so they edit as raw JSON — the same fallthrough the
        // original takes.
        default: LuckyCard { StructuredForm(value: $value) }
        }
    }

    /// `String(value.DiaglogShowMode ?? "simple")` — what the accordion passes down.
    private var ruleMode: String {
        guard let raw = value["DiaglogShowMode"], !raw.isNull else { return "simple" }
        return raw.asDisplayString
    }

    /// `value.DiaglogShowMode === "diy"` — a strict comparison against the raw value, which is why
    /// this is not `ruleMode == "diy"`. The two can only disagree for a mode that is not a string,
    /// and nothing writes one.
    private var diyMode: Bool { value["DiaglogShowMode"]?.stringValue == "diy" }

    private var tlsEnabled: Bool { WebRecord.bool(value["EnableTLS"]) }

    /// The default proxy's own type, compared strictly everywhere §21.2 reads it.
    private var defaultType: String? { defaultProxy["WebServiceType"]?.stringValue }

    @ViewBuilder
    private var ruleForm: some View {
        WebFormSection(title: "规则设置", symbol: "slider.horizontal.3") {
            ruleListen
            ruleService
        }
        WebFormSection(title: "默认规则", symbol: "globe") {
            defaultIdentity
            defaultSwitches
            WebSecurityHeading()
            WebSecurityFields(data: defaultProxy, scope: "default-security",
                              showIpFilter: diyMode || defaultType == "SNIRouting",
                              context: context, openSelect: $openSelect,
                              write: updateDefaultProxy)
        }
        WebEditorProxyList(proxies: proxies, draftIds: proxyDraftIds, ruleMode: ruleMode,
                           tlsEnabled: tlsEnabled, context: context,
                           expandedProxyId: $expandedProxyId, openSelect: $openSelect,
                           write: updateProxy, remove: confirmRemove, add: addProxy)
    }
}

// MARK: - §21.1 规则设置

extension WebEditorSheet {
    /// The four values are strings because `Choices` compares the *stringified* record value, which
    /// is what lets a numeric `TLSMinVersion` of 2 select TLS 1.2.
    private static let tlsVersions = [
        WebOption("TLS 1.0", "0"), WebOption("TLS 1.1", "1"),
        WebOption("TLS 1.2", "2"), WebOption("TLS 1.3", "3"),
    ]

    private static let showModes = [WebOption("简易模式", "simple"), WebOption("定制模式", "diy")]

    @ViewBuilder
    private var ruleListen: some View {
        WebField(label: "Web 服务规则名称", field: "RuleName", data: value, placeholder: "可留空",
                 write: update)
        WebToggle(label: "规则开关", field: "Enable", data: value, write: update)
        WebChoices(label: "操作模式", field: "DiaglogShowMode", options: Self.showModes,
                   data: value, write: update)
        WebListenTypes(data: value, toggle: toggleListenType)
        // 监听地址 is a 定制模式 concern: 简易模式 listens on every interface.
        if diyMode {
            WebField(label: "监听地址", field: "ListenIP", data: value,
                     hint: "没有特殊需求可留空", write: update)
        }
        WebPortStepper(data: value, write: update)
    }

    @ViewBuilder
    private var ruleService: some View {
        WebSelect(label: "IP 过滤规则", field: "IPFilterRule", options: filterOptions, data: value,
                  openSelect: $openSelect, write: update)
        WebToggle(label: "自动放行防火墙", field: "AutoOptionsFirewall", data: value, write: update)
        WebToggle(label: "TLS", field: "EnableTLS", data: value, write: update)
        if tlsEnabled {
            WebChoices(label: "TLS 最低版本", field: "TLSMinVersion", options: Self.tlsVersions,
                       data: value, write: update)
            if diyMode {
                WebToggle(label: "启用 HTTP/3", field: "Http3", data: value, write: update)
            }
        }
        if diyMode {
            WebField(label: "最大请求头 (KB)", field: "MaxHeaderKBytes", data: value,
                     numeric: true, write: update)
        }
        WebSelect(label: "CorazaWAF", field: "CorazaWAFInstance", options: wafOptions, data: value,
                  openSelect: $openSelect, write: update)
        wafButton
    }

    /// 应用到所有子规则. Drawn rather than a `ServiceActionButton(fill: .tinted)`: §21.1 gives it a
    /// full-strength accent border over the plain card fill, where the shared control tints both.
    private var wafButton: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button(action: applyWafToAllProxies) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 17, weight: .semibold))
                Text("应用到所有子规则")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(LuckyTheme.accent)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(shape.fill(LuckyTheme.surface))
            .overlay(shape.strokeBorder(LuckyTheme.accent, lineWidth: LuckyTheme.strokeWidth))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - §21.2 默认规则

extension WebEditorSheet {
    /// The third arm of the filter is `option.value === defaultProxy.WebServiceType`, so an SNI
    /// default proxy keeps its type even while the rule's TLS is off.
    private var defaultServiceTypes: [WebOption] {
        WebEditorContext.serviceTypes(tlsEnabled: tlsEnabled,
                                      current: defaultProxy["WebServiceType"])
    }

    private var reverseDefault: Bool { defaultType == "reverseproxy" }

    @ViewBuilder
    private var defaultIdentity: some View {
        WebSelect(label: "分组", field: "GroupKey", options: groupOptions, data: defaultProxy,
                  scope: "default", openSelect: $openSelect, write: updateDefaultProxy)
        WebSelect(label: "服务类型", field: "WebServiceType", options: defaultServiceTypes,
                  data: defaultProxy, scope: "default", openSelect: $openSelect,
                  write: updateDefaultProxy)
        // A reverse proxy may leave its targets empty and serve nothing; a redirect may not, which
        // is why only this label, placeholder and hint change with the type.
        WebField(label: reverseDefault ? "默认目标地址" : "跳转目标地址", field: "Locations",
                 data: defaultProxy,
                 placeholder: reverseDefault ? "没有特殊需求可留空" : "请填写跳转目标地址",
                 hint: reverseDefault ? "每行填写一个地址，多行时依次负载均衡" : nil,
                 multiline: true, write: updateDefaultProxy)
    }

    @ViewBuilder
    private var defaultSwitches: some View {
        WebSelect(label: "CorazaWAF", field: "CorazaWAFInstance", options: subWafOptions,
                  data: defaultProxy, scope: "default", openSelect: $openSelect,
                  write: updateDefaultProxy)
        WebToggle(label: "万事大吉", field: "EasyLucky", data: defaultProxy,
                  write: updateDefaultProxy)
        WebToggle(label: "忽略后端 TLS 证书验证", field: "LocationInsecureSkipVerify",
                  data: defaultProxy, write: updateDefaultProxy)
        WebToggle(label: "使用目标地址 Host 请求头", field: "UseTargetHost", data: defaultProxy,
                  write: updateDefaultProxy)
        WebToggle(label: "自动反代重定向", field: "AutoProxyLocation", data: defaultProxy,
                  write: updateDefaultProxy)
        if diyMode, WebRecord.bool(defaultProxy["AutoProxyLocation"]) {
            WebToggle(label: "不同 Host 也自动改写重定向",
                      field: "AutoProxyLocationWithoutSameHost", data: defaultProxy,
                      write: updateDefaultProxy)
        }
        WebToggle(label: "记录访问日志", field: "EnableAccessLog", data: defaultProxy,
                  write: updateDefaultProxy)
    }
}

// MARK: - §21.3 子规则 / 分组 / CGI

extension WebEditorSheet {
    /// A stand-alone sub-rule edits the same two field groups the accordion draws, only in sections
    /// of their own — and `showIpFilter` reads `editor.ruleMode`, which is `undefined` when the row
    /// was opened from a list rather than from inside a rule.
    @ViewBuilder
    private var subRuleForm: some View {
        WebFormSection(title: "基础设置", symbol: LuckySymbol.network) {
            WebSubRuleFields(data: value, scope: "subrule", ruleMode: request.ruleMode ?? "simple",
                             tlsEnabled: request.tlsEnabled ?? false, context: context,
                             openSelect: $openSelect, write: update)
        }
        WebFormSection(title: "安全设置", symbol: "checkmark.shield") {
            WebSecurityFields(data: value, scope: "subrule-security",
                              showIpFilter: subRuleIpFilter, context: context,
                              openSelect: $openSelect, write: update)
        }
    }

    private var subRuleIpFilter: Bool {
        request.ruleMode == "diy" || value["WebServiceType"]?.stringValue == "SNIRouting"
    }

    /// The original leaves these rows bare on the modal's own card surface; here they need a card
    /// of their own, since the sheet is drawn over the page backdrop.
    private var groupForm: some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            WebField(label: "分组名称", field: "Name", data: value, write: update)
            // `editor.key ? … : null` — an existing group shows its key, read-only; a new one has
            // none to show.
            if !(request.key ?? "").isEmpty {
                WebField(label: "分组 Key", field: "Key", data: value, readOnly: true,
                         write: update)
            }
        }
    }

    private var cgiForm: some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            cgiIdentity
            cgiLimits
        }
    }
}

extension WebEditorSheet {
    /// `options: ["php", "fastcgi"]` — `Choices` accepts bare strings and labels each with itself.
    private static let cgiTypes = [WebOption("php", "php"), WebOption("fastcgi", "fastcgi")]

    private static let cgiNetworks = [
        WebOption("tcp", "tcp"), WebOption("tcp4", "tcp4"),
        WebOption("tcp6", "tcp6"), WebOption("unix", "unix"),
    ]

    @ViewBuilder
    private var cgiIdentity: some View {
        WebField(label: "实例名称", field: "Name", data: value, write: update)
        WebToggle(label: "启用 CGI", field: "Enable", data: value, write: update)
        WebChoices(label: "CGI 类型", field: "CGIType", options: Self.cgiTypes, data: value,
                   write: update)
        WebChoices(label: "网络协议", field: "Network", options: Self.cgiNetworks, data: value,
                   write: update)
        WebField(label: "服务地址", field: "Address", data: value, hint: "例如 127.0.0.1:9000",
                 write: update)
    }

    @ViewBuilder
    private var cgiLimits: some View {
        WebField(label: "最大连接数", field: "MaxConns", data: value, numeric: true, write: update)
        WebField(label: "连接超时（秒）", field: "ConnectTimeout", data: value, numeric: true,
                 write: update)
        WebField(label: "默认文档根目录", field: "DefaultDocRoot", data: value, write: update)
        WebField(label: "默认首页", field: "DefaultIndexNames", data: value, hint: "每行一个文件名",
                 multiline: true, write: update)
        WebField(label: "文件扩展名", field: "FileExtensions", data: value, write: update)
        WebField(label: "禁止访问路径", field: "ForbiddenPaths", data: value, multiline: true,
                 write: update)
    }
}
