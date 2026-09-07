import Foundation

/// `tunnelDefaults(type, mode?)` — the record a 新增 form starts from.
///
/// It is also read on a 类型 change, where only the `Params` half is used: switching an FRP
/// instance from 客户端 to 服务端 needs the server's keys to exist before the fields can edit them.
extension TunnelSpec {
    static func defaults(_ type: TunnelFormType, mode: String? = nil) -> JSONObject {
        switch type {
        case .stunSettings:
            return JSONObject([("EnableModule", true), ("GlobalStunServerList", .array([]))])
                .merging(webhookDefaults)
        case .stun: return stunDefaults
        case .cloudflared: return cloudflaredDefaults(mode)
        case .frp: return frpDefaults(mode)
        case .ingress: return ingressDefaults
        case .proxies: return proxyDefaults
        case .visitors: return visitorDefaults
        }
    }

    /// `webhookDefaults` — spread into the STUN rule and into 全局设置 alike, which is why the
    /// webhook fields are the only ones both forms share.
    static var webhookDefaults: JSONObject {
        var pairs: [(String, JSONValue)] = [
            ("WebhookEnable", false), ("WebhookOnlyAddrChange", true), ("WebhookURL", ""),
            ("WebhookMethod", "post"), ("WebhookHeaders", .array([])),
            ("WebhookRequestBody", ""),
        ]
        pairs += [
            ("WebhookDisableCallbackSuccessContentCheck", true),
            ("WebhookSuccessContent", .array([])), ("WebhookProxy", ""),
            ("WebhookProxyAddr", ""), ("WebhookProxyUser", ""), ("WebhookProxyPassword", ""),
        ]
        pairs += [("RetryCount", 0), ("RetryInterval", 500)]
        return JSONObject(pairs)
    }
}

// MARK: - STUN

extension TunnelSpec {
    /// The STUN rule. Grouped the way the original's lines are, because the key order is what the
    /// 其他参数 fold and the request body both inherit.
    private static var stunDefaults: JSONObject {
        var pairs: [(String, JSONValue)] = [
            ("Key", ""), ("Name", ""), ("Enable", true), ("StunType", "tcp4"),
            ("DiaglogShowMode", "simple"), ("StunListenType", "ip"),
        ]
        pairs += [
            ("ListenIP", ""), ("ListenPort", 0), ("SpecifyNetworkInterface", ""),
            ("NetworkInterfaceReg", ""),
        ]
        pairs += [
            ("UseGlobalStunServerList", true),
            ("StunServerList", .array([.string("stun.miwifi.com:3478")])),
            ("TcpKeepAliveServerList", .array([])),
        ]
        pairs += [
            ("DisablePortForward", false),
            ("TargetAddressList", .array([.string("127.0.0.1")])), ("TargetPort", 80),
        ]
        pairs += [
            ("AutoOptionsFirewall", true), ("NatPMP", false), ("NatPMPGateway", ""),
            ("UPnP", false), ("UPnPGawayIP", ""), ("UPnPLocalPort", 0),
            ("UPnpLocalHost", ""), ("UpnPDiyControlAPIUrl", ""),
        ]
        pairs += [
            ("StunHeartbeatInterval", 2300), ("StunTimeout", 3000),
            ("StunRetryInterval", 3000), ("StunAutoRetry", true),
            ("DisableStunAvalidCheck", false),
        ]
        pairs += [
            ("AutoAddPubAddrWhiteList", false), ("LogLevel", 4),
            ("LogOutputToConsole", false), ("AccessLogMaxNum", 128),
            ("WebListShowLastLogMaxCount", 20),
        ]
        pairs += [("GlobalWebhook", false), ("CallScript", false), ("CallScriptContent", "")]
        var value = JSONObject(pairs).merging(webhookDefaults)
        value["Options"] = .object(stunOptionDefaults)
        return value
    }

    /// The rule's `Options` sub-record — everything the 定制模式 table reaches through a dotted
    /// key, which is why those specs read `Options.SafeMode` and not `SafeMode`.
    private static var stunOptionDefaults: JSONObject {
        var pairs: [(String, JSONValue)] = [
            ("DisableSelfForwardingCheck", false), ("SingleProxyMaxTCPConnections", 256),
            ("SingleProxyMaxUDPReadTargetDatagoroutineCount", 32), ("UDPShortMode", false),
            ("SafeMode", "blacklist"),
        ]
        pairs += [
            ("TCPListenTLS", false), ("TCPRelayTLS", false), ("TCPRelayTLSServerName", ""),
            ("TCPRelayTLSInsecureSkipVerify", false), ("TCPStreamEncryptionSource", false),
            ("TCPStreamEncryptionAccept", false), ("TCPStreamEncryptionKey", ""),
        ]
        pairs += [
            ("SinglePortSpeedLimit", false), ("SinglePortSendSpeedLimit", 0),
            ("SinglePortReceSpeedLimit", 0), ("RuleSpeedLimit", false),
            ("RuleSendSpeedLimit", 0), ("RuleReceSpeedLimit", 0),
        ]
        pairs += [
            ("UDPSessionTimeout", 30000), ("UDPPacketSourceEncryption", false),
            ("UDPPacketAcceptEncryption", false), ("UDPPacketEncryptionKey", ""),
            ("UDPPacketSize", 1500),
        ]
        return JSONObject(pairs)
    }
}

// MARK: - Cloudflared

extension TunnelSpec {
    /// A Cloudflared instance. The two shapes share only `NoTlsVerify`: a Tunnel dials out with a
    /// token, an Access instance publishes a local port behind a service token.
    private static func cloudflaredDefaults(_ mode: String?) -> JSONObject {
        let params: JSONObject
        if mode == "access" {
            params = JSONObject([
                ("Hostname", ""), ("URL", ""), ("HeaderList", ""), ("Destination", ""),
                ("TokenId", ""), ("TokenSecret", ""), ("ConnectTo", ""), ("UserAgent", ""),
                ("NoTlsVerify", false),
            ])
        } else {
            var pairs: [(String, JSONValue)] = [
                ("Token", ""), ("EdgeIpVersion", "auto"), ("HaConnections", 4),
                ("Protocol", "http2"), ("EdgeBindAddress", ""), ("ICMPV4Src", ""),
                ("ICMPV6Src", ""), ("NoTlsVerify", false),
            ]
            pairs += [
                ("Network", "tcp4"), ("ListenIP", "127.0.0.1"), ("ListenPort", 60000),
                ("CFApiToken", ""), ("CFAccountId", ""), ("CFTunnelId", ""),
            ]
            params = JSONObject(pairs)
        }
        return JSONObject([
            ("Key", ""), ("Remark", ""), ("Enable", true),
            ("Type", .string(mode ?? "tunnel")), ("Params", .object(params)),
        ])
    }
}

// MARK: - FRP

extension TunnelSpec {
    /// An FRP instance. `Proxies` and `Visitors` are seeded empty and then deliberately stripped
    /// before a save — see `TunnelScreen.save`, where the module's runtime aliases must not
    /// overwrite the editable arrays.
    private static func frpDefaults(_ mode: String?) -> JSONObject {
        let params: JSONObject = mode == "server" ? frpServerParams : frpClientParams
        return JSONObject([
            ("Key", ""), ("Remark", ""), ("Enable", true),
            ("Type", .string(mode ?? "client")), ("Proxies", .array([])),
            ("Visitors", .array([])), ("Params", .object(params)),
        ])
    }

    private static var frpServerParams: JSONObject {
        var pairs: [(String, JSONValue)] = [
            ("BindAddr", "0.0.0.0"), ("BindPort", 7000), ("Token", ""), ("ProxyBindAddr", ""),
            ("KCPBindPort", 0), ("QUICBindPort", 0),
        ]
        pairs += [
            ("VhostHTTPPort", 0), ("VhostHTTPSPort", 0), ("VhostHTTPTimeout", 60),
            ("TCPMuxHTTPConnectPort", 0), ("TCPMuxPassthrough", false), ("TCPMux", true),
            ("TCPMuxKeepaliveInterval", 60), ("TCPKeepalive", 7200),
        ]
        pairs += [
            ("MaxPoolCount", 5), ("MaxPortsPerClient", 0), ("AllowPorts", ""),
            ("HeartbeatTimeout", 90), ("UserConnTimeout", 10), ("TLSOnly", false),
            ("UDPPacketSize", 1500), ("DetailedErrorsToClient", true),
        ]
        pairs += [("DashboardPort", 0), ("DashboardUser", "admin")]
        return JSONObject(pairs)
    }

    private static var frpClientParams: JSONObject {
        var pairs: [(String, JSONValue)] = [
            ("ServerAddr", ""), ("ServerPort", 7000), ("User", ""), ("AuthMethod", "token"),
            ("Token", ""), ("AuthAdditionalScopes", .array([])), ("Protocol", "tcp"),
            ("NatHoleStunServer", ""),
        ]
        pairs += [
            ("DialServerTimeout", 10), ("DialServerKeepalive", 7200),
            ("ConnectServerLocalIP", ""), ("ProxyURL", ""), ("PoolCount", 1),
            ("TCPMux", true), ("TCPMuxKeepaliveInterval", 60),
        ]
        pairs += [
            ("HeartbeatInterval", 30), ("HeartbeatTimeout", 90), ("TLSEnable", true),
            ("TLSServerName", ""), ("DisableCustomTLSFirstByte", true),
            ("TLSInsecureSkipVerify", false), ("UDPPacketSize", 1500), ("DNSServer", ""),
        ]
        pairs += [
            ("LoginFailExit", false), ("Start", .array([])),
            ("Metadatas", .object(JSONObject())), ("AdminPort", 0), ("AdminUser", "admin"),
        ]
        pairs += [
            ("OIDCClientID", ""), ("OIDCClientSecret", ""), ("OIDCAudience", ""),
            ("OIDCScope", ""), ("OIDCTokenEndpointURL", ""),
        ]
        return JSONObject(pairs)
    }
}

// MARK: - Child collections

/// The three child records keep their lowercase keys: unlike everything else in Lucky's API these
/// are fragments of cloudflared's and frp's own config files, and the daemons read them verbatim.
extension TunnelSpec {
    private static var ingressDefaults: JSONObject {
        let origin = JSONObject([
            ("noTLSVerify", false), ("originServerName", ""), ("httpHostHeader", ""),
            ("http2Origin", false),
        ])
        return JSONObject([
            ("hostname", ""), ("path", ""), ("service", "http://127.0.0.1:80"),
            ("originRequest", .object(origin)),
        ])
    }

    private static var proxyDefaults: JSONObject {
        var pairs: [(String, JSONValue)] = [
            ("name", ""), ("type", "tcp"), ("disabled", false), ("localIP", "127.0.0.1"),
            ("localPort", 80), ("remotePort", 8080),
        ]
        pairs += [
            ("useEncryption", false), ("useCompression", false),
            ("proxyProtocolVersion", ""), ("plugin", ""),
            ("natTraversal", .object(JSONObject([("disableAssistedAddrs", false)]))),
        ]
        return JSONObject(pairs)
    }

    private static var visitorDefaults: JSONObject {
        let transport = JSONObject([("useEncryption", false), ("useCompression", false)])
        var pairs: [(String, JSONValue)] = [
            ("name", ""), ("type", "stcp"), ("disabled", false), ("serverName", ""),
            ("secretKey", ""), ("bindAddr", "127.0.0.1"), ("bindPort", 8080),
            ("serverUser", ""),
        ]
        pairs += [
            ("transport", .object(transport)), ("protocol", "quic"),
            ("keepTunnelOpen", false), ("maxRetriesAnHour", 8), ("minRetryInterval", 90),
            ("fallbackTo", ""), ("fallbackTimeoutMs", 0),
        ]
        return JSONObject(pairs)
    }
}
