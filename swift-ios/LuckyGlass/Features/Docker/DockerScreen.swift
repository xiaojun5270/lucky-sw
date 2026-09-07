import SwiftUI

/// The upload a picker is about to produce.
///
/// `.fileImporter` is boolean-presented and hands back only a `URL`, so the type, title, key and
/// pre-filled fields that `chooseDockerArchive` / `chooseDockerUpload` already knew have to wait
/// here until the pick returns.
///
/// `fileFirst` is the one difference between the two: the archive picker writes `file_name` and
/// `file_uri` *before* the form's own fields, the upload picker after them. `JSONObject` keeps
/// insertion order, so the form draws its rows in whichever order the original produced.
struct DockerPick {
    var kind: DockerEditorKind
    var title: String
    var key: String?
    var fields: JSONObject
    var fileFirst: Bool

    /// §9's two failure messages. The archive picker is exactly the pair that writes the file keys
    /// first, so the same flag chooses the copy.
    var failure: String { fileFirst ? "选择文件失败" : "选择上传文件失败" }
}

/// `app/docker.tsx` — 容器、镜像、Compose、网络、数据卷、任务、总览、设置 与 日志, in one screen.
///
/// The original is a single 3,500-line component: nine views behind one tab bar, fourteen queries,
/// one mutation with sixty-one arms, six overlays and forty-three generated forms. Here the value
/// types live in `DockerScreenModel.swift`, the payload readers in `DockerRecord.swift`, the
/// mutation in `DockerAction.swift` and each view in a file of its own; this file is the shell —
/// state, layout and the branch.
struct DockerScreen: View {
    /// `useIsFocused()` + `AppState`: `.task` is cancelled when the screen is popped, and the scene
    /// phase covers backgrounding. Every one of the four polling queries is gated on both.
    ///
    /// None of the state below is `private`, and it is the only screen in the port where that is
    /// true: `private` in Swift is file-scoped, and this screen's selectors, loaders, actions and
    /// nine views live in files of their own. Anything they read has to be at least internal.
    @Environment(\.scenePhase) var phase

    @State var view: DockerView
    @State var search: String
    @State var logPage = 1
    /// `output` — §18's Mode A payload: a container's log dump or a file listing, shown instead of
    /// the paged daemon log. `""` in the original, `nil` here.
    @State var output: JSONValue?

    // MARK: 查询结果

    @State var containers: [LuckyListItem] = []
    @State var icons: [JSONValue] = []
    @State var images: [LuckyListItem] = []
    @State var projects: [LuckyListItem] = []
    @State var networks: [LuckyListItem] = []
    @State var volumes: [LuckyListItem] = []
    @State var tasks: [LuckyListItem] = []
    @State var overview: DockerOverview?
    @State var config: JSONValue?
    @State var mirrors: JSONValue?
    @State var maintenance: JSONValue?
    @State var logPayload: JSONValue?

    /// The three stats payloads §3 feeds to `dockerStatRows` as one array: the five-second cached
    /// sweep, the fifteen-second live one, and the partial results the live sweep streams while it
    /// is still running.
    @State var stats: JSONValue?
    @State var liveStats: JSONValue?
    @State var progressiveStats: JSONValue?
    /// `containerStats.isSuccess` / `.error` / `.isLoading`, which §16 and §6 read separately.
    @State var statsSucceeded = false
    @State var statsFailed = false
    @State var statsLoading = false
    @State var liveStatsFailure = ""
    @State var liveStatsLoading = false

    /// react-query keeps one error per query, so a single string would print the containers failure
    /// over the settings view. Each query keeps its own.
    @State var queryFailures: [DockerQuery: String] = [:]
    @State var loaded: Set<DockerQuery> = []
    @State var fetching = false
    @State var maintenanceFetching = false

    // MARK: 浮层

    @State var editor: DockerEditorRequest?
    @State var composeCreatorOpen = false
    @State var composeProgress: DockerComposeProgress?
    @State var detail: DockerDetail?
    @State var containerMenu: DockerContainerMenu?
    @State var imageMenu: DockerImageMenu?
    @State var imageToolsOpen = false
    /// `dockerUpload` — the picked file, held until its form is saved or dismissed.
    @State var upload: DockerAsset?
    @State var pick: DockerPick?
    @State var picking = false

    // MARK: 镜像批量

    @State var selectionMode = false
    @State var selectedImageIds: [String] = []
    @State var imageUpgradeChecking = false
    @State var unusedScanChecking = false
    @State var unusedScanProgress: DockerProgress?
    @State var imageDeleteProgress: DockerProgress?
    /// `unusedImageScanRequestRef` — a scan the user walked away from still returns, and a partial
    /// report has to be dropped rather than applied to a selection that no longer exists.
    @State var scanRequest = 0
    /// `unusedImageScanAbortRef` / `imageUpgradeAbortRef`: leaving 批量操作 cancels the unused-image
    /// scan, and closing the detail viewer cancels the upgrade check.
    @State var scanTask: Task<Void, Never>?
    @State var upgradeTask: Task<Void, Never>?

    // MARK: 其它

    /// `mutation.variables?.type` — the type itself and not a flag, because §11's delete button
    /// prints its own progress while every other control merely dims.
    @State var running: DockerActionType?
    @State var confirmation: ServiceConfirmation?
    @State var localError = ""
    @State var localNotice = ""
    @State var toast: LuckyToast?
    /// `detailRequestRef` — §25.16's monotonic id. Every async write into `detail` carries the id
    /// it started with and is dropped if the id has moved on.
    @State var detailRequest = 0

    /// `LuckyRoute.docker(view:search:)` — 总览 links here with a view already chosen, and the
    /// container rankings link here with a name already in the search box.
    init(initialView: String = "", initialSearch: String = "") {
        _view = State(initialValue: DockerView(rawValue: initialView) ?? .containers)
        _search = State(initialValue: initialSearch)
    }

    var body: some View {
        chrome
            .task(id: view) { await loadView() }
            .task(id: statsTaskID) { await pollStats() }
            .task(id: liveStatsTaskID) { await pollLiveStats() }
            .task(id: overviewActive) { await pollOverview() }
            .task(id: logsTaskID) { await pollLogs() }
    }
}

// MARK: - 外壳

extension DockerScreen {
    /// The screen and its six overlays. `<Page title="Docker">`'s own title comes from
    /// `LuckyRoute.docker`, applied by the pushing stack; the subtitle slot in the navigation bar
    /// is where the pair belongs.
    private var chrome: some View {
        searchable
            .navigationSubtitle("容器、镜像与 Compose 管理")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: LuckySymbol.refresh)
                    }
                    .disabled(pageRefreshing)
                    .accessibilityLabel("刷新")
                }
            }
            .luckyToast($toast)
            // §6's `danger(title, message, action)`: every one of the twenty-one Docker
            // confirmations is 取消 / 继续, with 继续 destructive.
            .alert(confirmation?.title ?? "", isPresented: confirming,
                   presenting: confirmation) { request in
                Button("取消", role: .cancel) {}
                Button(request.confirm, role: request.destructive ? .destructive : nil) {
                    request.perform()
                }
            } message: { request in
                Text(request.message)
            }
            .sheet(item: $editor, onDismiss: { dismissEditor() }) { request in
                editorSheet(request)
            }
            .sheet(isPresented: $composeCreatorOpen,
                   onDismiss: { closeComposeCreator() }) { composeCreatorSheet }
            .sheet(item: $detail, onDismiss: { dismissDetail() }) { request in
                detailSheet(request)
            }
            .sheet(item: $containerMenu) { menu in containerMenuSheet(menu) }
            .sheet(item: $imageMenu) { menu in imageMenuSheet(menu) }
            .sheet(isPresented: $imageToolsOpen) { imageToolsSheet }
            // Expo's picker takes a MIME list per call site; `UTType` cannot express
            // `application/x-zip-compressed` without a declaring app, so the filter is `.item` and
            // the daemon rejects a wrong archive as it would a wrong one that passed the filter.
            .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { result in
                receive(result)
            }
    }

    /// `<SearchField>` exists for six of the nine views. Only `shell` is inside the branch, so the
    /// subtitle, the toolbar, the overlays and the five tasks all survive the subtree swap.
    @ViewBuilder
    private var searchable: some View {
        if let prompt = view.searchPrompt {
            shell
                .searchable(text: $search, prompt: prompt)
                .searchToolbarBehavior(.minimize)
        } else {
            shell
        }
    }

    /// `<Page scrollable={!isDockerListView}>`: the tab picker and the error cards stay pinned and
    /// only the branch scrolls. §25.15 has all of it inside the list header, which cannot be done
    /// here — glass may not sit in scrolling content — so the primary verb of each view moves into
    /// the bottom bar instead, as on every other screen in this port.
    @ViewBuilder
    fileprivate var shell: some View {
        if hasActionBar {
            frame.luckyActionBar { actionBar }
        } else {
            frame
        }
    }

    private var frame: some View {
        ZStack {
            LuckyBackdrop()
            VStack(spacing: 0) {
                header
                branch
            }
        }
    }
}

// MARK: - 导航栏

extension DockerScreen {
    /// §6's `renderDockerNavigation`, minus the two pieces the navigation bar now owns: the
    /// nine-tab `ResponsiveTabBar`, then the four notices — all of which can show at once, and in
    /// this order.
    private var header: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.m) {
            LuckyGlassMenuPicker(
                title: "视图",
                selection: viewSelection,
                segments: DockerView.allCases.map {
                    LuckySegment($0, $0.label, symbol: $0.symbol)
                }
            )
            if !localError.isEmpty {
                LuckyErrorCard(message: localError)
            }
            if !localNotice.isEmpty {
                noticePill
            }
            if let failure = queryFailures[activeQuery], !failure.isEmpty {
                LuckyErrorCard(message: failure) { Task { await refresh() } }
            }
            // The live sweep failed *and* the cached one has nothing to show. Its retry runs both,
            // because either one succeeding is enough to fill the grid.
            if containerStatRows.isEmpty, liveStatsNeeded, !liveStatsFailure.isEmpty {
                LuckyErrorCard(message: "容器统计暂时不可用") {
                    Task { await refreshStats() }
                }
            }
        }
        .padding(.horizontal, LuckyTheme.Space.gutter)
        .padding(.bottom, LuckyTheme.Space.m)
    }

    /// The success-tinted pill §6 prints for `localNotice` — the batch-scan summaries and the two
    /// Compose-create messages. Not an `ErrorState`: it is the same shape in the success colour.
    private var noticePill: some View {
        Text(localNotice)
            .font(LuckyTheme.Text.captionMedium)
            .foregroundStyle(LuckyTheme.success)
            .padding(.horizontal, LuckyTheme.Space.m)
            .padding(.vertical, LuckyTheme.Space.s)
            .frame(minHeight: 40, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LuckyTheme.successSoft, in: .rect(cornerRadius: 10))
    }

    /// §6's `selectDockerView(key)`. Leaving a view clears the search box and the log drawer;
    /// arriving at 日志 also rewinds the pager. The original does all three in the tab's `onSelect`.
    private var viewSelection: Binding<DockerView> {
        Binding(get: { view }, set: { next in
            search = ""
            output = nil
            if next == .logs { logPage = 1 }
            view = next
        })
    }
}

// MARK: - 底部操作栏

extension DockerScreen {
    /// 总览 has no verb of its own and 设置 keeps all four of its CTAs inside their own cards, so
    /// neither takes a bar; 日志 takes one only while it is paging the daemon log.
    private var hasActionBar: Bool {
        switch view {
        case .containers, .images, .compose, .networks, .volumes, .tasks: true
        case .logs: output == nil
        case .overview, .settings: false
        }
    }

    /// The primary verb of each view, lifted out of the list header. Its six secondary verbs — 构建,
    /// 扫描项目, 导入数据卷, 镜像高级工具, 升级状态, 批量操作 — stay in the scroll as
    /// `ServiceActionButton`s, which is the non-glass twin of this control.
    @ViewBuilder
    private var actionBar: some View {
        switch view {
        case .containers:
            LuckyPillButton(title: "创建容器", symbol: LuckySymbol.add, prominent: true) {
                openEditor(.containerCreate, title: "创建容器", value: .object([
                    ("name", .string("")), ("image", .string("")), ("config", .object([])),
                ]))
            }
        // §11's label is `拉取` and its glyph is `UploadCloud`; `拉取镜像` is the editor's title.
        case .images:
            LuckyPillButton(title: "拉取", symbol: "icloud.and.arrow.up", prominent: true) {
                openEditor(.imagePull, title: "拉取镜像", value: .object([
                    ("image", .string("")), ("tag", .string("latest")),
                    ("architecture", .string("")),
                ]))
            }
        case .compose:
            LuckyPillButton(title: "创建 Compose", symbol: LuckySymbol.add, prominent: true) {
                openComposeCreator()
            }
            .disabled(pending)
        case .networks:
            LuckyPillButton(title: "创建网络", symbol: LuckySymbol.add, prominent: true) {
                openEditor(.networkCreate, title: "创建网络", value: .object([
                    ("Name", .string("")), ("Driver", .string("bridge")),
                    ("Options", .object([])), ("IPAM", .object([])),
                ]))
            }
        case .volumes:
            LuckyPillButton(title: "创建数据卷", symbol: LuckySymbol.add, prominent: true) {
                openEditor(.volumeCreate, title: "创建数据卷", value: .object([
                    ("Name", .string("")), ("Driver", .string("local")),
                    ("DriverOpts", .object([])), ("Labels", .object([])),
                ]))
            }
        case .tasks:
            LuckyPillButton(title: "清空任务", symbol: LuckySymbol.delete, tone: .danger,
                            prominent: true) {
                danger("清空任务", "删除全部 Docker 任务记录？") { run(DockerMutation(.tasksClear)) }
            }
        case .logs:
            logPager
        case .overview, .settings:
            EmptyView()
        }
    }

    /// §18's footer pager. There is no total: a full page is exactly 200 lines, so a short page is
    /// the last one (§25.5). The original stacks `ChevronUp` / `ChevronDown`; a horizontal bar
    /// wants horizontal chevrons, so it gets them here.
    @ViewBuilder
    private var logPager: some View {
        LuckyGlassIconButton(symbol: "chevron.left", label: "上一页 Docker 日志") {
            logPage = max(1, logPage - 1)
        }
        .disabled(logPage <= 1 || fetching)
        Text("第 \(logPage) 页")
            .font(LuckyTheme.Text.caption)
            .foregroundStyle(LuckyTheme.textSecondary)
            .monospacedDigit()
            .frame(minWidth: 82, maxWidth: .infinity)
        LuckyGlassIconButton(symbol: "chevron.right", label: "下一页 Docker 日志") {
            logPage += 1
        }
        .disabled(fetching || logLines.count < DockerScreen.logPageSize)
    }
}
