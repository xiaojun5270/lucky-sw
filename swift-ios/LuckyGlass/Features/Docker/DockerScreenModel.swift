import Foundation

/// §1 — `DockerView`, the nine segments of the screen, in tab order.
enum DockerView: String, Hashable, CaseIterable, Identifiable, Sendable {
    case containers, images, compose, networks, volumes, tasks, overview, settings, logs

    var id: String { rawValue }

    /// The tab labels, verbatim. `搜索${label}` is built from these, which is why `Compose`
    /// carries no Chinese name.
    var label: String {
        switch self {
        case .containers: "容器"
        case .images: "镜像"
        case .compose: "Compose"
        case .networks: "网络"
        case .volumes: "数据卷"
        case .tasks: "任务"
        case .overview: "总览"
        case .settings: "设置"
        case .logs: "日志"
        }
    }

    /// `Container`, `Image`, `Workflow`, `Network`, `Database`, `Activity`, `Gauge`, `Settings2`,
    /// `FileText`.
    var symbol: String {
        switch self {
        case .containers: "shippingbox"
        case .images: "photo.on.rectangle.angled"
        case .compose: "flowchart"
        case .networks: LuckySymbol.network
        case .volumes: "externaldrive"
        case .tasks: "waveform.path.ecg"
        case .overview: LuckySymbol.dashboard
        case .settings: "gearshape.2"
        case .logs: LuckySymbol.logs
        }
    }

    /// The `SectionHeader` title, which is not the tab label for six of the nine.
    var title: String {
        switch self {
        case .containers: "容器"
        case .images: "镜像列表"
        case .compose: "Compose 项目"
        case .networks: "Docker 网络"
        case .volumes: "数据卷"
        case .tasks: "后台任务"
        case .overview: "Docker 总览"
        case .settings: "Docker 设置"
        case .logs: "Docker 日志"
        }
    }

    /// `dockerListViews` — the seven views rendered as a `FlatList` rather than a scroll view.
    static let listViews: [DockerView] = [
        .containers, .images, .compose, .networks, .volumes, .tasks, .logs,
    ]

    /// `isDockerListView(view)`.
    var isList: Bool { Self.listViews.contains(self) }

    /// `搜索${label}` — no space, and only for the six searchable lists.
    var searchPrompt: String? {
        switch self {
        case .containers, .images, .compose, .networks, .volumes, .tasks: "搜索\(label)"
        case .overview, .settings, .logs: nil
        }
    }

    /// `<EmptyState message>`; the two scrollable views have none.
    var emptyMessage: String {
        switch self {
        case .containers: "暂无容器"
        case .images: "暂无镜像"
        case .compose: "暂无 Compose 项目"
        case .networks: "暂无 Docker 网络"
        case .volumes: "暂无数据卷"
        case .tasks: "暂无后台任务"
        case .logs: "暂无 Docker 日志"
        case .overview, .settings: ""
        }
    }
}

/// §2's query keys, as a value. `containerStats` covers both the cached sweep and the live one —
/// they are refetched together and invalidated together, so one case is enough.
enum DockerQuery: Hashable, Sendable {
    case containers, images, compose, networks, volumes, tasks
    case overview, config, mirrors, maintenance, logs
    case containerStats, iconLibrary
}

// MARK: - 编辑器

/// Every `editor.type` the screen can open — §24.5's forty-three titles, keyed by the string the
/// original stores in `editor.type`.
///
/// Seven of these never reach the mutation: `containerFileDownload`, `imageFilesystemView`,
/// `composeDiscover`, `composeReadFile` and `composeBackupDownload` are intercepted by §19.2's save
/// handler and turn into a detail or a download, while `composeConfig` and `composeDockerfile` are
/// rewritten to their `-save` counterparts. `mutation` is where that mapping lives.
enum DockerEditorKind: String, Hashable, Sendable {
    case containerCreate = "container-create"
    case containerEdit = "container-edit"
    case containerUpgrade = "container-upgrade"
    case containerRename = "container-rename"
    case containerCopy = "container-copy"
    case containerCommit = "container-commit"
    case containerLabelSet = "container-label-set"
    case containerGroupSet = "container-group-set"
    case containerVersionSwitch = "container-version-switch"
    case containerFiles = "container-files"
    case containerFileDownload = "container-file-download"
    case containerFileUpload = "container-file-upload"
    case imagePull = "image-pull"
    case imageBuild = "image-build"
    case imageBuildGit = "image-build-git"
    case imageBuildZip = "image-build-zip"
    case imageImport = "image-import"
    case imageLoad = "image-load"
    case imageTag = "image-tag"
    case imagePush = "image-push"
    case imageFilesystemView = "image-filesystem-view"
    case composeDiscover = "compose-discover"
    case composeConfig = "compose-config"
    case composeDockerfile = "compose-dockerfile"
    case composeReadFile = "compose-read-file"
    case composeBackupDownload = "compose-backup-download"
    case composeBackupRestore = "compose-backup-restore"
    case composeBackupRemove = "compose-backup-remove"
    case composeBackupUpload = "compose-backup-upload"
    case composeRestore = "compose-restore"
    case networkCreate = "network-create"
    case volumeCreate = "volume-create"
    case volumeRestore = "volume-restore"
    case volumeBackupRemove = "volume-backup-remove"
    case volumeBackupUpload = "volume-backup-upload"
    case volumeImport = "volume-import"
    case configSave = "config-save"
    case groupCreate = "group-create"
    case groupUpdate = "group-update"
    case groupRemove = "group-remove"
    case mirrorAdd = "mirror-add"
    case mirrorRemove = "mirror-remove"
    case prune
}

extension DockerEditorKind {
    /// The mutation `type` a save produces, or `nil` when §19.2 handles the form itself.
    var mutation: DockerActionType? {
        switch self {
        case .containerFileDownload, .imageFilesystemView, .composeDiscover,
             .composeReadFile, .composeBackupDownload:
            return nil
        // The two rewrites: the form is `compose-config`, the mutation is `compose-config-save`.
        case .composeConfig: return .composeConfigSave
        case .composeDockerfile: return .composeDockerfileSave
        default: return DockerActionType(rawValue: rawValue)
        }
    }

    /// `mirror-remove` moves `value.mirror` into `key` and sends no `value` at all.
    var sendsFieldAsKey: String? { self == .mirrorRemove ? "mirror" : nil }
}

/// `EditorState` — the form `DockerFormEditor` is currently showing.
struct DockerEditorRequest: Identifiable, Hashable {
    var kind: DockerEditorKind
    var title: String
    var value: JSONValue
    var key: String?

    /// `key={`${editor.type}-${editor.key ?? "new"}`}`, which `.sheet(item:)` reuses as identity.
    var id: String { "\(kind.rawValue)-\(key ?? "new")" }

    init(_ kind: DockerEditorKind, title: String, value: JSONValue, key: String? = nil) {
        self.kind = kind
        self.title = title
        self.value = value
        self.key = key
    }
}

// MARK: - 详情浮层

/// `DetailState` — the read-only viewer that shows an inspect result, a scan report, or the receipt
/// of a download. `loading`, `value` and `error` are mutually exclusive in practice but not in the
/// type, exactly as in the original: a download sets `loading` **and** `status` together.
///
/// The title is the identity. Every flow that writes here writes two or three times under one
/// title — 正在下载 then the receipt, 正在检测 3/8 then the report — and `.sheet(item:)` re-presents
/// when the id changes, so a `UUID` would tear the sheet down and rebuild it on each of those.
struct DockerDetail: Identifiable, Hashable {
    var title: String
    var loading = false
    var status: String?
    var value: JSONValue?
    var error: String?

    var id: String { title }

    init(_ title: String, loading: Bool = false, status: String? = nil,
         value: JSONValue? = nil, error: String? = nil) {
        self.title = title
        self.loading = loading
        self.status = status
        self.value = value
        self.error = error
    }
}

// MARK: - 操作菜单

/// `containerMenu` — `name` is the daemon's raw name and may keep a leading `/`.
struct DockerContainerMenu: Identifiable, Hashable {
    var key: String
    var name: String
    var running: Bool
    var paused: Bool

    var id: String { key }

    /// `name.replace(/^\/+/, "")` — what the two payloads and the export filename use.
    var bareName: String {
        var trimmed = Substring(name)
        while trimmed.first == "/" { trimmed = trimmed.dropFirst() }
        return String(trimmed)
    }
}

/// `imageMenu`.
struct DockerImageMenu: Identifiable, Hashable {
    var key: String
    var name: String

    var id: String { key }

    /// `name !== "<none>" ? name.split(",")[0] : key` — the reference a delete is keyed by.
    var deleteKey: String {
        guard name != "<none>" else { return key }
        return name.components(separatedBy: ",").first ?? key
    }
}

/// `{ completed, total }` — the batch counters the image flows and the delete button print.
struct DockerProgress: Hashable, Sendable {
    var completed = 0
    var total = 0
}

// MARK: - Compose 创建

/// `composeProgress` — the running commentary of a `compose-create`, rebuilt from every task poll.
struct DockerComposeProgress: Hashable, Sendable {
    var taskId: String
    var status = ""
    var message: String
    /// `undefined` when the payload carried no finite number, which is what hides the bar.
    var progress: Double?

    /// The literal message, for the two states that have no task payload yet.
    init(taskId: String = "", message: String) {
        self.taskId = taskId
        self.message = message
        self.progress = nil
    }

    /// `composeTaskProgress(payload, taskId)`.
    init(_ payload: JSONValue, taskId: String) {
        self.taskId = taskId
        status = (DockerRecord.deepScalar(payload, ["status", "state"])?.asDisplayString ?? "")
            .jsTrimmed
        let text = (DockerRecord.deepScalar(payload, ["message", "output", "error"])?
            .asDisplayString ?? "").jsTrimmed
        if !text.isEmpty {
            message = text
        } else if !status.isEmpty {
            message = "任务状态：\(status)"
        } else {
            message = "正在创建 Compose 项目"
        }
        // `Number(undefined)` is NaN, so a payload missing all three keys leaves the bar off.
        let raw = DockerComposeProgress.jsNumber(
            DockerRecord.deepScalar(payload, ["progress", "percent", "percentage"])
        )
        progress = raw.isFinite ? min(100, max(0, raw)) : nil
    }

    /// `Number(value)` over the three scalar cases `deepScalar` can return.
    private static func jsNumber(_ value: JSONValue?) -> Double {
        switch value {
        case .number(let number): return number
        case .string(let text): return JSCompat.number(text)
        case .bool(let flag): return flag ? 1 : 0
        default: return .nan
        }
    }
}

/// `composeCreate` — the five fields of §19.3's creator, which is its own modal rather than one of
/// `DockerFormEditor`'s generated forms.
struct DockerComposeCreateValue: Hashable, Sendable {
    var projectName = ""
    var workingDirectory = ""
    var configFileName = "compose.yaml"
    var composeContent = DockerComposeCreateValue.template
    var build = false

    /// `defaultComposeTemplate` — verbatim, trailing newline included.
    static let template = """
        services:
          app:
            image: nginx:alpine
            container_name: lucky-compose-app
            restart: unless-stopped
            ports:
              - "8080:80"

        """

    /// One megabyte, the ceiling both the file import and the submit check enforce.
    static let contentLimit = 1024 * 1024

    /// `/\\.ya?ml$/i` — the only two extensions the daemon will write.
    static func isYAMLName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasSuffix(".yml") || lowered.hasSuffix(".yaml")
    }

    /// The outcome of `submit()`: either the normalised value, or the message to show.
    enum Validation {
        case ok(DockerComposeCreateValue)
        case failed(String)
    }

    /// `submit()` — the creator's own validation, whose copy differs from the mutation's even where
    /// the check is the same.
    func validated() -> Validation {
        var next = self
        next.projectName = projectName.jsTrimmed
        next.workingDirectory = workingDirectory.jsTrimmed
        next.configFileName = configFileName.jsTrimmed
        if next.workingDirectory.isEmpty { return .failed("请输入工作目录") }
        if next.configFileName.isEmpty { return .failed("请输入配置文件名") }
        if next.configFileName.contains("/") || next.configFileName.contains("\\")
            || !Self.isYAMLName(next.configFileName) {
            return .failed("配置文件名必须是 .yml 或 .yaml 文件名，不能包含路径")
        }
        let trimmedContent = composeContent.jsTrimmed
        if trimmedContent.isEmpty { return .failed("请输入 Compose YAML 内容") }
        if trimmedContent.count > Self.contentLimit { return .failed("Compose 内容不能超过 1 MB") }
        // The content itself is sent untrimmed — only the three names are normalised.
        return .ok(next)
    }

    /// The `value` the mutation reads, with the form's own names mapped onto the daemon's.
    var payload: JSONValue {
        .object([
            ("project_name", .string(projectName)),
            ("working_dir", .string(workingDirectory)),
            ("config_file_name", .string(configFileName)),
            ("compose_content", .string(composeContent)),
            ("build", .bool(build)),
        ])
    }
}
