import Foundation

/// The TypeScript union `TunnelKind | TunnelCollection | 'stun-settings'` as one enum.
///
/// The three modules and their three child collections already have enums in `TunnelsService`,
/// but every form in `src/components/tunnel-form.tsx` is driven by a single discriminator — and
/// `stun-settings` belongs to neither set — so the port flattens all seven spellings into the
/// strings the original switches on.
enum TunnelFormType: String, Hashable, Sendable, Identifiable {
    case stun, cloudflared, frp
    case ingress, proxies, visitors
    case stunSettings = "stun-settings"

    var id: String { rawValue }

    init(_ kind: TunnelKind) {
        switch kind {
        case .stun: self = .stun
        case .cloudflared: self = .cloudflared
        case .frp: self = .frp
        }
    }

    init(_ collection: TunnelCollection) {
        switch collection {
        case .ingress: self = .ingress
        case .proxies: self = .proxies
        case .visitors: self = .visitors
        }
    }

    /// Non-nil for the three child forms, which is how the editor knows to post to a parent rule
    /// rather than to the module itself.
    var collection: TunnelCollection? { TunnelCollection(rawValue: rawValue) }

    /// `fixedMode` in the original form component. STUN has no 高级设置 fold: the second field
    /// table appears only in 定制模式, and 全局设置 has no second table at all.
    var fixedMode: Bool { self == .stun || self == .stunSettings }
}

/// `Field` — one row of a tunnel form, as declared by the module rather than by a schema.
struct TunnelField: Identifiable, Sendable {
    /// The original's `type`, whose absent case is a single-line string field.
    enum Kind: Sendable { case number, toggle, lines, multiline, secret }

    var key: String
    var label: String
    var kind: Kind?
    /// A fixed set of values, rendered as wrapping chips. An empty string is a real option — it
    /// is how 代理类型 spells 无.
    var options: [String]?
    var required = false
    var min: Int?
    var max: Int?

    /// The dotted key is unique within a table, and `Options.SafeMode` never collides with a
    /// top-level `SafeMode` because only one of them is ever listed.
    var id: String { key }

    /// `field(key, label, type?, extra)`.
    static func spec(_ key: String, _ label: String, _ kind: Kind? = nil,
                     options: [String]? = nil, required: Bool = false,
                     min: Int? = nil, max: Int? = nil) -> TunnelField {
        TunnelField(key: key, label: label, kind: kind, options: options,
                    required: required, min: min, max: max)
    }

    /// `port(key, label, required)` — every port shares one range, and a required port may not be
    /// 0 because 0 is what this module means by 自动.
    static func port(_ key: String, _ label: String, _ required: Bool = false) -> TunnelField {
        TunnelField(key: key, label: label, kind: .number, required: required,
                    min: required ? 1 : 0, max: 65535)
    }
}

/// The data half of `src/components/tunnel-form.tsx` — defaults, field tables, dotted-path reads
/// and writes, validation and the mutually exclusive switch rules.
///
/// It is a separate namespace from the `TunnelForm` view because `TunnelScreen` needs the
/// validator without rendering anything: 保存 runs `validate` before it ever reaches the network.
enum TunnelSpec {
    // MARK: - Dotted paths

    /// `get(value, key)` — the original folds the path with
    /// `(current, part) => record(current)[part]`.
    ///
    /// A segment that is not a plain object ends the walk with nothing, exactly as indexing the
    /// `{}` that `record` substitutes would.
    static func read(_ value: JSONObject, _ key: String) -> JSONValue? {
        var current = JSONValue.object(value)
        for part in key.components(separatedBy: ".") {
            guard current.isRecord, let next = current[part] else { return nil }
            current = next
        }
        return current
    }

    /// `set(value, key, next)` — a fresh record down the path.
    ///
    /// `JSONObject`'s subscript updates an existing key in place and appends a new one, which is
    /// precisely the ordering `{ ...value, [head]: … }` produces.
    static func write(_ value: JSONObject, _ key: String, _ next: JSONValue) -> JSONObject {
        var parts = key.components(separatedBy: ".")
        let head = parts.removeFirst()
        var updated = value
        if parts.isEmpty {
            updated[head] = next
        } else {
            let child = (value[head] ?? .null).record
            updated[head] = .object(write(child, parts.joined(separator: "."), next))
        }
        return updated
    }

    /// `record(value[key])` — the nested reads the STUN tables and the FRP `Params` do.
    static func nested(_ value: JSONObject, _ key: String) -> JSONObject {
        (value[key] ?? .null).record
    }

    /// `Boolean(value[key])`, where a missing key and an explicit `null` are both falsy.
    static func truthy(_ value: JSONObject, _ key: String) -> Bool {
        value[key]?.isTruthy ?? false
    }
}

// MARK: - JavaScript coercions

extension TunnelSpec {
    /// `String(value)`.
    ///
    /// Only this file needs it. `JSONValue.asDisplayString` prints an array as JSON, while
    /// `String(['a', 'b'])` is `a,b` — and the required-field check below turns on exactly that
    /// difference, because `String([])` is falsy but `[]` serialised as JSON is not.
    static func stringify(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let flag): return flag ? "true" : "false"
        case .number(let number): return JSONSerializer.numberString(number)
        case .string(let text): return text
        // `Array.prototype.join` prints `null` and `undefined` as the empty string.
        case .array(let items):
            return items.map { $0.isNull ? "" : stringify($0) }.joined(separator: ",")
        case .object: return "[object Object]"
        case .binary: return "[object Blob]"
        }
    }

    /// `Number(value)` — the coercion `JSONValue.asNumber` deliberately does not perform, since
    /// that one folds `NaN` to 0 and the integer check below is what has to reject junk.
    ///
    /// Arrays route through `stringify` on purpose: `Number([])` is 0, `Number([5])` is 5 and
    /// `Number([1, 2])` is `NaN`, all of which fall out of coercing the joined text.
    static func coerce(_ value: JSONValue) -> Double {
        switch value {
        case .null: return 0
        case .bool(let flag): return flag ? 1 : 0
        case .number(let number): return number
        case .string(let text): return JSCompat.number(text)
        case .array, .object, .binary: return JSCompat.number(stringify(value))
        }
    }
}

// MARK: - Option labels

extension TunnelSpec {
    /// `optionLabels` — the option values that get a Chinese name. Protocol spellings like `tcp`
    /// and `quic` are absent on purpose: they print themselves.
    static let optionLabels: [String: String] = [
        "": "无",
        "simple": "简易模式",
        "diy": "定制模式",
        "client": "客户端",
        "server": "服务端",
        "tunnel": "Tunnel 隧道",
        "access": "Access 访问",
        "auto": "自动",
        "ip": "IP 地址",
        "networkInterface": "指定网卡",
        "tcp4": "TCP / IPv4",
        "udp4": "UDP / IPv4",
        "blacklist": "黑名单",
        "globalblacklist": "全局黑名单",
        "whitelist": "白名单",
    ]

    /// `optionLabels[option] ?? option`.
    static func optionLabel(_ option: String) -> String { optionLabels[option] ?? option }
}

// MARK: - Validation

extension TunnelSpec {
    /// `validateTunnelForm(type, value)` — the gate every 保存 passes through.
    ///
    /// It both checks and rewrites: a `number` field replaces its text with a real number and a
    /// `lines` field replaces its array with a trimmed, compacted one, so what the caller posts
    /// is the normalised record rather than what the fields held.
    ///
    /// The active table is computed once from the record as it arrived — a rewrite cannot change
    /// which fields are visible half-way down the loop — but each field is read from the record
    /// as it stands, which is what lets 重试间隔 see the 重试次数 the loop just wrote.
    static func validate(_ type: TunnelFormType, _ value: JSONObject) throws -> JSONObject {
        var result = value
        for field in activeFields(type, value) {
            let current = read(result, field.key)
            if field.required { try requireValue(current, field.label) }
            if field.kind == .number, let current {
                result = write(result, field.key, .number(try integer(current, field)))
            }
            if field.kind == .lines {
                let items = (current?.arrayValue ?? [])
                    .map { stringify($0).jsTrimmed }
                    .filter { !$0.isEmpty }
                result = write(result, field.key, .array(items.map { .string($0) }))
            }
        }
        try checkCrossFields(type, result)
        // `['kcp', 'quic'].includes(String(record(result.Params).Protocol))` — TCP multiplexing is
        // a TCP feature, so the two datagram protocols silently switch it off.
        if type == .frp {
            let name = stringify(nested(result, "Params")["Protocol"] ?? .null)
            if name == "kcp" || name == "quic" {
                result = write(result, "Params.TCPMux", .bool(false))
            }
        }
        return result
    }

    /// The union the original assembles inline. STUN validates its 定制模式 table only while that
    /// mode is selected, 全局设置 has no advanced table, and every other form validates both.
    private static func activeFields(_ type: TunnelFormType,
                                     _ value: JSONObject) -> [TunnelField] {
        var active = fields(type, value, advanced: false)
        switch type {
        case .stun:
            if value["DiaglogShowMode"]?.stringValue == "diy" {
                active += fields(type, value, advanced: true)
            }
        case .stunSettings:
            break
        default:
            active += fields(type, value, advanced: true)
        }
        return active
    }

    /// `v == null || !String(v).trim() || (Array.isArray(v) && !v.some(x => String(x).trim()))`.
    ///
    /// The array clause is what stops a 签发域名 list of blank lines from counting as filled — and
    /// note that a list holding a single `null` passes the string test, because `String([null])`
    /// is the four characters `null`, so only the third clause catches it.
    private static func requireValue(_ value: JSONValue?, _ label: String) throws {
        guard let value, !value.isNull, !stringify(value).jsTrimmed.isEmpty else {
            throw LuckyError("请填写\(label)")
        }
        guard let items = value.arrayValue else { return }
        guard items.contains(where: { !stringify($0).jsTrimmed.isEmpty }) else {
            throw LuckyError("请填写\(label)")
        }
    }

    /// The `number` branch: an empty string, a non-integer, and anything outside the declared
    /// bounds are all the same single error.
    private static func integer(_ value: JSONValue, _ field: TunnelField) throws -> Double {
        let number = coerce(value)
        // `!Number.isInteger(n)` covers `NaN` and both infinities as well as 1.5.
        var invalid = !number.isFinite || number != number.rounded(.towardZero)
        // `v === ''` is checked separately because `Number('')` is a perfectly good 0.
        if value.stringValue == "" { invalid = true }
        if let min = field.min, number < Double(min) { invalid = true }
        if let max = field.max, number > Double(max) { invalid = true }
        guard !invalid else { throw LuckyError("\(field.label)范围无效\(rangeHint(field))") }
        return number
    }

    /// The parenthetical the range error carries. A field with no declared minimum prints nothing
    /// at all, and one with only a minimum prints `（N 起）`.
    private static func rangeHint(_ field: TunnelField) -> String {
        guard let min = field.min else { return "" }
        guard let max = field.max else { return "（\(min) 起）" }
        return "（\(min)～\(max)）"
    }

    /// The three checks that read more than one field at once, and so cannot live in the loop.
    private static func checkCrossFields(_ type: TunnelFormType, _ result: JSONObject) throws {
        if type == .stun || type == .stunSettings, truthy(result, "WebhookEnable") {
            // `String(result.WebhookURL ?? '')` — `??` steps over `null` but not over `false`.
            var url = JSONValue.string("")
            if let stored = result["WebhookURL"], !stored.isNull { url = stored }
            guard !stringify(url).jsTrimmed.isEmpty, truthy(result, "WebhookMethod") else {
                throw LuckyError("请填写 Webhook 地址和请求方法")
            }
        }
        // Both ask the router to open a port, and a router that honours both opens it twice.
        if type == .stun, truthy(result, "NatPMP"), truthy(result, "UPnP") {
            throw LuckyError("NAT-PMP 和 UPnP 只能启用一项")
        }
    }
}

// MARK: - Editing

extension TunnelSpec {
    /// `updateTunnelFormValue(type, value, key, next)` — every field edit goes through here.
    ///
    /// Two things happen that a plain assignment could not. Switching an instance's 类型 re-seeds
    /// `Params` from the new type's defaults so the keys that type needs exist, while keeping
    /// whatever the record already carried on top. And the STUN form's three forwarding switches
    /// clear each other, because the module refuses a configuration that asks for two of them.
    static func update(_ type: TunnelFormType, _ value: JSONObject,
                       key: String, next: JSONValue) -> JSONObject {
        if key == "Type", type == .frp || type == .cloudflared {
            let seeded = nested(defaults(type, mode: stringify(next)), "Params")
            var updated = value
            updated["Type"] = next
            updated["Params"] = .object(seeded.merging(nested(value, "Params")))
            return updated
        }
        var updated = write(value, key, next)
        guard type == .stun else { return updated }
        // In 简易模式 the switches the user cannot see are cleared too, so the record it posts
        // matches what the visible fields say.
        let simple = updated["DiaglogShowMode"]?.stringValue != "diy"
        // `next === true` — turning a switch *off* releases nothing.
        guard next.boolValue == true else { return updated }
        switch key {
        case "AutoOptionsFirewall":
            updated["DisablePortForward"] = .bool(false)
        case "UPnP", "NatPMP":
            updated[key == "UPnP" ? "NatPMP" : "UPnP"] = .bool(false)
            if simple {
                updated["AutoOptionsFirewall"] = .bool(false)
                updated["DisablePortForward"] = .bool(false)
            }
        case "DisablePortForward" where simple:
            updated["UPnP"] = .bool(false)
            updated["NatPMP"] = .bool(false)
            updated["AutoOptionsFirewall"] = .bool(false)
        default:
            break
        }
        return updated
    }
}
