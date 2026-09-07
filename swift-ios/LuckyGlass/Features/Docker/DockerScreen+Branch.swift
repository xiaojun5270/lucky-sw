import SwiftUI

// MARK: - 视图分支

extension DockerScreen {
    /// §10–§18's nine bodies, chosen by the tab picker above them.
    ///
    /// Each pane is a function of the screen's state and a bundle of closures; nothing below the
    /// branch reaches back into `DockerScreen`, because `private` in Swift is file-scoped and these
    /// views live in files of their own. The verbs are therefore handed down rather than looked up,
    /// and this file is the one place the whole wiring can be read at once.
    @ViewBuilder
    var branch: some View {
        switch view {
        case .containers: containersPane
        case .images: imagesPane
        case .compose: composePane
        case .networks: networksPane
        case .volumes: volumesPane
        case .tasks: tasksPane
        case .overview: overviewBranch
        case .settings: settingsPane
        case .logs: logsPane
        }
    }
}

// MARK: - 容器与镜像

extension DockerScreen {
    /// §10. The stop and restart confirmations quote the **raw** name, which is why both verbs take
    /// the pair — the mutation is keyed by `keyOf` and the sentence by the name beside it.
    private var containersPane: some View {
        DockerContainersView(
            items: filtered,
            icons: icons,
            stats: containerStatsByKey,
            loading: loading,
            busy: pending,
            refresh: { await refresh() },
            actions: DockerContainerActions(
                menu: { containerMenu = $0 },
                unpause: { key in run(DockerMutation(.containerUnpause, key: key)) },
                start: { key in run(DockerMutation(.containerStart, key: key)) },
                stop: { key, name in
                    danger("确认停止", "停止容器 \(name)？") {
                        run(DockerMutation(.containerStop, key: key))
                    }
                },
                restart: { key, name in
                    danger("确认重启", "重启容器 \(name)？") {
                        run(DockerMutation(.containerRestart, key: key))
                    }
                },
                update: { key, name in Task { await updateContainer(key, name) } }
            )
        )
    }

    /// §11. Twelve verbs, of which six only make sense while the selection mode is on.
    private var imagesPane: some View {
        DockerImagesView(
            entries: visibleImageEntries,
            batch: imageBatch,
            loading: loading,
            refresh: { await refresh() },
            actions: imageActions
        )
    }

    private var imageBatch: DockerImageBatch {
        DockerImageBatch(
            mode: selectionMode,
            selected: selectedImageSet,
            validCount: validSelectedImageIds.count,
            visibleCount: visibleImageIds.count,
            allVisibleSelected: allVisibleImagesSelected,
            upgradeChecking: imageUpgradeChecking,
            scanChecking: unusedScanChecking,
            scanProgress: unusedScanProgress,
            deleteProgress: imageDeleteProgress,
            pending: pending,
            selectionBusy: imageSelectionBusy,
            actionBusy: imageActionBusy
        )
    }

    private var imageActions: DockerImageActions {
        DockerImageActions(
            toggle: { toggleImage($0) },
            toggleMode: { toggleSelectionMode() },
            toggleVisible: { toggleVisibleImages() },
            selectUnused: { selectUnusedImages() },
            removeSelected: { removeSelectedImages() },
            upgrade: {
                if validSelectedImageIds.isEmpty {
                    showImageUpgradeStatus()
                } else {
                    detectImageUpgrades()
                }
            },
            // The build form starts empty: every field it grows comes from the daemon's own schema.
            build: { openEditor(.imageBuild, title: "构建镜像", value: .object([])) },
            tools: { imageToolsOpen = true },
            inspect: { key in Task { await inspect(.image, key) } },
            tag: { key in
                openEditor(.imageTag, title: "添加镜像标签", value: .object([
                    ("repository", .string("")), ("tag", .string("latest")),
                ]), key: key)
            },
            menu: { imageMenu = $0 },
            // The row's delete and §19.4's delete key off the same derivation, so the row builds
            // the menu value it would have opened and asks that for the key.
            remove: { key, name in
                let target = DockerImageMenu(key: key, name: name)
                danger("确认删除", "删除镜像 \(name)？") {
                    run(DockerMutation(.imageRemove, key: target.deleteKey))
                }
            }
        )
    }
}

// MARK: - Compose

extension DockerScreen {
    /// §12. Sixteen verbs behind one dispatcher, which is what keeps their order and their
    /// confirmations in the view where they are drawn.
    private var composePane: some View {
        DockerComposeView(
            items: filtered,
            loading: loading,
            busy: pending,
            refresh: { await refresh() },
            scan: {
                openEditor(.composeDiscover, title: "发现 Compose 项目",
                           value: .object([("scan_path", .string(""))]))
            },
            perform: { verb, target in composeVerb(verb, target) }
        )
    }

    /// The four lifecycle verbs and the four reads. Split in two only because a `switch` over
    /// sixteen cases is easier to check against §12's table in two halves.
    private func composeVerb(_ verb: DockerComposeVerb, _ target: DockerComposeTarget) {
        let name = target.name
        switch verb {
        case .start:
            run(DockerMutation(.composeStart, value: target.payload))
        case .stop:
            danger("确认停止", "停止 Compose 项目 \(name)？") {
                run(DockerMutation(.composeStop, value: target.payload))
            }
        case .restart:
            run(DockerMutation(.composeRestart, value: target.payload))
        case .logs:
            Task { await composeLogs(name) }
        case .editConfig:
            Task { await editComposeConfig(target.path) }
        case .dockerfile:
            Task { await editComposeDockerfile(target.path) }
        case .readFile:
            openEditor(.composeReadFile, title: "读取 Compose 文件 · \(name)", value: .object([
                ("project_path", .string(target.path)),
                ("file_path", .string("docker-compose.yml")),
            ]))
        case .restoreConfig:
            chooseUpload(.composeRestore, key: name, title: "恢复 Compose 配置 · \(name)",
                         fields: JSONObject([
                             ("target_path", .string(target.path)),
                             ("project_name", .string(name)), ("auto_start", .bool(true)),
                             ("config_file_name", .string("")),
                         ]))
        default:
            composeBackupVerb(verb, target)
        }
    }

    /// §12's eight backup verbs. All of them are keyed by the **display** name, not by
    /// `project_name` — a project the daemon never named still has backups under whatever the row
    /// is called.
    private func composeBackupVerb(_ verb: DockerComposeVerb, _ target: DockerComposeTarget) {
        let name = target.name
        let backup: JSONValue = .object([
            ("project_name", .string(name)), ("backup", .string("")),
        ])
        switch verb {
        case .backup:
            danger("确认备份", "备份 Compose 项目 \(name)？") {
                run(DockerMutation(.composeBackup, value: target.payload))
            }
        case .backupList:
            Task {
                await openDetail("Compose 备份 · \(name)") {
                    try await DockerService.composeBackups(projectName: name)
                }
            }
        case .backupDownload:
            openEditor(.composeBackupDownload, title: "下载 Compose 备份 · \(name)", value: backup)
        case .backupsClear:
            danger("清空 Compose 备份", "确定删除项目 \(name) 的全部备份吗？") {
                run(DockerMutation(.composeBackupsClear, value: target.namePayload))
            }
        case .backupUpload:
            chooseUpload(.composeBackupUpload, key: name, title: "上传 Compose 备份 · \(name)",
                         fields: JSONObject([("project_name", .string(name))]))
        case .backupRestore:
            openEditor(.composeBackupRestore, title: "恢复 Compose 备份 · \(name)", value: backup)
        case .backupRemove:
            openEditor(.composeBackupRemove, title: "删除 Compose 备份 · \(name)", value: backup)
        case .backupCancel:
            danger("取消备份", "取消 Compose 项目 \(name) 的备份任务？") {
                run(DockerMutation(.composeBackupCancel, value: target.namePayload))
            }
        default:
            // Unreachable: the eight verbs above are exactly the ones `composeVerb` delegates.
            break
        }
    }
}

// MARK: - 网络、数据卷与任务

extension DockerScreen {
    /// §13. One verb, and the only list whose row subtitle can come out as a bare separator.
    private var networksPane: some View {
        DockerNetworksView(
            items: filtered,
            loading: loading,
            busy: pending,
            refresh: { await refresh() },
            remove: { key, name in
                danger("确认删除", "删除网络 \(name)？") {
                    run(DockerMutation(.networkRemove, key: key))
                }
            }
        )
    }

    /// §14. Eight verbs, every one keyed by the volume's name.
    private var volumesPane: some View {
        DockerVolumesView(
            items: filtered,
            loading: loading,
            busy: pending,
            refresh: { await refresh() },
            importVolume: {
                chooseUpload(.volumeImport, key: "", title: "导入数据卷", fields: JSONObject([
                    ("volume_name", .string("")), ("driver", .string("local")),
                ]))
            },
            perform: { verb, name in volumeVerb(verb, name) }
        )
    }

    private func volumeVerb(_ verb: DockerVolumeVerb, _ name: String) {
        switch verb {
        case .backup:
            run(DockerMutation(.volumeBackup, key: name))
        case .backupList:
            Task {
                await openDetail("备份列表 · \(name)") {
                    try await DockerService.volumeBackups(name)
                }
            }
        case .export:
            Task {
                await download("导出数据卷 · \(name)", as: "\(name).tar.gz") {
                    try await DockerService.exportVolume(name)
                }
            }
        case .backupUpload:
            chooseUpload(.volumeBackupUpload, key: name, title: "上传数据卷备份 · \(name)",
                         fields: JSONObject())
        case .backupRestore:
            openEditor(.volumeRestore, title: "恢复数据卷备份",
                       value: .object([("backup", .string(""))]), key: name)
        case .backupRemove:
            openEditor(.volumeBackupRemove, title: "删除数据卷备份 · \(name)",
                       value: .object([("backup", .string(""))]), key: name)
        case .backupCancel:
            danger("取消备份", "取消数据卷 \(name) 的备份任务？") {
                run(DockerMutation(.volumeBackupCancel, key: name))
            }
        case .remove:
            danger("确认删除", "删除数据卷 \(name)？") {
                run(DockerMutation(.volumeRemove, key: name))
            }
        }
    }

    /// §15. The delete here is the screen's one unconfirmed destructive verb — a task record is a
    /// receipt, and removing it changes nothing that is running.
    private var tasksPane: some View {
        DockerTasksView(
            items: filtered,
            loading: loading,
            busy: pending,
            refresh: { await refresh() },
            inspect: { key in Task { await inspect(.task, key) } },
            remove: { key in run(DockerMutation(.taskRemove, key: key)) }
        )
    }
}

// MARK: - 总览、设置与日志

extension DockerScreen {
    /// §16. Both jumps clear the log drawer, and the ranking rows also pre-fill the search box —
    /// which is how tapping a container in the dashboard lands on its row in 容器.
    private var overviewBranch: some View {
        DockerOverviewPane(
            data: overview,
            active: overviewActive,
            stats: statsSource,
            statsLoading: containerStatRows.isEmpty
                && (statsLoading || (liveStatsNeeded && liveStatsLoading)),
            statsError: containerStatRows.isEmpty && liveStatsNeeded && !liveStatsFailure.isEmpty
                ? "容器统计暂时不可用" : "",
            refresh: { await refresh() },
            selectView: { target in
                search = ""
                output = nil
                view = DockerScreen.destination(of: target)
            },
            selectContainer: { name in
                output = nil
                search = name
                view = .containers
            }
        )
    }

    /// The dashboard's five destinations. It cannot name a `DockerView` itself — the summary tiles
    /// live in a file that knows nothing about the tab picker — so it names a target and the screen
    /// resolves it.
    private static func destination(of target: DockerOverviewTarget) -> DockerView {
        switch target {
        case .containers: .containers
        case .images: .images
        case .compose: .compose
        case .networks: .networks
        case .volumes: .volumes
        }
    }

    /// §17. Eight verbs, none of which fires anything on its own: seven open a form and the eighth
    /// asks first.
    private var settingsPane: some View {
        DockerSettingsView(
            config: config,
            mirrors: mirrors,
            maintenance: maintenance,
            maintenanceFetching: maintenanceFetching,
            maintenanceFailure: queryFailures[.maintenance] ?? "",
            loading: loading,
            refresh: { await refresh() },
            actions: settingsActions
        )
    }

    private var settingsActions: DockerSettingsActions {
        let group: JSONValue = .object([("Name", .string("")), ("Key", .string(""))])
        return DockerSettingsActions(
            editConfig: {
                openEditor(.configSave, title: "编辑 Docker 设置",
                           value: .object(DockerRecord.nested(config ?? .null, ["config", "data"])))
            },
            createGroup: { openEditor(.groupCreate, title: "添加容器分组", value: group) },
            updateGroup: { openEditor(.groupUpdate, title: "编辑容器分组", value: group) },
            removeGroup: {
                openEditor(.groupRemove, title: "删除容器分组",
                           value: .object([("key", .string(""))]))
            },
            clearUpgrades: {
                danger("清除升级状态", "确定清除全部镜像升级检查记录吗？") {
                    run(DockerMutation(.upgradeStatusClear))
                }
            },
            addMirror: {
                openEditor(.mirrorAdd, title: "添加镜像加速地址",
                           value: .object([("mirror", .string(""))]))
            },
            removeMirror: {
                openEditor(.mirrorRemove, title: "删除镜像加速地址",
                           value: .object([("mirror", .string(""))]))
            },
            // `volumes` defaults to false: a prune that takes the data with it should be a
            // decision, not a default.
            prune: {
                openEditor(.prune, title: "清理 Docker 资源", value: .object([
                    ("containers", .bool(true)), ("images", .bool(true)),
                    ("networks", .bool(true)), ("volumes", .bool(false)),
                    ("build_cache", .bool(true)),
                ]))
            }
        )
    }

    /// §18. Both modes, chosen by the view itself from whether `output` is there.
    private var logsPane: some View {
        DockerLogsView(output: output, lines: logLines, loading: loading,
                       refresh: { await refresh() })
    }
}
