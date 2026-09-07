import SwiftUI

/// `app/(tabs)/_layout.tsx`.
///
/// The original renders `<NativeTabs minimizeBehavior="onScrollDown" blurEffect="systemDefault">`
/// — which is the React Native wrapper around exactly the iOS 26 tab bar this uses directly. The
/// glass, the blur and the minimize-on-scroll all come from the system; nothing here paints a bar.
struct LuckyRoot: View {
    @State private var navigator = LuckyNavigator()
    @State private var session = LuckySession.shared

    var body: some View {
        TabView(selection: $navigator.selection) {
            ForEach(LuckyTab.allCases) { tab in
                Tab(tab.label, systemImage: symbol(tab), value: tab) {
                    stack(tab)
                }
            }
        }
        // `minimizeBehavior="onScrollDown"`.
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(\.luckyNavigator, navigator)
        .tint(LuckyTheme.accent)
    }

    /// `<Icon sf={{ default, selected }} />`: the filled glyph while the tab is current.
    private func symbol(_ tab: LuckyTab) -> String {
        navigator.selection == tab ? tab.selectedSymbol : tab.symbol
    }

    private func stack(_ tab: LuckyTab) -> some View {
        NavigationStack(path: navigator.binding(for: tab)) {
            root(tab)
                .navigationDestination(for: LuckyRoute.self) { route in
                    destination(route)
                        .navigationTitle(route.title)
                        .navigationBarTitleDisplayMode(.inline)
                        // The original pushes onto the root stack, above the tab bar, so a
                        // detail screen never shows one.
                        .toolbar(.hidden, for: .tabBar)
                }
        }
    }

    @ViewBuilder
    private func root(_ tab: LuckyTab) -> some View {
        switch tab {
        case .dashboard: DashboardScreen()
        case .services: ServicesScreen()
        case .logs: LogsScreen()
        case .settings: SettingsScreen()
        }
    }

    @ViewBuilder
    private func destination(_ route: LuckyRoute) -> some View {
        switch route {
        case .service(let kind): ServiceDetailScreen(kind: kind)
        case .webservice: WebServiceScreen()
        case .docker(let view, let search): DockerScreen(initialView: view, initialSearch: search)
        case .tunnel(let kind): TunnelScreen(kind: kind)
        case .module(let key): ModuleScreen(moduleKey: key)
        case .endpoint(let id): EndpointScreen(endpointID: id)
        case .moduleIndex: ModuleIndexScreen()
        }
    }
}
