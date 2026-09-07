import SwiftUI

// MARK: - 安全设置

/// §21.4 `SecurityFields` — the authentication block a rule's default proxy, every sub-rule and a
/// stand-alone sub-rule all share.
///
/// Three of the four rows write to the record itself; 网页认证 writes into `OtherParams`, which is a
/// nested object rebuilt on every keystroke — `{...otherParams, [field]: next}`.
struct WebSecurityFields: View {
    var data: JSONObject
    var scope: String
    var showIpFilter: Bool = true
    var context: WebEditorContext
    @Binding var openSelect: String
    var write: (String, JSONValue) -> Void

    /// `object(data.OtherParams)` — anything that is not an object reads as an empty one.
    private var otherParams: JSONObject { data["OtherParams"]?.record ?? JSONObject() }

    private var useGlobalAuth: Bool { WebRecord.bool(data["UseRuleGlobalAuthSettings"]) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WebToggle(label: "使用规则全局认证设置", field: "UseRuleGlobalAuthSettings",
                      data: data, write: write)
            // Global settings own the credentials, so the rule's own three rows go away entirely
            // rather than being disabled — the record keeps whatever they held.
            if !useGlobalAuth {
                WebToggle(label: "Basic 认证", field: "EnableBasicAuth", data: data, write: write)
                if WebRecord.bool(data["EnableBasicAuth"]) {
                    WebField(label: "Basic 认证用户", field: "BasicAuthUserList", data: data,
                             hint: "每行填写一组 用户名:密码", multiline: true, write: write)
                }
                WebToggle(label: "网页认证", field: "WebAuth", data: otherParams,
                          write: updateOtherParam)
            }
            if showIpFilter {
                WebSelect(label: "IP 过滤规则", field: "SafeIPMode", options: context.filterOptions,
                          data: data, scope: scope, openSelect: $openSelect, write: write)
            }
        }
    }

    private func updateOtherParam(_ field: String, _ next: JSONValue) {
        var params = otherParams
        params[field] = next
        write("OtherParams", .object(params))
    }
}

// MARK: - 子规则字段

/// §21.3 `SubRuleFields` — everything a proxy entry carries, in source order.
///
/// `ruleMode` and `tlsEnabled` come from the rule above: the first gates 不同 Host 也自动改写重定向
/// to 定制模式, and the second decides whether a TLS-only service type may be chosen at all.
struct WebSubRuleFields: View {
    var data: JSONObject
    var scope: String
    var ruleMode: String
    var tlsEnabled: Bool
    var context: WebEditorContext
    @Binding var openSelect: String
    var write: (String, JSONValue) -> Void

    private var serviceTypes: [WebOption] {
        WebEditorContext.serviceTypes(tlsEnabled: tlsEnabled, current: data["WebServiceType"])
    }

    /// `data.WebServiceType === "reverseproxy"` — strict, so only the literal string counts.
    private var reverseProxy: Bool { data["WebServiceType"]?.stringValue == "reverseproxy" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            identity
            switches
        }
    }
}

extension WebSubRuleFields {
    @ViewBuilder
    private var identity: some View {
        WebField(label: "子规则名称", field: "Remark", data: data, placeholder: "可留空", write: write)
        WebToggle(label: "子规则开关", field: "Enable", data: data, write: write)
        WebSelect(label: "分组", field: "GroupKey", options: context.groupOptions, data: data,
                  scope: scope, openSelect: $openSelect, write: write)
        WebSelect(label: "服务类型", field: "WebServiceType", options: serviceTypes, data: data,
                  scope: scope, openSelect: $openSelect, write: write)
        WebField(label: "前端地址", field: "Domains", data: data,
                 hint: "每行填写一个域名或访问地址", multiline: true, write: write)
        WebField(label: reverseProxy ? "后端地址" : "目标地址", field: "Locations", data: data,
                 hint: "每行填写一个地址", multiline: true, write: write)
        WebSelect(label: "CorazaWAF", field: "CorazaWAFInstance", options: context.subWafOptions,
                  data: data, scope: scope, openSelect: $openSelect, write: write)
    }

    @ViewBuilder
    private var switches: some View {
        WebToggle(label: "万事大吉", field: "EasyLucky", data: data, write: write)
        WebToggle(label: "忽略后端 TLS 证书验证", field: "LocationInsecureSkipVerify", data: data,
                  write: write)
        WebToggle(label: "使用目标地址 Host 请求头", field: "UseTargetHost", data: data, write: write)
        WebToggle(label: "自动反代重定向", field: "AutoProxyLocation", data: data, write: write)
        // A rewrite that also crosses hosts is a 定制模式 concern, and only means anything while
        // the rewrite above it is on.
        if ruleMode == "diy", WebRecord.bool(data["AutoProxyLocation"]) {
            WebToggle(label: "不同 Host 也自动改写重定向", field: "AutoProxyLocationWithoutSameHost",
                      data: data, write: write)
        }
        WebToggle(label: "记录访问日志", field: "EnableAccessLog", data: data, write: write)
    }
}
