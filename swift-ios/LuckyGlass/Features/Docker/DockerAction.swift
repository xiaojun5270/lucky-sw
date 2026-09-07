import Foundation

/// §20 — the `type` of every mutation the Docker screen dispatches.
///
/// The original passes a bare string and reads it back with `startsWith`, so an unlisted verb falls
/// off the end of the ladder into `不支持的 Docker 操作`. Naming all sixty-three makes that terminal
/// throw unrepresentable and it therefore has no counterpart here; the string tests the ladder
/// needed — the container and compose fall-throughs, and §26's prefix cascade — become properties.
enum DockerActionType: String, Hashable, Sendable, CaseIterable {
    // MARK: 容器

    case containerCreate = "container-create"
    case containerEdit = "container-edit"
    case containerRemove = "container-remove"
    case containerRename = "container-rename"
    case containerCopy = "container-copy"
    case containerCommit = "container-commit"
    case containerLabelSet = "container-label-set"
    case containerLabelRemove = "container-label-remove"
    case containerGroupSet = "container-group-set"
    case containerVersionSwitch = "container-version-switch"
    case containerFileUpload = "container-file-upload"
    case containerFiles = "container-files"
    case containerUpgrade = "container-upgrade"
    /// The five the `type.startsWith("container-")` fall-through turns into a lifecycle verb.
    case containerStart = "container-start"
    case containerStop = "container-stop"
    case containerRestart = "container-restart"
    case containerPause = "container-pause"
    case containerUnpause = "container-unpause"

    // MARK: 镜像

    case imagePull = "image-pull"
    case imageRemove = "image-remove"
    /// Plural, and therefore **not** matched by `startsWith("image-")` — §26 tests it separately.
    case imagesRemoveBatch = "images-remove-batch"
    case imageTag = "image-tag"
    case imageBuild = "image-build"
    case imageBuildGit = "image-build-git"
    case imageBuildZip = "image-build-zip"
    case imageImport = "image-import"
    case imageLoad = "image-load"
    case imagePush = "image-push"

    // MARK: Compose

    case composeCreate = "compose-create"
    /// The `-save` counterparts §19.2 rewrites `compose-config` and `compose-dockerfile` into.
    case composeConfigSave = "compose-config-save"
    case composeDockerfileSave = "compose-dockerfile-save"
    case composeBackup = "compose-backup"
    case composeBackupRestore = "compose-backup-restore"
    case composeBackupRemove = "compose-backup-remove"
    case composeBackupUpload = "compose-backup-upload"
    case composeBackupCancel = "compose-backup-cancel"
    case composeBackupsClear = "compose-backups-clear"
    case composeRestore = "compose-restore"
    /// The five the `type.startsWith("compose-")` fall-through turns into a project verb. The grid
    /// only ever dispatches the last three; `up` and `down` are kept because the fall-through casts
    /// to the full union and the daemon accepts them.
    case composeUp = "compose-up"
    case composeDown = "compose-down"
    case composeStart = "compose-start"
    case composeStop = "compose-stop"
    case composeRestart = "compose-restart"

    // MARK: 网络与数据卷

    case networkCreate = "network-create"
    case networkRemove = "network-remove"
    case volumeCreate = "volume-create"
    case volumeRemove = "volume-remove"
    case volumeBackup = "volume-backup"
    case volumeRestore = "volume-restore"
    case volumeBackupRemove = "volume-backup-remove"
    case volumeBackupUpload = "volume-backup-upload"
    case volumeBackupCancel = "volume-backup-cancel"
    case volumeImport = "volume-import"

    // MARK: 任务与设置

    case taskRemove = "task-remove"
    /// Plural again — `"tasks-clear".startsWith("task-")` is false.
    case tasksClear = "tasks-clear"
    case groupCreate = "group-create"
    case groupUpdate = "group-update"
    case groupRemove = "group-remove"
    case upgradeStatusClear = "upgrade-status-clear"
    case configSave = "config-save"
    case prune
    case mirrorAdd = "mirror-add"
    case mirrorRemove = "mirror-remove"
}

// MARK: - §26 的失效级联

extension DockerActionType {
    private var isContainer: Bool { rawValue.hasPrefix("container-") }
    private var isImage: Bool { rawValue.hasPrefix("image-") }
    private var isCompose: Bool { rawValue.hasPrefix("compose-") }
    private var isNetwork: Bool { rawValue.hasPrefix("network-") }
    private var isVolume: Bool { rawValue.hasPrefix("volume-") }
    private var isTask: Bool { rawValue.hasPrefix("task-") }
    private var isGroup: Bool { rawValue.hasPrefix("group-") }
    private var isMirror: Bool { rawValue.hasPrefix("mirror-") }

    /// The queries a success refetches — the first matching branch of §26's ladder wins, so
    /// `container-files` short-circuits before the `container-` prefix ever gets a look.
    ///
    /// The ordering matters twice more: `images-remove-batch` is tested alongside the `image-`
    /// prefix because it does not carry it, and `tasks-clear` alongside `task-` for the same
    /// reason.
    var invalidates: [DockerQuery] {
        // Reading or writing a path inside a container changes no list metadata.
        if self == .containerFiles { return [] }
        if isContainer {
            var keys: [DockerQuery] = [.containers, .containerStats, .overview]
            if self == .containerCommit || self == .containerVersionSwitch { keys.append(.images) }
            if [.containerLabelSet, .containerLabelRemove, .containerGroupSet].contains(self) {
                keys.append(.maintenance)
            }
            return keys
        }
        if isImage || self == .imagesRemoveBatch { return [.images, .overview] }
        if isCompose {
            var keys: [DockerQuery] = [.compose, .overview]
            if self == .composeCreate { keys.append(contentsOf: [.tasks, .containers, .images]) }
            if rawValue.contains("backup") { keys.append(.maintenance) }
            return keys
        }
        if isNetwork { return [.networks, .overview] }
        if isVolume {
            var keys: [DockerQuery] = [.volumes, .overview]
            if rawValue.contains("backup") || self == .volumeRestore { keys.append(.maintenance) }
            return keys
        }
        if isTask || self == .tasksClear { return [.tasks] }
        if isGroup { return [.containers, .overview, .maintenance] }
        if self == .configSave { return [.config] }
        if isMirror { return [.mirrors] }
        if self == .upgradeStatusClear { return [.maintenance] }
        return [.overview]
    }

    /// The seven whose success releases the held upload.
    var clearsUpload: Bool {
        [.imageBuildZip, .imageLoad, .containerFileUpload, .composeBackupUpload,
         .composeRestore, .volumeBackupUpload, .volumeImport].contains(self)
    }

    /// The notice a success prints. `images-remove-batch` composes its own from the report.
    var notice: String {
        switch self {
        case .containerFiles: return "文件操作已完成"
        case .composeCreate: return "Compose 项目已创建并启动"
        default: return "操作已完成，数据已刷新"
        }
    }
}

// MARK: - 请求

/// `mutation.mutate({ type, key, value })` — the whole input of one Docker mutation.
struct DockerMutation: Sendable {
    var type: DockerActionType
    var key: String?
    var value: JSONValue?

    init(_ type: DockerActionType, key: String? = nil, value: JSONValue? = nil) {
        self.type = type
        self.key = key
        self.value = value
    }

    /// `key ?? ""`
    var id: String { key ?? "" }

    /// `value ?? {}`
    var record: JSONValue { value ?? .object([]) }

    /// `{ ...(value ?? {}) }` — the spread the two `delete` sites start from.
    var fields: JSONObject { value?.objectValue ?? JSONObject() }

    /// `String(value?.<key> ?? fallback)`. A `null` counts as absent, exactly as `??` does; a
    /// present-but-empty string does not, which is why several checks then trim and re-test.
    func text(_ key: String, or fallback: String = "") -> String {
        guard let value = value?[key], !value.isNull else { return fallback }
        return value.asDisplayString
    }

    /// The same, trimmed — `String(value?.<key> ?? "").trim()`.
    func trimmed(_ key: String, or fallback: String = "") -> String {
        text(key, or: fallback).jsTrimmed
    }

    /// `Boolean(value?.<key>)`
    func flag(_ key: String) -> Bool { value?[key]?.isTruthy ?? false }

    /// `String(value?.<first> ?? value?.<second> ?? "")` — `??` skips only a null, so a present but
    /// blank `first` is *not* replaced by `second`.
    func text(either first: String, or second: String) -> String {
        if let value = value?[first], !value.isNull { return value.asDisplayString }
        return text(second)
    }
}

// MARK: - 执行

/// The `mutationFn` of §20's ladder, with the two pieces of screen state it reads — the held upload
/// and the two progress sinks — passed in rather than captured.
///
/// The original's `signal` is gone: `compose-create` is the only type that used it, and cancelling
/// its `Task` now does the same job through structured concurrency.
struct DockerActionRunner: Sendable {
    /// `dockerUpload` — the file the picker is holding, which seven of the types require.
    var upload: DockerAsset?
    /// `setImageDeleteProgress` during `images-remove-batch`.
    var onImageDelete: (@Sendable (DockerProgress) -> Void)?
    /// `setComposeCreateProgress` during `compose-create`.
    var onCompose: (@Sendable (DockerComposeProgress) -> Void)?
    /// `invalidateQueries(["docker","tasks"])`, fired the moment the create task gets its ID.
    var onComposeTaskSubmitted: (@Sendable () -> Void)?

    func run(_ mutation: DockerMutation) async throws -> JSONValue {
        switch mutation.type {
        case .containerCreate, .containerEdit, .containerRemove, .containerRename, .containerCopy,
             .containerCommit, .containerLabelSet, .containerLabelRemove, .containerGroupSet,
             .containerVersionSwitch, .containerFileUpload, .containerFiles, .containerUpgrade,
             .containerStart, .containerStop, .containerRestart, .containerPause, .containerUnpause:
            return try await container(mutation)
        case .imagePull, .imageRemove, .imagesRemoveBatch, .imageTag, .imageBuild, .imageBuildGit,
             .imageBuildZip, .imageImport, .imageLoad, .imagePush:
            return try await image(mutation)
        case .composeCreate, .composeConfigSave, .composeDockerfileSave, .composeBackup,
             .composeBackupRestore, .composeBackupRemove, .composeBackupUpload,
             .composeBackupCancel, .composeBackupsClear, .composeRestore, .composeUp,
             .composeDown, .composeStart, .composeStop, .composeRestart:
            return try await compose(mutation)
        case .networkCreate, .networkRemove, .volumeCreate, .volumeRemove, .volumeBackup,
             .volumeRestore, .volumeBackupRemove, .volumeBackupUpload, .volumeBackupCancel,
             .volumeImport:
            return try await storage(mutation)
        case .taskRemove, .tasksClear, .groupCreate, .groupUpdate, .groupRemove,
             .upgradeStatusClear, .configSave, .prune, .mirrorAdd, .mirrorRemove:
            return try await system(mutation)
        }
    }
}

// MARK: 容器

extension DockerActionRunner {
    private func container(_ mutation: DockerMutation) async throws -> JSONValue {
        switch mutation.type {
        case .containerCreate:
            return try await DockerService.createContainer(mutation.record)
        case .containerEdit:
            return try await DockerService.editContainer(mutation.id, mutation.record)
        case .containerRemove:
            // `removeDockerContainer(key, true, false)` — forced, but the volumes are left alone.
            return try await DockerService.removeContainer(
                mutation.id, force: true, removeVolumes: false
            )
        case .containerRename:
            // Untrimmed, unchecked: a blank name is the daemon's to reject.
            return try await DockerService.renameContainer(mutation.id, name: mutation.text("name"))
        case .containerCopy:
            let name = mutation.trimmed("name")
            guard !name.isEmpty else { throw LuckyError("请输入新容器名称") }
            return try await DockerService.copyContainer(mutation.id, name: name)
        case .containerCommit:
            guard !mutation.trimmed("repository").isEmpty else {
                throw LuckyError("请输入镜像仓库名称")
            }
            return try await DockerService.commitContainer(mutation.id, mutation.record)
        case .containerLabelSet:
            let label = mutation.trimmed("label")
            guard !label.isEmpty else { throw LuckyError("请输入容器标签") }
            return try await DockerService.setContainerLabel(mutation.id, label: label)
        case .containerLabelRemove:
            return try await DockerService.removeContainerLabel(mutation.id)
        case .containerGroupSet:
            let name = mutation.trimmed("container_name")
            let group = mutation.trimmed("group_key")
            guard !name.isEmpty, !group.isEmpty else {
                throw LuckyError("请输入容器名称和分组标识")
            }
            return try await DockerService.setContainerGroup(containerName: name, groupKey: group)
        default:
            return try await containerRest(mutation)
        }
    }

    /// The rest of the container ladder, split only to keep one `switch` from running to sixty
    /// lines.
    private func containerRest(_ mutation: DockerMutation) async throws -> JSONValue {
        switch mutation.type {
        case .containerVersionSwitch:
            let target = mutation.trimmed("target_image_ref")
            guard !target.isEmpty else { throw LuckyError("请输入目标镜像标签") }
            // `[key ?? ""].filter(Boolean)` — a missing key sends `[]`, not `[""]`.
            let ids: [JSONValue] = mutation.id.isEmpty ? [] : [.string(mutation.id)]
            return try await DockerService.switchContainerVersion(
                containerIds: .array(ids), targetImageRef: target
            )
        case .containerFileUpload:
            guard let upload else { throw LuckyError("请重新选择要上传的文件") }
            return try await DockerService.uploadContainerFile(
                mutation.id, DockerFile.uploadForm(upload, mutation.fields)
            )
        case .containerFiles:
            // `String(value?.operation ?? "list").trim()` — absent means `list`, blank stays blank
            // and the service rejects it by name.
            let operation = mutation.trimmed("operation", or: "list")
            var request = mutation.fields
            request.removeValue(forKey: "operation")
            return try await DockerService.containerFileOperation(
                mutation.id, operation, .object(request)
            )
        case .containerUpgrade:
            return try await DockerService.upgradeContainer(mutation.id, mutation.record)
        // `runDockerContainerAction(key, type.replace("container-", ""))`.
        case .containerStart: return try await DockerService.containerAction(mutation.id, .start)
        case .containerStop: return try await DockerService.containerAction(mutation.id, .stop)
        case .containerRestart:
            return try await DockerService.containerAction(mutation.id, .restart)
        case .containerPause: return try await DockerService.containerAction(mutation.id, .pause)
        case .containerUnpause:
            return try await DockerService.containerAction(mutation.id, .unpause)
        default:
            throw LuckyError("不支持的 Docker 操作")
        }
    }
}

// MARK: 镜像

extension DockerActionRunner {
    private func image(_ mutation: DockerMutation) async throws -> JSONValue {
        switch mutation.type {
        case .imagePull:
            return try await DockerService.pullImage(mutation.record)
        case .imageRemove:
            // `removeDockerImage(key, true)` — forced here, unlike the batch, which is not.
            return try await DockerService.removeImage(mutation.id, force: true)
        case .imagesRemoveBatch:
            return try await removeImages(mutation)
        case .imageTag:
            return try await DockerService.tagImage(
                mutation.id,
                repository: mutation.text("repository"),
                tag: mutation.text("tag", or: "latest")
            )
        case .imageBuild:
            return try await DockerService.buildImage(mutation.record)
        case .imageBuildGit:
            guard !mutation.trimmed("git_url").isEmpty else { throw LuckyError("请输入 Git 仓库地址") }
            return try await DockerService.buildImageFromGit(mutation.record)
        case .imageBuildZip:
            guard let upload else { throw LuckyError("请重新选择 ZIP 构建文件") }
            return try await DockerService.buildImageFromZip(
                DockerFile.uploadForm(upload, mutation.fields)
            )
        case .imageImport:
            guard !mutation.trimmed("source").isEmpty else { throw LuckyError("请输入镜像导入来源") }
            return try await DockerService.importImage(mutation.record)
        case .imageLoad:
            guard let upload else { throw LuckyError("请重新选择镜像归档文件") }
            return try await DockerService.loadImage(DockerFile.uploadForm(upload, mutation.fields))
        case .imagePush:
            let image = mutation.trimmed("image")
            guard !image.isEmpty else { throw LuckyError("请输入要推送的镜像") }
            // `String(value?.tag ?? "latest").trim() || "latest"` — a blank tag falls back too.
            let tag = mutation.trimmed("tag", or: "latest")
            return try await DockerService.pushImage(image, tag: tag.isEmpty ? "latest" : tag)
        default:
            throw LuckyError("不支持的 Docker 操作")
        }
    }

    /// `images-remove-batch` — the only mutation that reports partial success as a value.
    ///
    /// `removeDockerImages` never throws, so the escalation is done here: nothing removed *and*
    /// something failed means the first failure's own message is raised instead.
    private func removeImages(_ mutation: DockerMutation) async throws -> JSONValue {
        // `Array.isArray(value?.ids) ? value.ids.map(String).filter(Boolean) : []`
        let ids = (mutation.value?["ids"]?.list ?? []).map(\.asDisplayString).filter { !$0.isEmpty }
        guard !ids.isEmpty else { throw LuckyError("未选择要删除的镜像") }
        let total = ids.count
        let sink = onImageDelete
        let report = await DockerService.removeImages(ids) { progress in
            // `Number(progress.totalCount) || ids.length` — a zero total falls back to the count.
            let reported = progress["totalCount"]?.asInt ?? 0
            sink?(DockerProgress(
                completed: progress["completedCount"]?.asInt ?? 0,
                total: reported == 0 ? total : reported
            ))
        }
        let removed = report["removedCount"]?.asInt ?? 0
        let failed = report["failedCount"]?.asInt ?? 0
        if removed == 0, failed > 0 {
            let first = report["failed"]?.list.first?.objectValue?["error"]?.asDisplayString ?? ""
            throw LuckyError(first.isEmpty ? "批量删除镜像失败" : first)
        }
        return report
    }

    /// The success notice and the surviving selection, read back off that same report.
    static func batchOutcome(_ report: JSONValue) -> (notice: String, failedIds: [String]) {
        let removed = report["removedCount"]?.asInt ?? 0
        let failed = report["failedCount"]?.asInt ?? 0
        let failedIds = (report["failed"]?.list ?? [])
            .map { $0.objectValue?["item"]?.asDisplayString ?? "" }
            .filter { !$0.isEmpty }
        let suffix = failed == 0 ? "" : "，\(failed) 个删除失败"
        return ("已删除 \(removed) 个镜像\(suffix)", failedIds)
    }
}

// MARK: Compose

extension DockerActionRunner {
    private func compose(_ mutation: DockerMutation) async throws -> JSONValue {
        switch mutation.type {
        case .composeCreate:
            return try await createCompose(mutation)
        case .composeConfigSave:
            let path = mutation.trimmed("project_path")
            let content = mutation.text("content")
            guard !path.isEmpty, !content.jsTrimmed.isEmpty else {
                throw LuckyError("Compose 配置路径或内容为空")
            }
            do {
                return try await DockerService.updateComposeConfig(
                    projectPath: path, content: content
                )
            } catch {
                throw composeError(error, projectPath: path)
            }
        case .composeDockerfileSave:
            let path = mutation.trimmed("project_path")
            let content = mutation.text("content")
            // The Dockerfile save is the one compose write whose failure is *not* rewritten.
            guard !path.isEmpty, !content.jsTrimmed.isEmpty else {
                throw LuckyError("Dockerfile 路径或内容为空")
            }
            return try await DockerService.updateComposeDockerfile(
                projectPath: path, content: content
            )
        case .composeBackup:
            return try await backupCompose(mutation)
        case .composeUp, .composeDown, .composeStart, .composeStop, .composeRestart:
            return try await composeVerb(mutation)
        default:
            return try await composeBackups(mutation)
        }
    }

    /// `throw composeProjectError(error, projectPath)` — the rewrite when the daemon said the
    /// directory is missing, and otherwise the *original* error, which is what the TS's
    /// `return error instanceof Error ? error : …` does and what keeps a cancellation recognisable.
    private func composeError(_ error: Error, projectPath: String) -> Error {
        let message = error.luckyMessage()
        let rewritten = DockerRecord.composeProjectError(message, projectPath: projectPath)
        return rewritten == message ? error : LuckyError(rewritten)
    }
}

// MARK: Compose 创建

extension DockerActionRunner {
    /// `compose-create` — the only mutation that submits a task and then follows it to the end.
    ///
    /// Its three guards are the mutation's own, and their copy is blunter than the creator's: the
    /// form has already said which field is wrong by the time this runs.
    private func createCompose(_ mutation: DockerMutation) async throws -> JSONValue {
        let workingDirectory = mutation.trimmed("working_dir")
        let configFileName = mutation.trimmed("config_file_name")
        let composeContent = mutation.text("compose_content")
        guard !workingDirectory.isEmpty else { throw LuckyError("请输入 Compose 工作目录") }
        guard !configFileName.isEmpty, !configFileName.contains("/"),
              !configFileName.contains("\\"),
              DockerComposeCreateValue.isYAMLName(configFileName) else {
            throw LuckyError("请输入有效的 Compose 配置文件名")
        }
        guard !composeContent.jsTrimmed.isEmpty else { throw LuckyError("Compose YAML 内容为空") }
        onCompose?(DockerComposeProgress(message: "正在提交 Compose 创建任务"))
        let submission = try await DockerService.createCompose(DockerComposeCreateInput(
            projectName: mutation.trimmed("project_name"),
            workingDirectory: workingDirectory,
            composeContent: composeContent,
            configFileName: configFileName,
            build: mutation.flag("build")
        ))
        let taskId = (DockerRecord.deepScalar(submission, ["task_id", "taskId", "id"])?
            .asDisplayString ?? "").jsTrimmed
        guard !taskId.isEmpty else { throw LuckyError("服务端未返回 Compose 创建任务 ID") }
        onCompose?(DockerComposeProgress(taskId: taskId, message: "Compose 创建任务已提交"))
        // The task list is refreshed the moment the ID is known, so the 任务 tab shows the work
        // while it runs rather than only once it finishes.
        onComposeTaskSubmitted?()
        let sink = onCompose
        let task = try await DockerService.waitForTask(taskId) { snapshot in
            sink?(DockerComposeProgress(snapshot, taskId: taskId))
        }
        return .object([("submission", submission), ("task", task)])
    }
}

// MARK: Compose 备份

extension DockerActionRunner {
    /// The six forms keyed by project *name* rather than by path.
    private func composeBackups(_ mutation: DockerMutation) async throws -> JSONValue {
        let projectName = mutation.trimmed("project_name")
        switch mutation.type {
        case .composeBackupRestore, .composeBackupRemove:
            let backup = mutation.trimmed("backup")
            guard !projectName.isEmpty, !backup.isEmpty else {
                throw LuckyError("请输入项目名称和备份文件")
            }
            // Two throwing calls cannot be a ternary: `try` may not appear right of `?` or `:`.
            if mutation.type == .composeBackupRestore {
                return try await DockerService.restoreComposeBackup(
                    projectName: projectName, backup: backup
                )
            }
            return try await DockerService.removeComposeBackup(
                projectName: projectName, backup: backup
            )
        case .composeBackupUpload:
            guard !projectName.isEmpty, let upload else {
                throw LuckyError("请重新选择 Compose 备份文件")
            }
            // The name travels in the path, so it is dropped from the form rather than sent twice.
            var fields = mutation.fields
            fields.removeValue(forKey: "project_name")
            return try await DockerService.uploadComposeBackup(
                projectName: projectName, DockerFile.uploadForm(upload, fields)
            )
        case .composeBackupCancel, .composeBackupsClear:
            guard !projectName.isEmpty else { throw LuckyError("Compose 项目名称缺失") }
            if mutation.type == .composeBackupCancel {
                return try await DockerService.cancelComposeBackup(projectName: projectName)
            }
            return try await DockerService.clearComposeBackups(projectName: projectName)
        case .composeRestore:
            let targetPath = mutation.trimmed("target_path")
            guard let upload, !targetPath.isEmpty else {
                throw LuckyError("请选择备份文件并填写目标路径")
            }
            // Only these four fields are sent — the rest of the form is the picker's bookkeeping.
            return try await DockerService.restoreCompose(DockerFile.uploadForm(upload, JSONObject([
                ("target_path", .string(targetPath)),
                ("project_name", .string(projectName)),
                ("auto_start", .bool(mutation.flag("auto_start"))),
                ("config_file_name", .string(mutation.trimmed("config_file_name"))),
            ])))
        default:
            throw LuckyError("不支持的 Docker 操作")
        }
    }

    /// `compose-backup` — the one mutation that reads the settings first, because the daemon
    /// answers an unconfigured backup directory with a bare `invalid request` and nothing else.
    private func backupCompose(_ mutation: DockerMutation) async throws -> JSONValue {
        let projectPath = mutation.trimmed("project_path")
        let projectName = mutation.trimmed("project_name")
        guard !projectPath.isEmpty, !projectName.isEmpty else {
            throw LuckyError("Compose 项目名称或路径缺失")
        }
        let configResult = try await DockerService.config()
        let config = DockerRecord.nested(configResult, ["config", "data", "result"])
        let backupPath = DockerRecord.pickComposeField(.object(config), ["compose_backup_path"])
        guard !backupPath.isEmpty else {
            throw LuckyError("请先在 Docker 设置中配置 Compose 备份路径")
        }
        do {
            // Reading the project's own config first turns "the directory was never mounted" into
            // the mount instruction, before the backup fails with something vaguer.
            _ = try await DockerService.readComposeConfig(projectPath: projectPath)
            return try await DockerService.backupCompose(
                projectPath: projectPath, projectName: projectName
            )
        } catch {
            let message = error.luckyMessage()
            let rewritten = DockerRecord.composeProjectError(message, projectPath: projectPath)
            // `projectError === error` — the directory rewrite did not fire, so this is the
            // daemon's own wording, and a bare `invalid request` means the directory is at fault.
            if rewritten == message, Self.isBareInvalidRequest(message) {
                throw LuckyError(
                    "Compose 备份请求被服务端拒绝，请确认备份目录 \(backupPath) 已存在且 Lucky 具有写入权限。"
                )
            }
            throw composeError(error, projectPath: projectPath)
        }
    }

    /// `/^invalid request:?\s*$/i` — the whole message, with nothing after the optional colon.
    private static func isBareInvalidRequest(_ message: String) -> Bool {
        let marker = "invalid request"
        guard message.lowercased().hasPrefix(marker) else { return false }
        var rest = Substring(message).dropFirst(marker.count)
        if rest.first == ":" { rest = rest.dropFirst() }
        return rest.allSatisfy(\.isWhitespace)
    }

    /// The five lifecycle verbs, which share one body and one error rewrite.
    private func composeVerb(_ mutation: DockerMutation) async throws -> JSONValue {
        let projectPath = mutation.trimmed("project_path")
        let projectName = mutation.trimmed("project_name")
        guard !projectPath.isEmpty, !projectName.isEmpty else {
            throw LuckyError("Compose 项目名称或路径缺失")
        }
        let action: DockerService.ComposeAction
        switch mutation.type {
        case .composeUp: action = .up
        case .composeDown: action = .down
        case .composeStart: action = .start
        case .composeStop: action = .stop
        default: action = .restart
        }
        // `{ ...value, project_path, project_name }` — the two trimmed names overwrite whatever the
        // row carried, and every other field of the row survives.
        var data = mutation.fields
        data["project_path"] = .string(projectPath)
        data["project_name"] = .string(projectName)
        do {
            return try await DockerService.composeAction(action, .object(data))
        } catch {
            throw composeError(error, projectPath: projectPath)
        }
    }
}

// MARK: 网络与数据卷

extension DockerActionRunner {
    private func storage(_ mutation: DockerMutation) async throws -> JSONValue {
        switch mutation.type {
        case .networkCreate:
            return try await DockerService.createNetwork(mutation.record)
        case .networkRemove:
            return try await DockerService.removeNetwork(mutation.id)
        case .volumeCreate:
            return try await DockerService.createVolume(mutation.record)
        case .volumeRemove:
            return try await DockerService.removeVolume(mutation.id)
        case .volumeBackup:
            return try await DockerService.backupVolume(mutation.id)
        case .volumeRestore, .volumeBackupRemove:
            let backup = mutation.trimmed("backup")
            guard !backup.isEmpty else { throw LuckyError("请输入备份文件") }
            if mutation.type == .volumeRestore {
                return try await DockerService.restoreVolumeBackup(mutation.id, backup: backup)
            }
            return try await DockerService.removeVolumeBackup(mutation.id, backup: backup)
        case .volumeBackupUpload:
            guard let upload else { throw LuckyError("请重新选择数据卷备份文件") }
            return try await DockerService.uploadVolumeBackup(
                mutation.id, DockerFile.uploadForm(upload, mutation.fields)
            )
        case .volumeBackupCancel:
            return try await DockerService.cancelVolumeBackup(mutation.id)
        default:
            return try await importVolume(mutation)
        }
    }

    /// `volume-import` — the archive's own filename is offered as the volume name, so the character
    /// check runs here rather than in the form.
    private func importVolume(_ mutation: DockerMutation) async throws -> JSONValue {
        let name = mutation.trimmed("volume_name")
        guard let upload else { throw LuckyError("请重新选择数据卷归档文件") }
        // A blank name is allowed: the daemon then keeps the name recorded inside the archive.
        if !name.isEmpty, !Self.isVolumeName(name) {
            throw LuckyError("数据卷名称只能包含字母、数字、点、下划线和连字符，且不能以点开头")
        }
        // `String(value?.driver ?? "local").trim() || "local"` — blank falls back a second time.
        var driver = mutation.trimmed("driver", or: "local")
        if driver.isEmpty { driver = "local" }
        return try await DockerService.importVolume(DockerFile.uploadForm(upload, JSONObject([
            ("volume_name", .string(name)),
            ("driver", .string(driver)),
        ])))
    }

    /// `!name.startsWith(".") && name.length <= 255 && /^[a-zA-Z0-9_.-]+$/.test(name)`
    private static func isVolumeName(_ name: String) -> Bool {
        guard !name.hasPrefix("."), name.count <= 255 else { return false }
        return name.allSatisfy { character in
            guard character.isASCII else { return false }
            return character.isLetter || character.isNumber
                || character == "_" || character == "." || character == "-"
        }
    }
}

// MARK: 任务与设置

extension DockerActionRunner {
    private func system(_ mutation: DockerMutation) async throws -> JSONValue {
        switch mutation.type {
        case .taskRemove:
            return try await DockerService.removeTask(mutation.id)
        case .tasksClear:
            return try await DockerService.clearTasks()
        case .groupCreate:
            return try await DockerService.createContainerGroup(mutation.record)
        case .groupUpdate:
            // The daemon capitalises the field and the form does not, so both spellings count.
            guard !mutation.text(either: "Key", or: "key").jsTrimmed.isEmpty else {
                throw LuckyError("请输入分组标识")
            }
            // The whole record is sent, capitalisation and all — the check is only a check.
            return try await DockerService.updateContainerGroup(mutation.record)
        case .groupRemove:
            // `String(value?.key ?? key ?? "")` — the payload's own field wins over the row key.
            return try await DockerService.removeContainerGroup(
                key: mutation.text("key", or: mutation.id)
            )
        case .upgradeStatusClear:
            return try await DockerService.clearImageUpgradeStatus()
        case .configSave:
            return try await DockerService.updateConfig(mutation.record)
        case .prune:
            return try await DockerService.prune(mutation.record)
        case .mirrorAdd:
            // Untrimmed: §24.5's form trims the field before it dispatches.
            return try await DockerService.addRegistryMirror(mutation.text("mirror"))
        default:
            // `mirror-remove` carries the mirror in `key`, which is why it sends no value at all.
            return try await DockerService.removeRegistryMirror(mutation.id)
        }
    }
}
