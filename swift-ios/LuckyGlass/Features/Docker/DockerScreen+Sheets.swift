import SwiftUI

// MARK: - 表单与详情

extension DockerScreen {
    /// §19.2's `DockerFormEditor`. `busy` is `mutation.isPending` — any mutation at all, because
    /// only one can run and the editor is modal over the row that started it.
    func editorSheet(_ request: DockerEditorRequest) -> some View {
        DockerFormEditor(
            request: request,
            busy: running != nil,
            close: {
                releaseUpload(for: request.kind)
                editor = nil
            },
            save: { value in Task { await save(request, value) } }
        )
    }

    /// The editor sheet's `onDismiss`, which has no counterpart in the original: a swipe past a
    /// `Modal` was not possible there, so its `close` was the only way out and the only place the
    /// held file was released.
    ///
    /// The kind is already gone by the time this runs, hence the unconditional clear — nothing but
    /// one of those seven forms ever holds an upload, and the runner reads it before its first
    /// suspension, so releasing it after a dismissal can never strip a request in flight.
    func dismissEditor() {
        guard editor == nil else { return }
        upload = nil
    }

    /// §19.1's `ComposeCreateEditor`.
    var composeCreatorSheet: some View {
        ComposeCreateEditor(
            busy: running == .composeCreate,
            progress: composeProgress,
            failure: localError,
            close: { closeComposeCreator() },
            save: { value in createCompose(value) }
        )
    }

    /// §19's `DockerDetailViewer`. `closeDetail()` rather than a bare nil: the request id has to
    /// move on so a read still in flight writes nothing, and the upgrade sweep has to be cancelled
    /// with it.
    func detailSheet(_ request: DockerDetail) -> some View {
        DockerDetailViewer(detail: request) { closeDetail() }
    }
}

// MARK: - 镜像高级工具

extension DockerScreen {
    /// §19.3 — the four ways to make an image that are not `docker pull`.
    var imageToolsSheet: some View {
        DockerActionSheet(
            title: "镜像高级工具",
            subtitle: "构建、导入与加载",
            close: { imageToolsOpen = false },
            items: [
                // lucide `GitBranch`.
                DockerActionItem("Git 构建", "arrow.triangle.branch", LuckyTheme.accent) {
                    openEditor(.imageBuildGit, title: "从 Git 构建镜像", value: .object([
                        ("git_url", .string("")), ("branch", .string("main")),
                        ("dockerfile", .string("Dockerfile")), ("tag", .string("")),
                        ("build_args", .object([])), ("no_cache", .bool(false)),
                    ]))
                },
                // The two archive verbs open the picker instead of a form; the form follows once a
                // file has been chosen, with `file_name` already in it.
                DockerActionItem("ZIP 构建", "archivebox", LuckyTheme.warning) {
                    chooseArchive(.imageBuildZip)
                },
                DockerActionItem("导入镜像", LuckySymbol.download, LuckyTheme.info) {
                    openEditor(.imageImport, title: "导入镜像", value: .object([
                        ("source", .string("")), ("repository", .string("")),
                        ("tag", .string("latest")),
                    ]))
                },
                DockerActionItem("加载归档", LuckySymbol.upload, LuckyTheme.success) {
                    chooseArchive(.imageLoad)
                },
            ]
        )
    }
}

// MARK: - 镜像操作

extension DockerScreen {
    /// §19.4 — the five verbs §11's rows do not have room for.
    func imageMenuSheet(_ menu: DockerImageMenu) -> some View {
        DockerActionSheet(
            title: "镜像操作",
            subtitle: menu.name,
            close: { imageMenu = nil },
            items: imageMenuItems(menu)
        )
    }

    private func imageMenuItems(_ menu: DockerImageMenu) -> [DockerActionItem] {
        [
            DockerActionItem("镜像历史", "archivebox", LuckyTheme.textPrimary) {
                Task {
                    await openDetail("镜像历史 · \(menu.name)") {
                        try await DockerService.imageHistory(menu.key)
                    }
                }
            },
            // lucide `Tags`.
            DockerActionItem("查看标签", "tag", LuckyTheme.accent) {
                Task {
                    await openDetail("镜像标签 · \(menu.name)") {
                        try await DockerService.imageTags(menu.key)
                    }
                }
            },
            DockerActionItem("文件系统", "folder", LuckyTheme.warning) {
                openEditor(.imageFilesystemView, title: "浏览镜像文件系统",
                           value: .object([("path", .string("/"))]), key: menu.key)
            },
            // lucide `UploadCloud`.
            DockerActionItem("推送镜像", "icloud.and.arrow.up", LuckyTheme.info) {
                openEditor(.imagePush, title: "推送镜像",
                           value: .object(DockerRecord.imagePushValue(menu.name)), key: menu.key)
            },
            DockerActionItem("删除镜像", LuckySymbol.delete, LuckyTheme.danger) {
                danger("确认删除", "删除镜像 \(menu.name)？") {
                    run(DockerMutation(.imageRemove, key: menu.deleteKey))
                }
            },
        ]
    }
}

// MARK: - 容器操作

extension DockerScreen {
    /// §19.5 — eighteen verbs in the original's order, of which seventeen always appear.
    func containerMenuSheet(_ menu: DockerContainerMenu) -> some View {
        DockerActionSheet(
            title: "容器操作",
            subtitle: menu.name,
            close: { containerMenu = nil },
            items: containerMenuItems(menu)
        )
    }

    /// `menu.name` is the **raw** name and may keep its leading slash. Only 复制容器, 设置分组 and
    /// the export filename strip it; every title and message prints it as the daemon gave it.
    private func containerMenuItems(_ menu: DockerContainerMenu) -> [DockerActionItem] {
        var items: [DockerActionItem] = []
        // The one conditional entry: 恢复 lives on the row, so the drawer only ever pauses, and only
        // a container that is running and not already paused can be.
        if menu.running, !menu.paused {
            items.append(DockerActionItem("暂停容器", "pause.fill", LuckyTheme.warning) {
                run(DockerMutation(.containerPause, key: menu.key))
            })
        }
        items.append(contentsOf: containerReadItems(menu))
        items.append(contentsOf: containerFileItems(menu))
        items.append(contentsOf: containerEditItems(menu))
        return items
    }

    /// Entries 1–2: the inspect payload, and the log dump.
    private func containerReadItems(_ menu: DockerContainerMenu) -> [DockerActionItem] {
        [
            DockerActionItem("容器详情", LuckySymbol.search, LuckyTheme.textPrimary) {
                Task { await inspect(.container, menu.key) }
            },
            // lucide `FileText`. The dump goes to §18's pane, not to the detail viewer.
            DockerActionItem("查看日志", "doc.text", LuckyTheme.info) {
                Task { await containerLogs(menu.key) }
            },
        ]
    }

    /// Entries 3–8: the file verbs, and the two reads that sit between them.
    private func containerFileItems(_ menu: DockerContainerMenu) -> [DockerActionItem] {
        [
            DockerActionItem("管理文件", "folder", LuckyTheme.warning) {
                openEditor(.containerFiles, title: "容器文件操作", value: .object([
                    ("operation", .string("list")), ("path", .string("/")),
                ]), key: menu.key)
            },
            DockerActionItem("下载文件", LuckySymbol.download, LuckyTheme.info) {
                openEditor(.containerFileDownload, title: "下载容器文件",
                           value: .object([("path", .string("/"))]), key: menu.key)
            },
            DockerActionItem("上传文件", LuckySymbol.upload, LuckyTheme.warning) {
                chooseUpload(.containerFileUpload, key: menu.key, title: "上传文件 · \(menu.name)",
                             fields: JSONObject([("path", .string("/"))]))
            },
            DockerActionItem("导出容器", "archivebox", LuckyTheme.warning) {
                let bare = menu.bareName
                Task {
                    await download("导出容器 · \(menu.name)",
                                   as: "\(bare.isEmpty ? "container" : bare).tar") {
                        try await DockerService.exportContainer(menu.key)
                    }
                }
            },
            // lucide `Activity`.
            DockerActionItem("查看进程", LuckySymbol.monitor, LuckyTheme.info) {
                Task {
                    await openDetail("容器进程 · \(menu.name)") {
                        try await DockerService.containerProcesses(menu.key)
                    }
                }
            },
            DockerActionItem("Compose 配置", "doc.text", LuckyTheme.textPrimary) {
                Task {
                    await openDetail("Compose 配置 · \(menu.name)") {
                        try await DockerService.containerComposeConfig(menu.key)
                    }
                }
            },
        ]
    }

    /// Entries 9–17: everything that rewrites the container, ending with the two destructive ones.
    private func containerEditItems(_ menu: DockerContainerMenu) -> [DockerActionItem] {
        [
            DockerActionItem("编辑配置", LuckySymbol.edit, LuckyTheme.accent) {
                Task { await editContainer(menu.key) }
            },
            // lucide `Box`. The rename form starts from the raw name, slash and all.
            DockerActionItem("重命名", "shippingbox", LuckyTheme.accent) {
                openEditor(.containerRename, title: "重命名容器",
                           value: .object([("name", .string(menu.name))]), key: menu.key)
            },
            DockerActionItem("复制容器", LuckySymbol.copy, LuckyTheme.accent) {
                openEditor(.containerCopy, title: "复制容器",
                           value: .object([("name", .string("\(menu.bareName)-copy"))]),
                           key: menu.key)
            },
            DockerActionItem("提交为镜像", "archivebox", LuckyTheme.warning) {
                openEditor(.containerCommit, title: "提交容器为镜像", value: .object([
                    ("repository", .string("")), ("tag", .string("latest")),
                    ("author", .string("")), ("comment", .string("")), ("pause", .bool(true)),
                ]), key: menu.key)
            },
            DockerActionItem("设置标签", "tag", LuckyTheme.accent) {
                openEditor(.containerLabelSet, title: "设置容器标签",
                           value: .object([("label", .string(""))]), key: menu.key)
            },
            DockerActionItem("移除标签", LuckySymbol.delete, LuckyTheme.danger) {
                danger("移除标签", "移除容器 \(menu.name) 的标签？") {
                    run(DockerMutation(.containerLabelRemove, key: menu.key))
                }
            },
            // lucide `Layers`.
            DockerActionItem("设置分组", "square.3.layers.3d", LuckyTheme.accent) {
                openEditor(.containerGroupSet, title: "设置容器分组", value: .object([
                    ("container_name", .string(menu.bareName)), ("group_key", .string("")),
                ]), key: menu.key)
            },
            DockerActionItem("切换版本", "arrow.triangle.branch", LuckyTheme.info) {
                openEditor(.containerVersionSwitch, title: "切换容器版本",
                           value: .object([("target_image_ref", .string(""))]), key: menu.key)
            },
            DockerActionItem("删除容器", LuckySymbol.delete, LuckyTheme.danger) {
                danger("确认删除", "强制删除容器 \(menu.name)？") {
                    run(DockerMutation(.containerRemove, key: menu.key))
                }
            },
        ]
    }
}
