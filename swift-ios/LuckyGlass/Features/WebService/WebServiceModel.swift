import Foundation

/// `ViewKey` — the six panes of the screen's `ResponsiveTabBar`.
///
/// Named `WebPane` rather than `WebView`: iOS 26 ships a SwiftUI `WebView`, and a same-file type
/// with that name would shadow it for anyone who later imports WebKit here.
enum WebPane: String, Hashable, CaseIterable, Identifiable {
    case rules, groups, cgi, settings, logs, tools

    var id: String { rawValue }

    /// The tab labels, verbatim.
    var label: String {
        switch self {
        case .rules: "规则"
        case .groups: "分组"
        case .cgi: "CGI"
        case .settings: "设置"
        case .logs: "日志"
        case .tools: "工具"
        }
    }

    /// `Route`, `FolderTree`, `Workflow`, `Settings2`, `ScrollText`, `Wrench`.
    var symbol: String {
        switch self {
        case .rules: "point.topleft.down.to.point.bottomright.curvepath"
        case .groups: "folder"
        case .cgi: "flowchart"
        case .settings: "gearshape.2"
        case .logs: LuckySymbol.logs
        case .tools: "wrench.and.screwdriver"
        }
    }

    /// `SectionHeader`'s title for the pane.
    var title: String {
        switch self {
        case .rules: "反向代理规则"
        case .groups: "子规则分组"
        case .cgi: "CGI 实例"
        case .settings: "模块设置"
        case .logs: "日志"
        case .tools: "辅助接口"
        }
    }
}

/// `SelectOption`.
struct WebOption: Identifiable, Hashable {
    var label: String
    var value: String

    var id: String { value }

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

// MARK: - 编辑器

/// `EditorType` — the six forms `WebServiceEditor` can put up.
enum WebEditorKind: String, Hashable {
    case rule, subrule, group, cgi, settings, template
}

/// `EditorState`.
///
/// `ruleMode` and `tlsEnabled` are read from the *parent* rule when a sub-rule is opened on its
/// own: the sub-rule endpoint answers the child only, so without them the form could not tell
/// whether to draw the DIY fields or the TLS-only service types.
struct WebEditorRequest: Identifiable, Hashable {
    var kind: WebEditorKind
    var title: String
    var value: JSONValue
    var key: String?
    var parentKey: String?
    var ruleMode: String?
    var tlsEnabled: Bool?

    /// `key={`${editor.type}-${editor.key ?? "new"}`}` — the identity that remounts the form.
    /// `.sheet(item:)` reads it for exactly the same purpose.
    var id: String { "\(kind.rawValue)-\(key ?? "new")" }

    init(_ kind: WebEditorKind, title: String, value: JSONValue, key: String? = nil,
         parentKey: String? = nil, ruleMode: String? = nil, tlsEnabled: Bool? = nil) {
        self.kind = kind
        self.title = title
        self.value = value
        self.key = key
        self.parentKey = parentKey
        self.ruleMode = ruleMode
        self.tlsEnabled = tlsEnabled
    }
}

// MARK: - 日志目标

/// `WebLogMode`.
enum WebLogMode: String, Hashable {
    /// `getWebServiceLogs(50, page)` and friends.
    case page
    /// `getWebServiceLastLogs()` — the tail, with no pager.
    case recent
}

/// `WebLogKind` — which of the seven log endpoints the pane is pointed at.
enum WebLogKind: String, Hashable {
    case module, subrule, access, coraza, http

    /// `Users` / `ShieldAlert` / `ScrollText`.
    var symbol: String {
        switch self {
        case .access: "person.2"
        case .coraza: "exclamationmark.shield"
        default: LuckySymbol.logs
        }
    }

    /// `supportsRecentLogs` — only these two kinds have a `lastlogs` endpoint, so only they
    /// get the 最近日志 toggle.
    var supportsRecent: Bool { self == .module || self == .subrule }
}

/// `WebLogTarget`.
struct WebLogTarget: Hashable {
    var kind: WebLogKind
    var title: String
    var ruleKey: String?
    var subKey: String?

    /// `defaultWebLogTarget`.
    static let module = WebLogTarget(.module, title: "Web 服务日志")

    init(_ kind: WebLogKind, title: String, ruleKey: String? = nil, subKey: String? = nil) {
        self.kind = kind
        self.title = title
        self.ruleKey = ruleKey
        self.subKey = subKey
    }
}

extension WebLogTarget {
    /// `WEB_LOG_PAGE_SIZE`. Every service function here defaults to 100, so all seven calls
    /// below name the size explicitly.
    static let pageSize = 50

    /// `getWebLogPage(target, page, mode, signal)` — the seven-way dispatch.
    func load(page: Int, mode: WebLogMode) async throws -> JSONValue {
        switch kind {
        case .module:
            if mode == .recent { return try await WebService.lastLogs() }
            return try await WebService.logs(pageSize: Self.pageSize, page: page)
        case .http:
            return try await WebService.httpLogs(ruleKey: rule(), pageSize: Self.pageSize,
                                                 page: page)
        case .subrule:
            let pair = try self.pair()
            if mode == .recent {
                return try await WebService.ruleLastLogs(ruleKey: pair.0, subKey: pair.1)
            }
            return try await WebService.ruleLogs(ruleKey: pair.0, subKey: pair.1,
                                                 pageSize: Self.pageSize, page: page)
        case .access:
            let pair = try self.pair()
            return try await WebService.accessDetails(ruleKey: pair.0, subKey: pair.1,
                                                      pageSize: Self.pageSize, page: page)
        case .coraza:
            let pair = try self.pair()
            return try await WebService.corazaLogs(ruleKey: pair.0, subKey: pair.1,
                                                   pageSize: Self.pageSize, page: page)
        }
    }

    /// The first guard. `!target.ruleKey` in the original, so an empty string fails it too.
    private func rule() throws -> String {
        guard let ruleKey, !ruleKey.isEmpty else { throw LuckyError("缺少 Web 服务规则标识") }
        return ruleKey
    }

    /// The second guard, which the three per-sub-rule kinds add on top of the first.
    private func pair() throws -> (String, String) {
        let ruleKey = try rule()
        guard let subKey, !subKey.isEmpty else { throw LuckyError("缺少 Web 服务子规则标识") }
        return (ruleKey, subKey)
    }
}

// MARK: - 浮层的目标

/// `WebServiceToolsTarget` — what 更多 opened the sheet on.
struct WebToolsTarget: Identifiable, Hashable {
    var ruleKey: String
    var ruleName: String
    var subKey: String?
    var subName: String?
    var fileService = false

    var id: String { "\(ruleKey)/\(subKey ?? "")" }

    /// Spelled out rather than left to the memberwise initializer, because a rule row opens the
    /// sheet with two arguments and a sub-rule row with five.
    init(ruleKey: String, ruleName: String, subKey: String? = nil, subName: String? = nil,
         fileService: Bool = false) {
        self.ruleKey = ruleKey
        self.ruleName = ruleName
        self.subKey = subKey
        self.subName = subName
        self.fileService = fileService
    }

    /// `target.subKey ? … : …` — an empty string is falsy, so it reads as no sub-rule at all.
    var hasSubRule: Bool { !(subKey ?? "").isEmpty }

    /// `subName || subKey || "子规则"`.
    var subTitle: String {
        if let subName, !subName.isEmpty { return subName }
        if let subKey, !subKey.isEmpty { return subKey }
        return "子规则"
    }
}

/// `groupOrderEditor` — the 排序 sheet's `{ key, name, keys }`.
struct WebOrderRequest: Identifiable, Hashable {
    var key: String
    var name: String
    var keys: [String]

    var id: String { key }
}

/// `folderTarget` — the 更新文件服务目录 sheet's `{ parentKey, subKey }`.
struct WebFolderRequest: Identifiable, Hashable {
    var parentKey: String
    var subKey: String

    var id: String { "\(parentKey)/\(subKey)" }
}

// MARK: - 动作

/// The query keys `invalidateWebService` names, as a value. `logs` is `["webservice","log-view"]`
/// and `groupOptions` is `["webservice","subrule-group-options"]` — the sub-rule editor's group
/// picker, which is the only one of the three option lists a mutation ever invalidates.
enum WebQuery: Hashable {
    case rules, groups, cgi, settings, tips, logs, groupOptions
}

/// The mutation input — one case per row of §10's table.
///
/// The original's `Action` is a discriminated union whose `mutationFn` ends in
/// `throw new Error("不支持的 Web 服务操作")`. An enum makes that arm unreachable, so it has no
/// counterpart here: every action the screen can build is one this file knows how to perform.
enum WebAction: Hashable {
    case save(WebEditorRequest, JSONObject)
    case deleteRule(String)
    case deleteGroup(String)
    case deleteCgi(String)
    case deleteSubRule(parentKey: String, key: String)
    case toggleRule(key: String, enabled: Bool)
    case toggleSubRule(parentKey: String, key: String, enabled: Bool)
    case toggleCgi(key: String, enabled: Bool)
    case reorderRules([String])
    case reorderGroups([String])
    case reorderGroupSubRules(ruleKey: String, keys: [String])
    case disconnectClient(ruleKey: String, clientKey: String)
    case flushCache(ruleKey: String, subKey: String)
    case markTip(String)
}

extension WebAction {
    /// `mutationFn`. Four of these are read-modify-writes: the sub-rule list lives inside its
    /// parent rule, so adding, replacing, removing or reordering one means GET the rule, edit
    /// `ProxyList` and PUT the whole thing back.
    func perform() async throws -> JSONValue {
        switch self {
        case .save(let editor, let value): return try await Self.save(editor, value)
        case .deleteRule(let key): return try await WebService.deleteRule(key)
        case .deleteGroup(let key): return try await WebService.deleteGroup(key)
        case .deleteCgi(let key): return try await WebService.deleteCgi(key)
        case .deleteSubRule(let parentKey, let key):
            return try await Self.withProxyList(parentKey) { items in
                items.enumerated()
                    .filter { WebRecord.key($0.element, $0.offset) != key }
                    .map(\.element)
            }
        case .toggleRule(let key, let enabled):
            var rule = try await WebService.rule(key).record
            rule["Enable"] = .bool(enabled)
            return try await WebService.updateRule(key: key, value: .object(rule))
        case .toggleSubRule(let parentKey, let key, let enabled):
            return try await WebService.setSubRuleEnabled(ruleKey: parentKey, subKey: key,
                                                          enabled: enabled)
        case .toggleCgi(let key, let enabled):
            return try await WebService.setCgiEnabled(key, enabled)
        case .reorderRules(let keys): return try await WebService.reorderRules(keys)
        case .reorderGroups(let keys): return try await WebService.reorderGroups(keys)
        case .reorderGroupSubRules(let ruleKey, let keys):
            return try await Self.withProxyList(ruleKey) { try Self.ordered($0, keys) }
        case .disconnectClient(let ruleKey, let clientKey):
            return try await WebService.disconnectClient(ruleKey: ruleKey, clientKey: clientKey)
        case .flushCache(let ruleKey, let subKey):
            return try await WebService.flushCache(ruleKey: ruleKey, subKey: subKey)
        case .markTip(let version): return try await WebService.markTipRead(version)
        }
    }
}

extension WebAction {
    /// GET the rule, hand its `ProxyList` to `edit`, PUT the whole rule back. A rule with no
    /// `ProxyList` yields an empty list and gains the key, which is what the assignment does in
    /// JavaScript too.
    private static func withProxyList(
        _ ruleKey: String,
        _ edit: ([JSONValue]) throws -> [JSONValue]
    ) async throws -> JSONValue {
        var rule = try await WebService.rule(ruleKey).record
        let items = WebRecord.array(.object(rule), ["ProxyList"])
        rule["ProxyList"] = .array(try edit(items))
        return try await WebService.updateRule(key: ruleKey, value: .object(rule))
    }

    /// The reorder walk. An unknown or repeated key is skipped rather than fatal, and a result
    /// that does not cover every existing sub-rule means the sheet was built from a stale list —
    /// saving it would silently drop rows, so it is refused instead.
    private static func ordered(_ items: [JSONValue], _ keys: [String]) throws -> [JSONValue] {
        guard !items.isEmpty else { throw LuckyError("当前规则没有可排序的子规则") }
        var byKey: [String: JSONValue] = [:]
        for (index, item) in items.enumerated() { byKey[WebRecord.key(item, index)] = item }
        var result: [JSONValue] = []
        var used = Set<String>()
        for key in keys {
            guard let item = byKey[key], !used.contains(key) else { continue }
            used.insert(key)
            result.append(item)
        }
        guard result.count == items.count else {
            throw LuckyError("排序列表已过期，请刷新规则后重试")
        }
        return result
    }

    /// The `save` arm. `source.key` is tested for truthiness throughout, so an empty string
    /// means "create" — which is exactly how 复制规则 reuses the edit form to POST a new rule.
    private static func save(_ editor: WebEditorRequest,
                             _ value: JSONObject) async throws -> JSONValue {
        let record = JSONValue.object(value)
        let key = editor.key ?? ""
        switch editor.kind {
        case .rule:
            if key.isEmpty { return try await WebService.createRule(record) }
            return try await WebService.updateRule(key: key, value: record)
        case .subrule:
            return try await withProxyList(editor.parentKey ?? "") { items in
                guard !key.isEmpty else { return items + [record] }
                let match = items.indices.first { WebRecord.key(items[$0], $0) == key }
                guard let index = match else { throw LuckyError("子规则不存在") }
                var next = items
                next[index] = record
                return next
            }
        case .group:
            // The create path posts only `Name`; the update path sends the whole group.
            if key.isEmpty { return try await WebService.createGroup(record) }
            return try await WebService.updateGroup(record)
        case .cgi:
            if key.isEmpty { return try await WebService.createCgi(record) }
            return try await WebService.updateCgi(key: key, value: record)
        case .settings:
            return try await WebService.updateSettings(record)
        case .template:
            return try await WebService.lightPanelConfigTemplate(record)
        }
    }
}

extension WebAction {
    /// `invalidateWebService(action)`, §10.1 verbatim.
    ///
    /// react-query refetches the panes that are on screen and marks the rest stale; the screen
    /// does the same by hand — it drops each of these from its loaded set and reloads whichever
    /// one is showing.
    var invalidates: [WebQuery] {
        switch self {
        case .save(let editor, _): return Self.saved(editor.kind)
        case .deleteRule, .deleteSubRule, .toggleRule, .toggleSubRule, .reorderRules:
            return [.rules, .groups]
        case .deleteGroup, .reorderGroups: return [.groups, .groupOptions]
        case .reorderGroupSubRules: return [.groups, .rules]
        case .deleteCgi, .toggleCgi: return [.cgi]
        case .markTip: return [.tips]
        case .disconnectClient: return [.logs]
        case .flushCache: return [.rules, .logs]
        }
    }

    private static func saved(_ kind: WebEditorKind) -> [WebQuery] {
        switch kind {
        case .rule, .subrule: [.rules, .groups]
        case .group: [.groups, .groupOptions]
        case .cgi: [.cgi]
        case .settings: [.settings]
        // A template request only ever produces output; nothing on the server changed.
        case .template: []
        }
    }
}
