import SwiftUI

/// The port's entry point into the endpoint browser: every module in `LuckyEndpoints.json`, with
/// its endpoint and method counts. The original has no such screen — `/modules/[module]` is only
/// reachable by typing a URL — so this is built from the same registry the module screen reads.
struct ModuleIndexScreen: View {
    @Environment(\.luckyNavigator) private var navigator
    @State private var search = ""

    private var modules: [LuckyModuleDefinition] {
        let keyword = search.jsTrimmed.lowercased()
        guard !keyword.isEmpty else { return LuckyEndpointRegistry.modules }
        return LuckyEndpointRegistry.modules.filter {
            "\($0.label) \($0.key)".lowercased().contains(keyword)
        }
    }

    var body: some View {
        LuckyPage {
            LuckySectionHeader(title: "模块清单", subtitle: total, symbol: "square.grid.3x3") {
                LuckyChip(text: "\(modules.count) 项", tone: .idle)
            }
            if modules.isEmpty {
                LuckyEmptyState(symbol: "magnifyingglass", title: "没有匹配的模块")
            } else {
                LuckyDataRail {
                    LazyVStack(spacing: 0) {
                        ForEach(modules) { module in
                            Button {
                                navigator.push(.module(module.key))
                            } label: {
                                LuckyListRow(
                                    title: module.label,
                                    subtitle: module.key,
                                    symbol: LuckySymbol.module(module.key),
                                    chips: [
                                        LuckyChipSpec("\(module.endpointCount) 端点", tone: .brand),
                                        LuckyChipSpec("\(module.methodCount) 方法", tone: .info),
                                    ]
                                )
                            }
                            .buttonStyle(.plain)
                            if module.id != modules.last?.id { LuckyHairline() }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "搜索模块名称或 Key")
        .searchToolbarBehavior(.minimize)
    }

    private var total: String {
        let modules = LuckyEndpointRegistry.modules.count
        let endpoints = LuckyEndpointRegistry.endpoints.count
        return "\(modules) 个模块 · \(endpoints) 个端点"
    }
}
