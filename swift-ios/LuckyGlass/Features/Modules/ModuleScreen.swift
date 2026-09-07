import SwiftUI

/// `app/modules/[module].tsx`.
struct ModuleScreen: View {
    var moduleKey: String

    @Environment(\.luckyNavigator) private var navigator
    @State private var search = ""

    private var module: LuckyModuleDefinition? {
        LuckyEndpointRegistry.modules.first { $0.key == moduleKey }
    }

    /// `` `${endpoint.path} ${endpoint.id} ${endpoint.source}` `` — the same haystack, so a search
    /// for `stunrule` still finds an endpoint whose path does not spell it.
    private var endpoints: [LuckyEndpointDefinition] {
        let keyword = search.jsTrimmed.lowercased()
        return LuckyEndpointRegistry.endpoints(module: moduleKey).filter { endpoint in
            guard !keyword.isEmpty else { return true }
            let haystack = "\(endpoint.path) \(endpoint.id) \(endpoint.source)"
            return haystack.lowercased().contains(keyword)
        }
    }

    var body: some View {
        if let module {
            list(module)
        } else {
            // `<Page title="模块不存在">` with an empty state rather than an error.
            LuckyPage {
                LuckyPageHero(title: "模块不存在")
                LuckyEmptyState(symbol: "curlybraces", title: "接口清单中没有找到该模块")
            }
        }
    }

    private func list(_ module: LuckyModuleDefinition) -> some View {
        LuckyPage {
            LuckyPageHero(
                title: module.label,
                subtitle: "\(module.endpointCount) 个端点 · \(module.methodCount) 个方法"
            )
            LuckySectionHeader(title: "接口列表", symbol: "magnifyingglass") {
                LuckyChip(text: "\(endpoints.count) 项", tone: .idle)
            }
            if endpoints.isEmpty {
                LuckyEmptyState(symbol: "magnifyingglass", title: "没有匹配的接口")
            } else {
                LuckyDataRail {
                    LazyVStack(spacing: 0) {
                        ForEach(endpoints) { endpoint in
                            Button {
                                navigator.push(.endpoint(endpoint.id))
                            } label: {
                                EndpointRow(endpoint: endpoint)
                                    .padding(.horizontal, LuckyTheme.Space.m)
                                    .padding(.vertical, LuckyTheme.Space.s)
                            }
                            .buttonStyle(.plain)
                            if endpoint.id != endpoints.last?.id { LuckyHairline() }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "搜索路径或接口")
        .searchToolbarBehavior(.minimize)
    }
}

/// `<EndpointRow>`: method badges and a chevron, the path in monospace over two lines, then the
/// source and whether a path parameter is required.
struct EndpointRow: View {
    var endpoint: LuckyEndpointDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            HStack(spacing: LuckyTheme.Space.s) {
                LuckyWrap(spacing: 5, lineSpacing: 5) {
                    ForEach(endpoint.methods) { method in
                        LuckyMethodBadge(method: method)
                    }
                }
                Spacer(minLength: LuckyTheme.Space.xs)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LuckyTheme.textTertiary)
            }
            Text(endpoint.path)
                .font(LuckyTheme.Text.code)
                .foregroundStyle(LuckyTheme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(caption)
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
    }

    /// `{endpoint.source || 'Lucky API'}{endpoint.requiresSuffix ? ' · 需要路径参数' : ''}`.
    private var caption: String {
        let source = endpoint.source.isEmpty ? "Lucky API" : endpoint.source
        return endpoint.requiresSuffix ? "\(source) · 需要路径参数" : source
    }
}
