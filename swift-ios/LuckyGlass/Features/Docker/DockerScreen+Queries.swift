import SwiftUI

/// §2's fourteen queries, as `.task` loops.
///
/// react-query's `enabled` flag becomes the `.task(id:)` that owns the loop: cancelling the task
/// cancels the request and the sleep with it, which is what `enabled: false` does to a mounted
/// query. `staleTime` has no counterpart — re-entering a view always refetches, which is a visible
/// divergence on a fast tab bounce and a harmless one.
extension DockerScreen {
    /// `active.refetch()` on entry. Three views are missing from this switch on purpose: 总览 and
    /// 日志 are refetched on an interval and own `fetching` from inside their own loops, and the two
    /// statistics sweeps are not tied to a view at all.
    func loadView() async {
        switch view {
        case .overview, .logs: return
        case .containers: await loadContainers()
        case .settings: await loadSettings()
        default: await loadList(view)
        }
    }

    /// The five plain list views.
    ///
    /// There is deliberately no `guard !fetching` prologue: `.task(id: view)` starts the next
    /// view's load before the cancelled one has returned, and a guard would drop it. The flag is
    /// instead cleared only by the load still standing on the view it started on.
    private func loadList(_ target: DockerView) async {
        let key = DockerScreen.query(of: target)
        fetching = true
        defer { if view == target { fetching = false } }
        do {
            switch target {
            case .images: images = try await DockerService.images().items
            case .compose: projects = try await DockerService.composeProjects().items
            case .networks: networks = try await DockerService.networks().items
            case .volumes: volumes = try await DockerService.volumes().items
            case .tasks: tasks = try await DockerService.tasks().items
            default: return
            }
            queryFailures[key] = ""
            loaded.insert(key)
        } catch {
            // A cancelled read is a view switch, not a failure; react-query drops those too.
            guard !error.isCancellation else { return }
            queryFailures[key] = error.luckyMessage()
        }
    }

    /// `containers` and `iconLibrary` share an `enabled`, so they load together. The library's
    /// 30-minute `staleTime` becomes "read it once and keep it" — nothing in §26 invalidates it —
    /// and its failure is never surfaced, because a container without artwork simply draws a glyph.
    private func loadContainers() async {
        let wantsIcons = !loaded.contains(.iconLibrary)
        fetching = true
        defer { if view == .containers { fetching = false } }
        do {
            containers = try await DockerService.containers().items
            queryFailures[.containers] = ""
            loaded.insert(.containers)
        } catch {
            guard !error.isCancellation else { return }
            queryFailures[.containers] = error.luckyMessage()
        }
        guard wantsIcons, let library = try? await IconLibService.icons() else { return }
        icons = library
        loaded.insert(.iconLibrary)
    }

    /// 设置's three queries. They start together, as react-query mounts them together; the awaits
    /// are ordered because each writes its own slot. `config` is `active`, so it owns `fetching`
    /// and the header's error card; `maintenance` has its own spinner (§17.4's 正在刷新 meta) and
    /// its own card (§17.3); `mirrors` surfaces neither, so a failure leaves the last list showing.
    private func loadSettings() async {
        async let configRead = DockerService.config()
        async let mirrorRead = DockerService.registryMirrors()
        async let maintenanceRead = DockerService.maintenanceStatus()
        fetching = true
        maintenanceFetching = true
        do {
            config = try await configRead
            queryFailures[.config] = ""
            loaded.insert(.config)
        } catch {
            if !error.isCancellation { queryFailures[.config] = error.luckyMessage() }
        }
        if view == .settings { fetching = false }
        if let list = try? await mirrorRead {
            mirrors = list
            loaded.insert(.mirrors)
        }
        do {
            maintenance = try await maintenanceRead
            queryFailures[.maintenance] = ""
            loaded.insert(.maintenance)
        } catch {
            if !error.isCancellation { queryFailures[.maintenance] = error.luckyMessage() }
        }
        if view == .settings { maintenanceFetching = false }
    }
}

// MARK: - 轮询

extension DockerScreen {
    /// `overview`: `refetchInterval: 60_000`. The loop is the whole gate — `.task(id:)` cancels it,
    /// and the sleep with it, the moment the view changes or the app leaves the foreground.
    func pollOverview() async {
        guard overviewActive else { return }
        await loadOverview()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await loadOverview()
        }
    }

    private func loadOverview() async {
        fetching = true
        defer { if view == .overview { fetching = false } }
        do {
            overview = try await DockerService.overview()
            queryFailures[.overview] = ""
            loaded.insert(.overview)
        } catch {
            guard !error.isCancellation else { return }
            queryFailures[.overview] = error.luckyMessage()
        }
    }

    /// `logs`: `refetchInterval: 15000`, and unlike the tunnel and webservice logs every page polls
    /// — the query key carries `dockerLogPage`, so paging is a new query and not a new argument.
    func pollLogs() async {
        guard logsActive else { return }
        await loadLogs()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await loadLogs()
        }
    }

    private func loadLogs() async {
        fetching = true
        defer { if view == .logs { fetching = false } }
        do {
            logPayload = try await DockerService.logs(
                pageSize: DockerScreen.logPageSize, page: logPage
            )
            queryFailures[.logs] = ""
            loaded.insert(.logs)
        } catch {
            guard !error.isCancellation else { return }
            queryFailures[.logs] = error.luckyMessage()
        }
    }
}

// MARK: - 容器统计

extension DockerScreen {
    /// `containerStats`: `refetchInterval: 5_000`, `retry: false`. One bulk call covering every
    /// container, which is why it is the cheap one and why its failure is not shown on its own.
    func pollStats() async {
        guard statsActive else { return }
        await loadStats()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await loadStats()
        }
    }

    /// The three flags §2's gate reads. react-query's status is one of three values, so a refetch
    /// that fails after a success clears `isSuccess` — and that is what turns the live sweep on.
    private func loadStats() async {
        // `isLoading` is `isPending && isFetching`: fetching, nothing cached, and no error yet.
        statsLoading = stats == nil && !statsFailed
        defer { statsLoading = false }
        do {
            stats = try await DockerService.allContainerStats()
            statsSucceeded = true
            statsFailed = false
        } catch {
            guard !error.isCancellation else { return }
            statsSucceeded = false
            statsFailed = true
        }
    }

    /// `liveContainerStats`: `refetchInterval: 15_000`, `retry: false`. One call per container, run
    /// four at a time, which is why it only runs when the bulk sweep could not answer.
    func pollLiveStats() async {
        guard liveStatsNeeded else { return }
        await loadLiveStats()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await loadLiveStats()
        }
    }

    private func loadLiveStats() async {
        liveStatsLoading = liveStats == nil && liveStatsFailure.isEmpty
        defer { liveStatsLoading = false }
        // `setProgressiveContainerStats(undefined)` — the previous sweep's partials go before the
        // next one starts streaming, so the grid never mixes two rounds.
        progressiveStats = nil
        // 容器 hands the sweep the list it is already showing; 总览 passes nothing and lets
        // `refreshDockerContainerStats` fetch its own.
        let items = view == .containers ? containers : nil
        // `State` is `Sendable` and its setter is nonmutating, so the box can cross into the
        // progress callback where `self` could not.
        let sink = _progressiveStats
        do {
            liveStats = try await DockerService.refreshContainerStats(items: items) { partial in
                Task { @MainActor in sink.wrappedValue = partial }
            }
            liveStatsFailure = ""
        } catch {
            guard !error.isCancellation else { return }
            liveStatsFailure = error.luckyMessage()
        }
    }
}

// MARK: - 刷新与失效

extension DockerScreen {
    /// §6's `refreshDockerView` — the toolbar button and every pull-to-refresh. 总览 and 容器 also
    /// re-run the statistics sweeps, and 设置 re-runs the two queries that are not `active`.
    func refresh() async {
        await reloadActive()
        guard statsActive else { return }
        await refreshStats()
    }

    /// `active.refetch()` for all nine views. Unlike `loadView` this one does reload 总览 and 日志:
    /// their intervals belong to their loops, but a manual refresh and an invalidation both mean
    /// "read it again now".
    private func reloadActive() async {
        switch view {
        case .overview: await loadOverview()
        case .logs: await loadLogs()
        case .containers: await loadContainers()
        case .settings: await loadSettings()
        default: await loadList(view)
        }
    }

    /// `containerStats.refetch(); if (liveStatsNeeded) liveContainerStats.refetch();` — either one
    /// succeeding is enough to fill the grid, which is why the header's retry runs both.
    func refreshStats() async {
        await loadStats()
        guard liveStatsNeeded else { return }
        await loadLiveStats()
    }

    /// §26's cascade. react-query refetches the mounted queries and marks the rest stale; every
    /// view here reloads on entry anyway, so marking an off-screen one stale is a no-op and the
    /// sweep reduces to "reload whatever is showing". The view keeps its old rows while that runs,
    /// which is what makes this a refetch and not a reload.
    ///
    /// 设置 is the one view whose `active` query is not the only one on screen, so a sweep that
    /// touches 维护状态 reloads it too.
    func invalidate(_ type: DockerActionType) async {
        await invalidate(keys: type.invalidates)
    }

    /// The same sweep for the two places that name their keys directly rather than deriving them
    /// from a mutation: the upgrade check writes 维护状态, and a submitted Compose task writes 任务.
    func invalidate(keys: [DockerQuery]) async {
        guard !keys.isEmpty else { return }
        if keys.contains(activeQuery) || (view == .settings && keys.contains(.maintenance)) {
            await reloadActive()
        }
        guard keys.contains(.containerStats), statsActive else { return }
        await refreshStats()
    }
}
