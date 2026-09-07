import SwiftUI

/// The expo-router paths, as a value type.
///
/// `app/_layout.tsx` declares six pushed screens — `services/[kind]`, `modules/[module]`,
/// `endpoints/[id]`, `webservice`, `docker` and `tunnels/[kind]` — and the app navigates to
/// them with `router.push('/docker?view=containers&search=nginx')`. A `NavigationStack` path
/// carries values instead of strings, so the query parameters become associated values and the
/// `titles` below are the `options.title` of each `Stack.Screen`.
enum LuckyRoute: Hashable, Codable {
    /// `/services/[kind]` — the shared list/detail screen for ddns and ssl.
    case service(LuckyServiceKind)
    /// `/webservice` — lifted out of `services/[kind]` because reverse proxy has its own screen.
    case webservice
    /// `/docker?view=&search=` — `view` selects the segment, `search` seeds the filter.
    case docker(view: String = "", search: String = "")
    /// `/tunnels/[kind]`.
    case tunnel(TunnelKind)
    /// `/modules/[module]`.
    case module(String)
    /// `/endpoints/[id]`.
    case endpoint(String)
    /// The port's own entry point into the endpoint browser. `/modules/[module]` is an orphan
    /// route in the original: nothing links to it, and expo-router only reaches it by URL. A
    /// native app has no URL bar, so the module index gets a real screen.
    case moduleIndex

    /// `options.title` from `app/_layout.tsx`, verbatim — except for a tunnel, where the module's
    /// own name replaces the generic 内网穿透. The original prints both: the stack header carries
    /// the generic title and the screen draws a `PageHeader` with `tunnelTitles[kind]` under it.
    /// Here the navigation bar *is* that header, so it has to say which module this is.
    var title: String {
        switch self {
        case .service: "服务详情"
        case .webservice: "Web 服务"
        case .docker: "Docker"
        case .tunnel(let kind): kind.title
        case .module: "模块接口"
        case .endpoint: "接口调试"
        case .moduleIndex: "接口调试"
        }
    }
}

/// The four visible tabs of `app/(tabs)/_layout.tsx`. The `index` trigger is hidden there and
/// only exists to `<Redirect href="/monitor" />`, so it has no case here.
enum LuckyTab: String, Hashable, CaseIterable, Identifiable {
    case dashboard, services, logs, settings

    var id: String { rawValue }

    /// `<Label>` text, verbatim.
    var label: String {
        switch self {
        case .dashboard: "总览"
        case .services: "服务"
        case .logs: "日志"
        case .settings: "设置"
        }
    }

    /// `<Icon sf={{ default, selected }} />`. 总览 declares no selected variant.
    var symbol: String {
        switch self {
        case .dashboard: "gauge"
        case .services: "square.grid.2x2"
        case .logs: "doc.text"
        case .settings: "gearshape"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .dashboard: "gauge"
        case .services: "square.grid.2x2.fill"
        case .logs: "doc.text.fill"
        case .settings: "gearshape.fill"
        }
    }
}

/// Pushes a route from anywhere in the tree without threading a binding through every view —
/// the equivalent of importing `router` from `expo-router`.
///
/// The original pushes onto the *root* stack, which sits above the tab bar, so a push from 总览
/// and a push from 服务 share one history. Here each tab keeps its own stack (the arrangement
/// SwiftUI supports) and `push` targets whichever tab is showing, which produces the same
/// forward navigation while making Back per-tab.
@MainActor
@Observable
final class LuckyNavigator {
    var selection: LuckyTab = .dashboard
    private var paths: [LuckyTab: [LuckyRoute]] = [:]

    func push(_ route: LuckyRoute) {
        paths[selection, default: []].append(route)
    }

    /// Hand-built rather than `@Bindable` so `NavigationStack(path:)` can bind a tab that has no
    /// entry yet without inserting an empty array first.
    func binding(for tab: LuckyTab) -> Binding<[LuckyRoute]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    /// Switches tab and pops that tab to its root — `settings.tsx`'s post-logout reset.
    func reset(to tab: LuckyTab) {
        paths.removeAll()
        selection = tab
    }
}

extension EnvironmentValues {
    @Entry var luckyNavigator = LuckyNavigator()
}
