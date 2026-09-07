import SwiftUI

/// §16 — 总览. The one Docker view that renders no list: `DockerOverviewDashboard` with all three of
/// its flags on, inside the scrollable page rather than a `FlatList`.
///
/// The dashboard needs a live status socket for its four resource cards, and the original lets it
/// open one of its own (`liveStatus` is *not* passed here, unlike on the 仪表盘 tab). The port has a
/// single reference-counted `LuckyStatusStore`, so the equivalent is to hold it for exactly as long
/// as this pane is on screen — `retain()` on entry, `release()` when `.task(id:)` tears it down.
struct DockerOverviewPane: View {
    var data: DockerOverview?
    /// `overviewActive` — focused, foregrounded and showing 总览. The socket and the resource cards
    /// are both gated on it.
    var active: Bool
    var stats: JSONValue?
    var statsLoading: Bool
    /// `"容器统计暂时不可用"`, or empty. The chrome prints the same sentence in a retryable card; this
    /// one is what the two ranking cards say in place of their rows.
    var statsError: String
    var refresh: @Sendable () async -> Void
    var selectView: (DockerOverviewTarget) -> Void
    var selectContainer: (String) -> Void

    private var live: LuckyStatusStore { .shared }

    var body: some View {
        DockerPaneScroll(refresh: refresh) {
            DockerOverviewDashboard(
                data: data,
                active: active,
                live: live,
                stats: stats,
                statsLoading: statsLoading,
                statsError: statsError,
                onSelectView: selectView,
                onSelectContainer: selectContainer
            )
        }
        .task(id: active) { await hold() }
    }

    /// The socket lives exactly as long as 总览 does. The sleep is only a parking spot; the `defer`
    /// is the whole point.
    private func hold() async {
        guard active else { return }
        live.retain()
        defer { live.release() }
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)) }
    }
}
