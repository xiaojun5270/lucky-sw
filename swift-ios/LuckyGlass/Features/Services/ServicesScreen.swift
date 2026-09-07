import SwiftUI

/// The service control plane. Services are presented as subsystem lanes rather than a launcher grid:
/// each row names a capability, its operating scope and the route into its existing workspace.
struct ServicesScreen: View {
    @Environment(\.luckyNavigator) private var navigator

    private let scene = LuckySceneDescriptor(
        module: .services,
        title: "服务控制面",
        subtitle: "选择一个子系统进入配置与运行视图",
        symbol: LuckySymbol.services,
        tone: .brand,
        health: .unknown
    )

    var body: some View {
        LuckyPage {
            LuckySceneStrip(scene)
            commonRail
            tunnelRail
            developerRail
        }
        .luckyTitle("服务", "子系统与工具")
        .luckyScene(scene)
    }

    private var commonRail: some View {
        LuckyDataRail(title: "常用服务", subtitle: "4 个子系统", tone: .brand) {
            VStack(spacing: 0) {
                ServiceLane(symbol: "globe.asia.australia", label: "反向代理",
                            detail: "域名、监听、后端与 TLS 规则", tone: .brand) {
                    navigator.push(.webservice)
                }
                LuckyHairline()
                ServiceLane(symbol: "arrow.triangle.2.circlepath", label: "动态域名",
                            detail: "DDNS 任务、地址记录与手动同步", tone: .info) {
                    navigator.push(.service(.ddns))
                }
                LuckyHairline()
                ServiceLane(symbol: "shippingbox", label: "Docker",
                            detail: "运行时、容器与镜像资源", tone: .warning) {
                    navigator.push(.docker())
                }
                LuckyHairline()
                ServiceLane(symbol: "checkmark.shield", label: "SSL 证书",
                            detail: "证书来源、签发状态与同步", tone: .ok) {
                    navigator.push(.service(.ssl))
                }
            }
        }
    }

    private var tunnelRail: some View {
        LuckyDataRail(title: "内网穿透", subtitle: "真实隧道与代理关系", tone: .info) {
            VStack(spacing: 0) {
                ForEach(TunnelKind.allCases) { kind in
                    ServiceLane(symbol: kind.symbol, label: kind.title, detail: kind.detail,
                                tone: kind.tone) {
                        navigator.push(.tunnel(kind))
                    }
                    if kind.id != TunnelKind.allCases.last?.id { LuckyHairline() }
                }
            }
        }
    }

    private var developerRail: some View {
        LuckyDataRail(title: "开发工具", subtitle: endpointDetail, tone: .brand) {
            ServiceLane(symbol: LuckySymbol.debugger, label: "接口调试",
                        detail: "浏览模块、构造请求并检查原始响应", tone: .brand) {
                navigator.push(.moduleIndex)
            }
        }
    }

    private var endpointDetail: String {
        let modules = LuckyEndpointRegistry.modules.count
        let endpoints = LuckyEndpointRegistry.endpoints.count
        return "\(modules) 个模块 · \(endpoints) 个端点"
    }
}

private struct ServiceLane: View {
    var symbol: String
    var label: String
    var detail: String
    var tone: LuckyTone
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            LuckyListRow(title: label, subtitle: detail, symbol: symbol, tone: tone)
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开\(label)工作区")
    }
}
