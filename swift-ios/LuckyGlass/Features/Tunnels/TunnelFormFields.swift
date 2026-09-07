import Foundation

/// `fields(type, value, advanced)` — the field tables from `src/components/tunnel-form.tsx`.
///
/// Nothing here is a schema: each table is a hand-written list that reads the record it is about
/// to describe, so a switch the user just turned on changes which rows exist on the very next
/// render. That is why every table takes the current value rather than only the type.
extension TunnelSpec {
    static func fields(_ type: TunnelFormType, _ value: JSONObject,
                       advanced: Bool) -> [TunnelField] {
        switch type {
        case .stunSettings: return advanced ? [] : settingsFields(value)
        case .stun: return advanced ? stunAdvancedFields(value) : stunFields(value)
        case .cloudflared:
            return advanced ? cloudflaredAdvanced(value) : cloudflaredFields(value)
        case .frp: return advanced ? frpAdvanced(value) : frpFields(value)
        case .ingress: return advanced ? ingressAdvanced : ingressFields
        case .proxies: return advanced ? proxyAdvanced : proxyFields(value)
        case .visitors: return advanced ? visitorAdvanced : visitorFields
        }
    }

    /// `webhookFields(value)`.
    ///
    /// It collapses to the single switch while the webhook is off, so the dozen fields behind it
    /// never render for a rule that does not use one — and the validator, which walks the same
    /// list, never demands a URL that is not being asked for.
    static func webhookFields(_ value: JSONObject) -> [TunnelField] {
        let enable = TunnelField.spec("WebhookEnable", "启用 Webhook", .toggle)
        guard truthy(value, "WebhookEnable") else { return [enable] }
        var list: [TunnelField] = [
            enable,
            .spec("WebhookOnlyAddrChange", "仅地址变更时通知", .toggle),
            .spec("WebhookURL", "Webhook 地址", required: true),
            .spec("WebhookMethod", "请求方法",
                  options: ["get", "post", "put", "patch"], required: true),
            .spec("WebhookHeaders", "请求头", .lines),
        ]
        // A GET carries no body, so the field for one disappears rather than being ignored.
        if value["WebhookMethod"]?.stringValue != "get" {
            list.append(.spec("WebhookRequestBody", "请求内容", .multiline))
        }
        list.append(.spec("RetryCount", "重试次数", .number, min: 0, max: 10))
        if coerce(value["RetryCount"] ?? .null) > 0 {
            list.append(.spec("RetryInterval", "重试间隔（毫秒）", .number, min: 500, max: 10000))
        }
        list.append(.spec("WebhookDisableCallbackSuccessContentCheck",
                          "跳过响应内容检查", .toggle))
        if !truthy(value, "WebhookDisableCallbackSuccessContentCheck") {
            list.append(.spec("WebhookSuccessContent", "成功响应关键字", .lines, required: true))
        }
        list.append(.spec("WebhookProxy", "代理类型",
                          options: ["", "http", "https", "socks5", "dns"]))
        if truthy(value, "WebhookProxy") {
            list += [
                // A DNS proxy resolves through the system resolver, so it needs no address.
                .spec("WebhookProxyAddr", "代理地址",
                      required: value["WebhookProxy"]?.stringValue != "dns"),
                .spec("WebhookProxyUser", "代理账号"),
                .spec("WebhookProxyPassword", "代理密码", .secret),
            ]
        }
        return list
    }
}

// MARK: - STUN

extension TunnelSpec {
    /// 全局设置 has no advanced table — the module toggle, the shared server list and the webhook
    /// are all there is.
    private static func settingsFields(_ value: JSONObject) -> [TunnelField] {
        [
            .spec("EnableModule", "启用 STUN 模块", .toggle),
            .spec("GlobalStunServerList", "全局 STUN 服务器", .lines),
        ] + webhookFields(value)
    }

    /// The STUN rule's 简易模式 table. 仅获取公网地址 is the pivot: with it on the rule stops
    /// forwarding and the three target fields become meaningless, so they leave.
    private static func stunFields(_ value: JSONObject) -> [TunnelField] {
        var list: [TunnelField] = [
            .spec("Name", "规则名称", required: true),
            .spec("Enable", "启用规则", .toggle),
            .spec("DiaglogShowMode", "配置模式", options: ["simple", "diy"]),
            .spec("StunType", "穿透协议", options: ["tcp4", "udp4"]),
            .port("ListenPort", "监听端口（0 为自动）"),
            .spec("AutoOptionsFirewall", "自动配置防火墙", .toggle),
            .spec("UPnP", "UPnP", .toggle),
        ]
        if truthy(value, "UPnP") {
            list += [
                .spec("UPnPGawayIP", "UPnP 网关 IP"),
                .spec("UPnpLocalHost", "UPnP 客户端本地 IP"),
                .spec("UpnPDiyControlAPIUrl", "UPnP 控制接口地址"),
            ]
        }
        list.append(.spec("NatPMP", "NAT-PMP", .toggle))
        if truthy(value, "NatPMP") { list.append(.spec("NatPMPGateway", "NAT-PMP 网关")) }
        // Only a rule that maps a port without forwarding it has to say which port that is.
        if truthy(value, "UPnP") || truthy(value, "NatPMP"),
           truthy(value, "DisablePortForward") {
            list.append(.port("UPnPLocalPort", "映射的本地端口"))
        }
        list.append(.spec("DisablePortForward", "仅获取公网地址", .toggle))
        if !truthy(value, "DisablePortForward") {
            list += [
                .spec("DisableStunAvalidCheck", "跳过 STUN 有效性检查", .toggle),
                .spec("TargetAddressList", "目标地址", .lines, required: true),
                .port("TargetPort", "目标端口", true),
            ]
        }
        list.append(.spec("CallScript", "执行自定义脚本", .toggle))
        if truthy(value, "CallScript") {
            list.append(.spec("CallScriptContent", "脚本内容", .multiline, required: true))
        }
        list.append(.spec("GlobalWebhook", "使用全局 Webhook", .toggle))
        return list + webhookFields(value)
    }

    /// The 定制模式 table. It is not a 高级设置 fold: STUN shows it only when 配置模式 is 定制模式,
    /// and the validator honours the same condition, so a rule left in 简易模式 is never rejected
    /// for a field it cannot show.
    private static func stunAdvancedFields(_ value: JSONObject) -> [TunnelField] {
        let options = nested(value, "Options")
        var list: [TunnelField] = [
            .spec("Options.SafeMode", "IP 过滤模式",
                  options: ["blacklist", "globalblacklist", "whitelist"]),
        ]
        if options["SafeMode"]?.stringValue == "whitelist" {
            list.append(.spec("AutoAddPubAddrWhiteList", "公网地址自动加入白名单", .toggle))
        }
        list.append(.spec("StunListenType", "监听方式", options: ["ip", "networkInterface"]))
        if value["StunListenType"]?.stringValue == "ip" {
            list.append(.spec("ListenIP", "监听 IP（留空自动选择）"))
        } else {
            list += [
                .spec("SpecifyNetworkInterface", "网卡名称"),
                .spec("NetworkInterfaceReg", "地址匹配表达式"),
            ]
        }
        list.append(.spec("Options.DisableSelfForwardingCheck", "跳过自身转发检查", .toggle))
        // The transport tables are mutually exclusive and both vanish for a rule that only wants
        // its public address.
        let forwarding = !truthy(value, "DisablePortForward")
        let stunType = value["StunType"]?.stringValue
        if forwarding, stunType == "tcp4" { list += stunTcpFields(options) }
        if forwarding, stunType == "udp4" { list += stunUdpFields(options) }
        list.append(.spec("UseGlobalStunServerList", "使用全局 STUN 服务器", .toggle))
        if !truthy(value, "UseGlobalStunServerList") {
            list.append(.spec("StunServerList", "STUN 服务器", .lines, required: true))
        }
        // Keep-alive is a TCP notion; a UDP rule has no connection to keep open.
        if stunType == "tcp4" {
            list.append(.spec("TcpKeepAliveServerList", "TCP 保活服务器", .lines))
        }
        return list + stunTimingFields
    }

    private static var stunTimingFields: [TunnelField] {
        [
            .spec("StunTimeout", "STUN 超时（毫秒）", .number, min: 1000, max: 10000),
            .spec("StunHeartbeatInterval", "心跳检测间隔（毫秒）", .number,
                  min: 1000, max: 10000),
            .spec("StunRetryInterval", "穿透重试间隔（毫秒）", .number, min: 1000, max: 10000),
            .spec("StunAutoRetry", "穿透失败自动重试", .toggle),
            .spec("LogLevel", "日志级别", .number, min: 0, max: 6),
            .spec("LogOutputToConsole", "日志输出到终端", .toggle),
            .spec("AccessLogMaxNum", "最大访问日志数", .number, min: 0, max: 102400),
            .spec("WebListShowLastLogMaxCount", "页面显示最新日志数", .number, min: 1, max: 64),
        ]
    }

    /// The TCP transport rows — TLS on either leg, stream encryption, and the per-port and
    /// per-connection limits a stream can carry.
    private static func stunTcpFields(_ options: JSONObject) -> [TunnelField] {
        var list: [TunnelField] = [.spec("Options.SinglePortSpeedLimit", "单端口限速", .toggle)]
        if truthy(options, "SinglePortSpeedLimit") {
            list += [
                .spec("Options.SinglePortSendSpeedLimit", "单端口最大发送速度", .number,
                      min: 30, max: 1000000),
                .spec("Options.SinglePortReceSpeedLimit", "单端口最大接收速度", .number,
                      min: 30, max: 1000000),
            ]
        }
        list += [
            .spec("Options.SingleProxyMaxTCPConnections", "单端口最大 TCP 连接数", .number,
                  min: 1, max: 1024),
            .spec("Options.TCPListenTLS", "来源启用 TLS", .toggle),
            .spec("Options.TCPRelayTLS", "接收端启用 TLS", .toggle),
        ]
        if truthy(options, "TCPRelayTLS") {
            list += [
                .spec("Options.TCPRelayTLSInsecureSkipVerify", "跳过 TLS 证书校验", .toggle),
                .spec("Options.TCPRelayTLSServerName", "TLS 转发服务域名"),
            ]
        }
        list += [
            .spec("Options.TCPStreamEncryptionSource", "来源流加密", .toggle),
            .spec("Options.TCPStreamEncryptionAccept", "接收端流加密", .toggle),
        ]
        // One key serves both legs, so either switch is enough to demand it.
        if truthy(options, "TCPStreamEncryptionSource")
            || truthy(options, "TCPStreamEncryptionAccept") {
            list.append(.spec("Options.TCPStreamEncryptionKey", "流加密密钥", .secret,
                              required: true))
        }
        return list
    }

    /// The UDP transport rows. A datagram rule has sessions and packet sizes where a stream rule
    /// has connections and rate limits.
    private static func stunUdpFields(_ options: JSONObject) -> [TunnelField] {
        var list: [TunnelField] = [
            .spec("Options.UDPSessionTimeout", "UDP 会话超时（毫秒）", .number,
                  min: 30, max: 300000),
            .spec("Options.SingleProxyMaxUDPReadTargetDatagoroutineCount",
                  "单端口最大 UDP 会话数", .number, min: 0, max: 32),
            .spec("Options.UDPPacketSize", "UDP 数据包最大长度", .number, min: 1, max: 65507),
            .spec("Options.UDPShortMode", "UDP 短连接模式", .toggle),
            .spec("Options.UDPPacketSourceEncryption", "来源数据包加密", .toggle),
            .spec("Options.UDPPacketAcceptEncryption", "接收端数据包加密", .toggle),
        ]
        if truthy(options, "UDPPacketSourceEncryption")
            || truthy(options, "UDPPacketAcceptEncryption") {
            list.append(.spec("Options.UDPPacketEncryptionKey", "数据包加密密钥", .secret,
                              required: true))
        }
        return list
    }
}

// MARK: - Cloudflared

extension TunnelSpec {
    /// A Cloudflared instance. Tunnel dials Cloudflare's edge with a token; Access publishes a
    /// local listener behind a service token — so the two share only 跳过源站 TLS 校验.
    private static func cloudflaredFields(_ value: JSONObject) -> [TunnelField] {
        var list: [TunnelField] = [
            .spec("Remark", "实例名称", required: true),
            .spec("Enable", "启用实例", .toggle),
            .spec("Type", "实例类型", options: ["tunnel", "access"]),
        ]
        if value["Type"]?.stringValue == "access" {
            list += [
                .spec("Params.Hostname", "访问域名", required: true),
                .spec("Params.URL", "本地监听地址", required: true),
                .spec("Params.TokenId", "服务令牌 ID", .secret),
                .spec("Params.TokenSecret", "服务令牌密钥", .secret),
            ]
        } else {
            list += [
                .spec("Params.Token", "隧道 Token", .secret, required: true),
                .spec("Params.EdgeIpVersion", "边缘 IP 版本", options: ["auto", "4", "6"]),
                .spec("Params.Protocol", "连接协议", options: ["auto", "http2", "quic"]),
                .spec("Params.HaConnections", "连接数", .number, min: 1, max: 8),
            ]
        }
        list.append(.spec("Params.NoTlsVerify", "跳过源站 TLS 校验", .toggle))
        return list
    }

    private static func cloudflaredAdvanced(_ value: JSONObject) -> [TunnelField] {
        if value["Type"]?.stringValue == "access" {
            return [
                .spec("Params.HeaderList", "请求头", .multiline),
                .spec("Params.Destination", "目标地址"),
                .spec("Params.ConnectTo", "连接地址"),
                .spec("Params.UserAgent", "User Agent"),
            ]
        }
        return [
            .spec("Params.CFApiToken", "Cloudflare API Token", .secret),
            .spec("Params.CFAccountId", "账户 ID"),
            .spec("Params.CFTunnelId", "隧道 ID"),
            .spec("Params.EdgeBindAddress", "边缘绑定地址"),
            .spec("Params.ICMPV4Src", "ICMP IPv4 源地址"),
            .spec("Params.ICMPV6Src", "ICMP IPv6 源地址"),
        ]
    }
}

// MARK: - FRP

extension TunnelSpec {
    /// An FRP instance is either end of the same tunnel, so 实例类型 rewrites the whole `Params`
    /// half — see `TunnelSpec.update`, which re-seeds it rather than leaving stale keys behind.
    private static func frpFields(_ value: JSONObject) -> [TunnelField] {
        var list: [TunnelField] = [
            .spec("Remark", "实例名称", required: true),
            .spec("Enable", "启用实例", .toggle),
            .spec("Type", "实例类型", options: ["client", "server"]),
        ]
        if value["Type"]?.stringValue == "server" {
            list += [
                .spec("Params.BindAddr", "监听地址"),
                .port("Params.BindPort", "监听端口", true),
                .port("Params.VhostHTTPPort", "HTTP 虚拟主机端口"),
                .port("Params.VhostHTTPSPort", "HTTPS 虚拟主机端口"),
            ]
        } else {
            list += [
                .spec("Params.ServerAddr", "服务器地址", required: true),
                .port("Params.ServerPort", "服务器端口", true),
                .spec("Params.Protocol", "传输协议",
                      options: ["tcp", "kcp", "quic", "websocket", "wss"]),
                .spec("Params.AuthMethod", "认证方式", options: ["token", "oidc"]),
                .spec("Params.TLSEnable", "启用 TLS", .toggle),
            ]
        }
        list.append(.spec("Params.Token", "认证 Token", .secret))
        return list
    }

    private static func frpAdvanced(_ value: JSONObject) -> [TunnelField] {
        if value["Type"]?.stringValue == "server" { return frpServerAdvanced }
        var list: [TunnelField] = [
            .spec("Params.User", "用户标识"),
            .spec("Params.NatHoleStunServer", "NAT 穿透 STUN 服务器"),
            .spec("Params.ProxyURL", "连接代理 URL"),
            .spec("Params.DNSServer", "DNS 服务器"),
            .spec("Params.TLSServerName", "TLS 服务名"),
            .spec("Params.TLSInsecureSkipVerify", "跳过 TLS 证书校验", .toggle),
            // The only two fields in the port with a minimum and no maximum.
            .spec("Params.HeartbeatInterval", "心跳间隔（秒）", .number, min: 1),
            .spec("Params.HeartbeatTimeout", "心跳超时（秒）", .number, min: 1),
        ]
        list += [
            .spec("Params.OIDCClientID", "OIDC 客户端 ID"),
            .spec("Params.OIDCClientSecret", "OIDC 客户端密钥", .secret),
            .spec("Params.OIDCTokenEndpointURL", "OIDC 令牌地址"),
            .spec("Params.OIDCAudience", "OIDC Audience"),
            .spec("Params.OIDCScope", "OIDC Scope"),
        ]
        return list
    }

    /// 管理面板密码 has no default: the server only ever sends it back once, so an untouched field
    /// posts nothing and leaves whatever is stored alone.
    private static var frpServerAdvanced: [TunnelField] {
        [
            .port("Params.KCPBindPort", "KCP 监听端口"),
            .port("Params.QUICBindPort", "QUIC 监听端口"),
            .spec("Params.AllowPorts", "允许端口范围"),
            .port("Params.DashboardPort", "管理面板端口"),
            .spec("Params.DashboardUser", "管理面板账号"),
            .spec("Params.DashboardPassword", "管理面板密码", .secret),
            .spec("Params.TLSOnly", "强制 TLS", .toggle),
        ]
    }
}

// MARK: - Child collections

extension TunnelSpec {
    /// Cloudflared 域名路由. A rule with no hostname is the catch-all, which is why the field says
    /// so instead of being required.
    private static var ingressFields: [TunnelField] {
        [
            .spec("hostname", "域名（留空为兜底规则）"),
            .spec("path", "路径表达式"),
            .spec("service", "后端服务", required: true),
            .spec("originRequest.noTLSVerify", "跳过源站 TLS 校验", .toggle),
        ]
    }

    private static var ingressAdvanced: [TunnelField] {
        [
            .spec("originRequest.originServerName", "源站 TLS 服务名"),
            .spec("originRequest.httpHostHeader", "源站 Host"),
            .spec("originRequest.http2Origin", "源站 HTTP/2", .toggle),
            .spec("originRequest.connectTimeout", "连接超时（例如 30s）"),
        ]
    }

    /// FRP 代理规则. The proxy's own type decides how it is published: a raw port gets 远端端口,
    /// an HTTP proxy gets domains, and the secret types get a key instead of either.
    private static func proxyFields(_ value: JSONObject) -> [TunnelField] {
        // `String(value.type ?? 'tcp')` — a record that lost its type still offers the TCP rows.
        var proxyType = "tcp"
        if let stored = value["type"], !stored.isNull { proxyType = stringify(stored) }
        var list: [TunnelField] = [
            .spec("name", "代理名称", required: true),
            .spec("type", "代理类型",
                  options: ["tcp", "udp", "http", "https", "stcp", "xtcp", "sudp", "tcpmux"]),
            .spec("disabled", "停用代理", .toggle),
            .spec("localIP", "本地地址"),
            .port("localPort", "本地端口", true),
        ]
        if ["tcp", "udp"].contains(proxyType) {
            list.append(.port("remotePort", "远端端口", true))
        }
        if ["http", "https", "tcpmux"].contains(proxyType) {
            list += [.spec("customDomains", "自定义域名", .lines), .spec("subdomain", "子域名")]
        }
        if ["stcp", "xtcp", "sudp"].contains(proxyType) {
            list.append(.spec("secretKey", "访问密钥", .secret, required: true))
        }
        return list
    }

    private static var proxyAdvanced: [TunnelField] {
        [
            .spec("useEncryption", "加密", .toggle),
            .spec("useCompression", "压缩", .toggle),
            .spec("proxyProtocolVersion", "Proxy Protocol", options: ["", "v1", "v2"]),
            .spec("bandwidthLimit", "带宽限制（例如 1MB）"),
            .spec("plugin", "插件", options: pluginOptions),
        ]
    }

    private static var pluginOptions: [String] {
        ["", "http_proxy", "socks5", "static_file", "unix_domain_socket", "http2https",
         "https2http", "https2https", "tls2raw"]
    }

    /// FRP 访问者 — the local end of an `stcp` / `xtcp` / `sudp` proxy, which is why both the
    /// server-side name and the shared key are required.
    private static var visitorFields: [TunnelField] {
        [
            .spec("name", "访问者名称", required: true),
            .spec("type", "访问类型", options: ["stcp", "xtcp", "sudp"]),
            .spec("disabled", "停用访问者", .toggle),
            .spec("serverName", "服务端代理名称", required: true),
            .spec("secretKey", "访问密钥", .secret, required: true),
            .spec("bindAddr", "本地监听地址"),
            .port("bindPort", "本地监听端口", true),
        ]
    }

    private static var visitorAdvanced: [TunnelField] {
        [
            .spec("transport.useEncryption", "加密", .toggle),
            .spec("transport.useCompression", "压缩", .toggle),
            .spec("keepTunnelOpen", "保持隧道连接", .toggle),
            .spec("serverUser", "服务端用户"),
            .spec("protocol", "穿透协议", options: ["quic", "kcp"]),
        ]
    }
}
