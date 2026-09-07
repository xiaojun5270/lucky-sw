import Foundation

/// `webservice.tsx`'s own value readers.
///
/// The screen ships a second set of these alongside `ServiceRecord`'s, and the two do not agree:
/// `pick` here answers `""` by default and takes any string or number, where `ServiceRecord.pick`
/// answers `--` and skips a blank string; `bool` treats a whitespace-only string as absent, where
/// `Format.asEnabled` only tests for an empty one. Sharing either would change what the rows print,
/// so both are reimplemented against the helpers this screen actually calls.
enum WebRecord {
    /// `pick(item, keys, fallback = "")` — the first key holding a string or a number, stringified.
    /// A boolean, an object or an array at that key is skipped rather than stringified, which is
    /// what keeps `Enable: true` out of a name column.
    static func pick(_ item: JSONValue?, _ keys: [String], _ fallback: String = "") -> String {
        guard let record = item?.objectValue else { return fallback }
        for key in keys {
            switch record[key] {
            case .string(let text): return text
            case .number(let number): return JSONSerializer.numberString(number)
            default: continue
            }
        }
        return fallback
    }

    /// `keyOf(item, index)`. The position is the last resort, so a module answering rules without
    /// keys still gives every row a distinct identity.
    static func key(_ item: JSONValue?, _ index: Int) -> String {
        pick(item, ["RuleKey", "Key", "key", "ID", "id"], String(index))
    }

    /// `asBoolean(value, fallback = false)` — absent, null or blank answers the fallback;
    /// `false`, `0` and the five disabled words answer false; **everything else answers true**, so
    /// a module replying `"nope"` reads as enabled.
    static func bool(_ value: JSONValue?, _ fallback: Bool = false) -> Bool {
        guard let value, !value.isNull else { return fallback }
        if case .string(let text) = value, text.jsTrimmed.isEmpty { return fallback }
        if case .bool(false) = value { return false }
        if case .number(let number) = value, number == 0 { return false }
        if case .string(let text) = value, Format.isDisabledWord(text) { return false }
        return true
    }

    /// `enabled(item)` = `asBoolean(item.Enable ?? item.enable, true)`. `??` skips an absent or
    /// null key only, so `Enable: false` is honoured and `Enable: null` falls through to `enable`.
    static func isEnabled(_ item: JSONValue?) -> Bool {
        for name in ["Enable", "enable"] {
            guard let value = item?[name], !value.isNull else { continue }
            return bool(value, true)
        }
        return true
    }

    /// `array(item, keys)` — the first key holding an array. A key holding a record or a string is
    /// passed over rather than wrapped.
    static func array(_ item: JSONValue?, _ keys: [String]) -> [JSONValue] {
        guard let record = item?.objectValue else { return [] }
        for key in keys {
            if let list = record[key]?.arrayValue { return list }
        }
        return []
    }

    /// `cleanLines(value)` — an array maps `String` over its elements, anything else stringifies
    /// once and splits on newlines; then every entry is trimmed and the empties dropped.
    ///
    /// The branches disagree about null: an element inside the array goes through `String(null)`
    /// and survives as the literal `null`, while a bare null hits `String(value ?? "")` and becomes
    /// the empty string that the filter then drops. Both are reproduced.
    static func lines(_ value: JSONValue?) -> [String] {
        let raw: [String]
        if let list = value?.arrayValue {
            raw = list.map { $0.isNull ? "null" : $0.asDisplayString }
        } else {
            raw = (value?.asDisplayString ?? "").jsLines
        }
        return raw.map(\.jsTrimmed).filter { !$0.isEmpty }
    }

    /// `move(keys, index, offset)` — a plain swap. A target past either end answers the list
    /// unchanged, which is how the 上移 / 下移 buttons stay harmless at the ends of a list.
    static func move(_ keys: [String], _ index: Int, _ offset: Int) -> [String] {
        var next = keys
        let target = index + offset
        guard target >= 0, target < next.count, index >= 0, index < next.count else { return next }
        next.swapAt(index, target)
        return next
    }
}

// MARK: - 日志载荷

extension WebRecord {
    /// The key list `webLogEntries` walks, verbatim and in order. Seven modules answer log pages
    /// under seven different names, and `text` at the end catches the ones that answer a blob.
    private static let logKeys = ["accessDetails", "accessDetail", "clientList", "clients",
                                  "corazaLogs", "httpLogs", "logs", "lastLogs", "lastlogs",
                                  "rows", "items", "list", "text"]

    /// `entriesFromCandidate` — an array is already a row list; a string is a block of lines, each
    /// trimmed at the *end* only so indentation survives; anything else is no candidate, which is
    /// the `undefined` the caller tests for.
    private static func entries(_ value: JSONValue?) -> [JSONValue]? {
        if let list = value?.arrayValue { return list }
        if case .string(let text) = value {
            let rows = text.jsLines.map(\.jsTrimmedEnd).filter { !$0.isEmpty }
            return rows.map { JSONValue.string($0) }
        }
        return nil
    }

    /// The step-3 sweep: the first of `logKeys` that holds an array or a string.
    private static func named(_ record: JSONObject) -> [JSONValue]? {
        for key in logKeys {
            if let found = entries(record[key]) { return found }
        }
        return nil
    }

    /// `webLogEntries(value)` — flattens whatever a log endpoint answered into rows.
    static func logEntries(_ value: JSONValue?) -> [JSONValue] {
        if let direct = entries(value) { return direct }
        guard let value, !value.isNull else { return [] }
        guard let record = value.objectValue else { return [value] }
        if let found = named(record) { return found }
        for key in ["data", "result"] {
            guard let nested = record[key] else { continue }
            if let direct = entries(nested) { return direct }
            if let inner = nested.objectValue, let found = named(inner) { return found }
        }
        // Last resort: the envelope itself becomes the single row, minus the two status keys, so a
        // shape nobody anticipated is still readable instead of silently empty.
        var visible = record
        visible.removeValue(forKey: "ret")
        visible.removeValue(forKey: "msg")
        return visible.keys.isEmpty ? [] : [.object(visible)]
    }

    /// `typeof raw === "number" ? raw : Number(raw)`. `asNumber` cannot stand in here: it collapses
    /// an unparsable string to 0, and a `total: "abc"` that reads as 0 would switch the pager into
    /// counted mode and hide 下一页. Absent answers NaN, null answers 0 — both are `Number`'s.
    ///
    /// The editor needs the same reading for `Number(value.ListenPort)` and
    /// `Number(value.TLSMinVersion)`, where `|| 0` would let an absent version pass a 0…3 check.
    static func jsNumber(_ raw: JSONValue?) -> Double {
        switch raw {
        case .none: return .nan
        case .null: return 0
        case .bool(let flag): return flag ? 1 : 0
        case .number(let number): return number
        case .string(let text): return JSCompat.number(text)
        // `Number([x])` goes through `String([x])`, so a one-element array converts while a
        // longer one becomes NaN by way of the comma.
        case .array(let list):
            return JSCompat.number(list.map(\.asDisplayString).joined(separator: ","))
        default: return .nan
        }
    }

    /// `webLogTotal(value)` — the count a pager needs, when the module volunteers one. Scanning
    /// continues past a negative or non-numeric key rather than giving up on the source.
    static func logTotal(_ value: JSONValue?) -> Int? {
        guard let value else { return nil }
        for source in [value, value["data"] ?? .null, value["result"] ?? .null] {
            guard let record = source.objectValue else { continue }
            for key in ["total", "Total", "totalCount", "TotalCount", "count", "Count"] {
                let count = jsNumber(record[key])
                guard count.isFinite, count >= 0 else { continue }
                return Int(count.rounded(.towardZero))
            }
        }
        return nil
    }

    /// `webServiceClientKey(value)` — the handle 断开客户端 posts. A row that names no connection is
    /// only allowed to fall back to its plain `Key` when it looks like a client at all, which keeps
    /// the chip off a WAF log line that happens to carry a key.
    static func clientKey(_ value: JSONValue?) -> String {
        guard let record = value?.objectValue else { return "" }
        let explicit = pick(value, ["ClientKey", "clientKey", "ConnectionKey", "connectionKey",
                                    "ConnKey", "connKey"])
        if !explicit.isEmpty { return explicit }
        let names = ["ClientIP", "clientIP", "RemoteAddr", "remoteAddr", "RemoteIP", "remoteIP"]
        // `value[key] !== undefined` — an explicit null counts as present.
        let looksLikeClient = names.contains { record.has($0) }
        return looksLikeClient ? pick(value, ["Key", "key"]) : ""
    }
}

// MARK: - 复制网址

/// The address a front-end domain resolves to, taken apart the way `new URL` takes it apart.
private struct WebAuthority {
    var userInfo = ""
    var hostname = ""
    /// The port exactly as written, leading zeros included — `new URL` keeps them only when the
    /// number equals the scheme's default, and step 10 of the original re-inserts that text.
    var portText: String?
    var portNumber: Int?
    var tail = ""
}

extension WebRecord {
    /// `buildSubRuleUrl(rule, subRule)` — the address 复制网址 puts on the pasteboard.
    ///
    /// The original leans on `new URL` for parsing and normalisation. There is no equivalent here
    /// that both validates and rebuilds the same way, so the four things `toString()` does to an
    /// authority are reproduced by hand: the host is lowercased, a port equal to the scheme's
    /// default is dropped (and then re-inserted verbatim by step 10), an empty path becomes `/`,
    /// and anything unparsable throws. Two of its refinements are *not* reproduced — an IDN host is
    /// left as typed instead of punycoded, and the path keeps its spacing instead of being
    /// percent-encoded — neither of which a Lucky 前端地址 carries.
    static func subRuleUrl(_ rule: JSONValue?, _ subRule: JSONValue?) throws -> String {
        guard let domain = lines(subRule?["Domains"]).first else { return "" }
        let scheme = bool(rule?["EnableTLS"]) ? "https" : "http"
        let authority = try WebAuthority(address: strippedAddress(domain))
        let defaultPort = scheme == "https" ? 443 : 80
        var port = ""
        if let text = authority.portText, let number = authority.portNumber {
            port = number == defaultPort ? ":\(text)" : ":\(number)"
        } else if let listen = listenPort(rule?["ListenPort"]), listen != defaultPort {
            port = ":\(listen)"
        }
        var path = authority.tail
        if path.isEmpty || !path.hasPrefix("/") { path = "/" + path }
        return "\(scheme)://\(authority.userInfo)\(authority.hostname.lowercased())\(port)\(path)"
    }

    /// Steps 3 and 4: a scheme other than http(s) is refused outright, a matching one is dropped
    /// because the rule's own TLS flag decides the scheme, and a protocol-relative `//host` loses
    /// its slashes. What is left may not be empty or begin a path, query or fragment.
    private static func strippedAddress(_ domain: String) throws -> String {
        var address = domain
        var matched = false
        if let mark = domain.range(of: "://") {
            let name = String(domain[..<mark.lowerBound])
            if isSchemeName(name) {
                guard ["http", "https"].contains(name.lowercased()) else { throw badAddress }
                address = String(domain[mark.upperBound...])
                matched = true
            }
        }
        if !matched, address.hasPrefix("//") { address = String(address.dropFirst(2)) }
        guard let first = address.first, !"/?#".contains(first) else { throw badAddress }
        return address
    }

    /// `^[a-z][a-z\d+.-]*$` — the scheme grammar the original's match anchors on. A prefix that
    /// fails it means the `://` belongs to something else, so no scheme was written at all.
    private static func isSchemeName(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter, first.isASCII else { return false }
        return name.dropFirst().allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0))
        }
    }

    /// `Number.isInteger(Number(rule.ListenPort)) && > 0 && <= 65535`.
    private static func listenPort(_ value: JSONValue?) -> Int? {
        let number = jsNumber(value)
        guard number.isFinite, number == number.rounded(.towardZero) else { return nil }
        guard number > 0, number <= 65535 else { return nil }
        return Int(number)
    }

    static var badAddress: LuckyError { LuckyError("前端地址格式不正确") }
}

extension WebAuthority {
    /// The characters `new URL` refuses inside a host. It rejects a good deal more than this, but
    /// everything else it rejects cannot survive `cleanLines`'s trim in the first place.
    private static let forbidden = Set(" \t\"<>\\^`|{}")

    /// Splits `host[:port][/path][?query][#hash]` and refuses what `new URL` would refuse: an empty
    /// hostname, a port that is not a plain number below 65536, an unclosed IPv6 bracket, and any
    /// host carrying a character that cannot appear in one.
    init(address: String) throws {
        self.init()
        let end = address.firstIndex { "/?#".contains($0) }
        let authority = end.map { String(address[..<$0]) } ?? address
        tail = end.map { String(address[$0...]) } ?? ""
        var host = authority
        if let at = authority.lastIndex(of: "@") {
            userInfo = String(authority[...at])
            host = String(authority[authority.index(after: at)...])
        }
        if host.hasPrefix("[") {
            guard let close = host.firstIndex(of: "]") else { throw WebRecord.badAddress }
            hostname = String(host[...close])
            let rest = String(host[host.index(after: close)...])
            if !rest.isEmpty { try readPort(rest) }
        } else if let colon = host.lastIndex(of: ":") {
            hostname = String(host[..<colon])
            try readPort(String(host[colon...]))
        } else {
            hostname = host
        }
        guard !hostname.isEmpty, !hostname.contains(where: Self.forbidden.contains) else {
            throw WebRecord.badAddress
        }
    }

    /// `^:(\d+)$` — and, beyond the original's regex, the range check `new URL` applies before it.
    /// A bare `host:` is a hostname with no port, which is what the regex's failure amounts to once
    /// `new URL` has already accepted the address.
    private mutating func readPort(_ text: String) throws {
        guard text.hasPrefix(":") else { throw WebRecord.badAddress }
        let digits = String(text.dropFirst())
        if digits.isEmpty { return }
        guard JSRegex.isDigitsOnly(digits), let number = Int(digits), number <= 65535 else {
            throw WebRecord.badAddress
        }
        portText = digits
        portNumber = number
    }
}

// MARK: - 代理规则的迁移

extension WebRecord {
    /// The six keys `normalizeWebProxy` deletes — five superseded spellings and the per-rule
    /// `DiaglogShowMode`, which belongs to the rule and not to a proxy inside it.
    private static let retired = ["DiaglogShowMode", "CorazaWAFKey", "AutoRedirect",
                                  "BasicAuthUser", "BasicAuthPasswd", "EnableWebAuth"]

    /// `normalizeWebProxy(value, defaults)` — folds an older rule into the shape the editor writes.
    ///
    /// Every one of these steps is a migration: Lucky renamed `CorazaWAFKey`, split
    /// `BasicAuthUser`/`BasicAuthPasswd` into one `user:pass` list, renamed `AutoRedirect` and
    /// `EnableWebAuth`, mis-cased `fileServer` for a while, and used to write `"default"` where the
    /// group key is now empty. A rule saved by an older Lucky must edit as though it were new, so
    /// the old key is read, folded in, and dropped — `delete` and not `= null`, since a null would
    /// travel back to the module as a real value.
    static func normalizeProxy(_ value: JSONValue?, _ defaults: JSONObject) -> JSONObject {
        let source = value?.record ?? JSONObject()
        var next = defaults.merging(source)
        if let type = first(source["WebServiceType"], defaults["WebServiceType"]) {
            next["WebServiceType"] = type.stringValue == "fileserver" ? .string("fileServer") : type
        }
        let group = source["GroupKey"]
        if group?.stringValue == "default" {
            next["GroupKey"] = .string("")
        } else {
            next["GroupKey"] = first(group, defaults["GroupKey"]) ?? .string("")
        }
        next["CorazaWAFInstance"] = .string(truthy(source["CorazaWAFInstance"],
                                                   source["CorazaWAFKey"],
                                                   defaults["CorazaWAFInstance"]))
        next["AutoProxyLocation"] = .bool(bool(source["AutoProxyLocation"])
            || bool(source["AutoRedirect"]) || bool(defaults["AutoProxyLocation"]))
        next["BasicAuthUserList"] = .string(basicAuth(source, defaults))
        next["OtherParams"] = .object(otherParams(source, defaults))
        for key in retired { next.removeValue(forKey: key) }
        return next
    }

    /// `a ?? b` over a pair of possibly-null keys.
    private static func first(_ candidates: JSONValue?...) -> JSONValue? {
        candidates.first { $0 != nil && $0?.isNull == false } ?? nil
    }

    /// `String(a || b || c || "")` — `||` walks past an empty string as well as an absent key.
    private static func truthy(_ candidates: JSONValue?...) -> String {
        for value in candidates where value?.isTruthy == true {
            return value?.asDisplayString ?? ""
        }
        return ""
    }

    /// `(currentBasicAuth || legacyBasicAuth) ?? defaults.BasicAuthUserList ?? ""`.
    ///
    /// The trim is not just a test — the trimmed text is stored. The legacy pair joins on a
    /// colon whenever *either* half is truthy, so a rule that only ever carried a password migrates
    /// to `:secret` instead of losing it.
    private static func basicAuth(_ source: JSONObject, _ defaults: JSONObject) -> String {
        let current = (source["BasicAuthUserList"]?.asDisplayString ?? "").jsTrimmed
        if !current.isEmpty { return current }
        let user = source["BasicAuthUser"]
        let password = source["BasicAuthPasswd"]
        if user?.isTruthy == true || password?.isTruthy == true {
            return "\(user?.asDisplayString ?? ""):\(password?.asDisplayString ?? "")"
        }
        return defaults["BasicAuthUserList"]?.asDisplayString ?? ""
    }

    /// `{ ...defaultOtherParams, ...sourceOtherParams, WebAuth }` — the nested record is merged the
    /// same way the proxy is, and the rule's own `EnableWebAuth` folds into it.
    private static func otherParams(_ source: JSONObject, _ defaults: JSONObject) -> JSONObject {
        let inner = source["OtherParams"]?.record ?? JSONObject()
        var merged = (defaults["OtherParams"]?.record ?? JSONObject()).merging(inner)
        merged["WebAuth"] = .bool(bool(inner["WebAuth"]) || bool(source["EnableWebAuth"])
            || bool(defaults["OtherParams"]?["WebAuth"]))
        return merged
    }
}
