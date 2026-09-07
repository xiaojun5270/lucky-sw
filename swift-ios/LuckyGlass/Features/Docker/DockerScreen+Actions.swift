import SwiftUI

/// `inspect(kind, key)` — the three read-only lookups that open the detail viewer, with the titles
/// §7 gives them.
enum DockerInspect: Sendable {
    case container, image, task

    var title: String {
        switch self {
        case .container: "容器详情"
        case .image: "镜像详情"
        case .task: "任务详情"
        }
    }
}

// MARK: - 确认与浮层

extension DockerScreen {
    /// §6's `danger(title, message, action)` — 取消 / 继续 with 继续 destructive, which is what all
    /// twenty-one of this screen's confirmations are.
    func danger(_ title: String, _ message: String, _ action: @escaping () -> Void) {
        confirmation = ServiceConfirmation(title: title, message: message, confirm: "继续",
                                          perform: action)
    }

    /// Every `setEditor({ type, title, key, value })` call site.
    func openEditor(_ kind: DockerEditorKind, title: String, value: JSONValue,
                    key: String? = nil) {
        editor = DockerEditorRequest(kind, title: title, value: value, key: key)
    }

    /// The second half of `DockerFormEditor`'s `close`: seven of the forty-three forms are holding
    /// a picked file, and dismissing one of those releases it.
    ///
    /// That list is exactly `DockerActionType.clearsUpload`, so it is read through there rather
    /// than written out a second time.
    func releaseUpload(for kind: DockerEditorKind) {
        guard kind.mutation?.clearsUpload == true else { return }
        upload = nil
    }

    /// §12's 创建 Compose. `mutation.reset()` clears the error the creator reads, which here is
    /// `localError`: the sheet is the only thing that can be on screen while a `compose-create`
    /// runs, so the screen's own error slot doubles as the sheet's.
    func openComposeCreator() {
        localError = ""
        localNotice = ""
        composeProgress = nil
        composeCreatorOpen = true
    }

    /// §19.1's `close()`. A create still in flight is deliberately left running — the sheet merely
    /// goes away, and says so.
    func closeComposeCreator() {
        if running == .composeCreate {
            composeCreatorOpen = false
            localNotice = "Compose 创建任务正在后台执行"
            return
        }
        composeProgress = nil
        composeCreatorOpen = false
    }

    /// §19.1's `save(value)` — camelCase in the form, snake_case on the wire.
    func createCompose(_ value: DockerComposeCreateValue) {
        run(DockerMutation(.composeCreate, value: value.payload))
    }
}

// MARK: - 变更

extension DockerScreen {
    /// `mutation.mutate(variables)` — fire and forget, which is what all sixty-one call sites do,
    /// and what lets a `ViewBuilder` closure dispatch one.
    func run(_ mutation: DockerMutation) {
        Task { await perform(mutation) }
    }

    /// `onMutate` → `mutationFn` → `onSuccess` / `onError`, in one function.
    private func perform(_ mutation: DockerMutation) async {
        localError = ""
        localNotice = ""
        if mutation.type == .composeCreate { composeProgress = nil }
        // The batch delete prints 完成 n/total from its first frame, so the total is known before
        // the sweep begins. Every other type clears whatever the last one left behind.
        imageDeleteProgress = mutation.type == .imagesRemoveBatch
            ? DockerProgress(total: mutation.value?["ids"]?.arrayValue?.count ?? 0)
            : nil
        running = mutation.type
        do {
            let result = try await runner.run(mutation)
            running = nil
            await succeeded(mutation, result)
        } catch {
            running = nil
            failed(mutation, error)
        }
    }

    /// The runner, with the held upload and the four sinks it writes through. `State` is `Sendable`
    /// and its setter is nonmutating, so each box crosses into a `@Sendable` callback where `self`
    /// — which `ServiceConfirmation`'s plain closure keeps non-`Sendable` — could not.
    private var runner: DockerActionRunner {
        let deleteSink = _imageDeleteProgress
        let composeSink = _composeProgress
        let taskSink = _tasks
        let loadedSink = _loaded
        return DockerActionRunner(
            upload: upload,
            onImageDelete: { progress in
                Task { @MainActor in deleteSink.wrappedValue = progress }
            },
            onCompose: { progress in
                Task { @MainActor in composeSink.wrappedValue = progress }
            },
            onComposeTaskSubmitted: {
                // `invalidateQueries(["docker","tasks"])` the moment the task id arrives. The
                // original refetches only a mounted 任务 list; reading it unconditionally costs one
                // request and behaves identically on screen, and is needed because the creator
                // sheet can be dismissed mid-flight and 任务 opened while the task still runs.
                Task { @MainActor in
                    guard let list = try? await DockerService.tasks() else { return }
                    taskSink.wrappedValue = list.items
                    loadedSink.wrappedValue.insert(.tasks)
                }
            }
        )
    }

    /// `onSuccess`. The notice is written before the refetch is awaited, because the original fires
    /// its invalidations with `void` and never waits for them.
    private func succeeded(_ mutation: DockerMutation, _ result: JSONValue) async {
        editor = nil
        if mutation.type == .composeCreate {
            composeCreatorOpen = false
            composeProgress = nil
        }
        if mutation.type.clearsUpload { upload = nil }
        localError = ""
        imageDeleteProgress = nil
        switch mutation.type {
        // §21's `container-files` is the one write whose result is worth reading, so it opens the
        // detail viewer on the way out.
        case .containerFiles:
            detail = DockerDetail("文件操作结果", value: result)
            localNotice = mutation.type.notice
        case .imagesRemoveBatch:
            // The failures stay selected so a retry needs no re-picking; a clean sweep leaves both
            // the selection and 批量操作 behind.
            let outcome = DockerActionRunner.batchOutcome(result)
            selectedImageIds = outcome.failedIds
            selectionMode = !outcome.failedIds.isEmpty
            localNotice = outcome.notice
        default:
            localNotice = mutation.type.notice
        }
        await invalidate(mutation.type)
    }

    /// `onError`.
    private func failed(_ mutation: DockerMutation, _ error: Error) {
        localNotice = ""
        imageDeleteProgress = nil
        if mutation.type == .composeCreate {
            composeProgress = nil
            // `variables.signal?.aborted` — a create the user cancelled reports nothing at all.
            if error.isCancellation { return }
        }
        localError = error.luckyMessage()
    }
}

// MARK: - 详情与下载

extension DockerScreen {
    /// §7's `closeDetail`. The request id moves on, so any write still in flight is dropped, and
    /// the upgrade sweep — the one detail read worth abandoning early — is cancelled with it.
    func closeDetail() {
        detailRequest += 1
        upgradeTask?.cancel()
        upgradeTask = nil
        detail = nil
    }

    /// The sheet's `onDismiss`. A swipe or a tap on 关闭 leaves the binding nil, which is the real
    /// dismissal; replacing one request with another under a different title would leave it holding
    /// the new one, and must not bump the id that new request is waiting on.
    func dismissDetail() {
        guard detail == nil else { return }
        closeDetail()
    }

    /// §7's `openDetail(title, request)`. `detailRequestRef` is monotonic and **every** async write
    /// is guarded by the id it started with, so a slow read that lands after the sheet was closed —
    /// or after a second read replaced it — writes nothing.
    func openDetail(_ title: String, _ request: () async throws -> JSONValue) async {
        detailRequest += 1
        let id = detailRequest
        detail = DockerDetail(title, loading: true)
        do {
            let value = try await request()
            guard detailRequest == id else { return }
            detail = DockerDetail(title, value: value)
        } catch {
            guard detailRequest == id else { return }
            detail = DockerDetail(title, error: error.luckyMessage("读取详情失败"))
        }
    }

    /// §7's `downloadDockerResource`. The `nativePath` / `nativeMethod` branch is gone: it existed
    /// to hand a path to expo-file-system so the bytes never entered JS, and every `DockerService`
    /// download here already returns them as `.binary`. `DockerFile.save` writes into Documents —
    /// iOS has no counterpart to the Android `pickDirectoryAsync` branch — and returns the receipt
    /// the viewer prints.
    func download(_ title: String, as fallback: String,
                  _ request: () async throws -> JSONValue) async {
        detailRequest += 1
        let id = detailRequest
        detail = DockerDetail(title, loading: true, status: "正在下载")
        do {
            let payload = try await request()
            let value = try DockerFile.save(payload, fallback: fallback)
            guard detailRequest == id else { return }
            detail = DockerDetail(title, value: value)
        } catch {
            guard detailRequest == id else { return }
            detail = DockerDetail(title, error: error.luckyMessage("下载失败"))
        }
    }

    /// §7's `inspect(kind, key)`.
    func inspect(_ kind: DockerInspect, _ key: String) async {
        await openDetail(kind.title) {
            switch kind {
            case .container: return try await DockerService.container(key)
            case .image: return try await DockerService.image(key)
            case .task: return try await DockerService.task(key)
            }
        }
    }
}

// MARK: - 读取后打开

extension DockerScreen {
    /// §7's `containerLogs`. A container's dump goes into §18's Mode A pane, which is why it jumps
    /// to 日志 rather than opening the detail viewer. Alone among these six it does *not* clear the
    /// notice first, so a preceding 操作已完成 survives the jump — as in the original.
    func containerLogs(_ key: String) async {
        do {
            output = try await DockerService.containerLogs(key)
            logPage = 1
            view = .logs
        } catch {
            localError = error.luckyMessage("读取日志失败")
        }
    }

    /// §12's 日志 verb. `{ tail: 200 }` is a body field here, not an argument.
    func composeLogs(_ name: String) async {
        localError = ""
        localNotice = ""
        do {
            output = try await DockerService.composeLogs(name, .object([("tail", .int(200))]))
            logPage = 1
            view = .logs
        } catch {
            localError = error.luckyMessage("读取 Compose 日志失败")
        }
    }

    /// §12's 配置 verb. An empty read is a failure, not an empty editor — the daemon answers 200 with
    /// no content when the project path is not bind-mounted, the case `composeProjectError`
    /// rewrites into the mount instruction.
    func editComposeConfig(_ projectPath: String) async {
        localError = ""
        localNotice = ""
        do {
            let result = try await DockerService.readComposeConfig(projectPath: projectPath)
            let content = DockerRecord.composeConfigText(result)
            guard !content.isEmpty else { throw LuckyError("接口未返回 Compose 配置内容") }
            openEditor(.composeConfig, title: "编辑 Compose 配置", value: .object([
                ("project_path", .string(projectPath)), ("content", .string(content)),
            ]), key: projectPath)
        } catch {
            localError = DockerRecord.composeProjectError(error.luckyMessage(),
                                                          projectPath: projectPath)
        }
    }

    /// §12's Dockerfile verb — the same shape, without the path rewrite.
    func editComposeDockerfile(_ projectPath: String) async {
        localError = ""
        localNotice = ""
        do {
            let result = try await DockerService.readComposeDockerfile(projectPath: projectPath)
            let content = DockerRecord.composeConfigText(result)
            guard !content.isEmpty else { throw LuckyError("接口未返回 Dockerfile 内容") }
            openEditor(.composeDockerfile, title: "编辑 Dockerfile", value: .object([
                ("project_path", .string(projectPath)), ("content", .string(content)),
            ]), key: projectPath)
        } catch {
            localError = error.luckyMessage("读取 Dockerfile 失败")
        }
    }

    /// §10's 编辑 verb: the container's own configuration, dug out of the inspect payload.
    func editContainer(_ key: String) async {
        do {
            let result = try await DockerService.container(key)
            openEditor(.containerEdit, title: "编辑容器",
                       value: .object(DockerRecord.nested(result, ["container", "data"])),
                       key: key)
        } catch {
            localError = error.luckyMessage("读取容器配置失败")
        }
    }

    /// §10's 更新 verb. The upgrade check answers with the daemon's envelope wrapped around the new
    /// configuration, so the two envelope fields come off before the form sees it.
    func updateContainer(_ key: String, _ name: String) async {
        localError = ""
        do {
            let result = try await DockerService.checkContainerUpgrade(key)
            var value = DockerRecord.nested(result, ["config", "upgrade", "result", "data"])
            value.removeValue(forKey: "ret")
            value.removeValue(forKey: "msg")
            openEditor(.containerUpgrade, title: "更新容器 \(name)", value: .object(value), key: key)
        } catch {
            localError = error.luckyMessage("检查容器更新失败")
        }
    }
}

// MARK: - 镜像批量

extension DockerScreen {
    /// §11's row checkbox. A tap during any pending work is ignored rather than queued.
    func toggleImage(_ id: String) {
        guard !imageActionBusy else { return }
        if let index = selectedImageIds.firstIndex(of: id) {
            selectedImageIds.remove(at: index)
        } else {
            selectedImageIds.append(id)
        }
    }

    /// §11's 批量操作 toggle. Leaving the mode drops the selection and cancels a running scan; the
    /// upgrade check is not cancelled here — it merely blocks the toggle while it runs.
    func toggleSelectionMode() {
        guard !pending, !imageUpgradeChecking else { return }
        if unusedScanChecking {
            scanRequest += 1
            scanTask?.cancel()
            scanTask = nil
        }
        if selectionMode { selectedImageIds = [] }
        selectionMode.toggle()
    }

    /// §11's 全选 / 取消全选, over the *visible* rows only.
    ///
    /// JS `Set` iterates in insertion order, so the array the original produces keeps the order its
    /// ids were added in — which a Swift `Set` would not. The stale-id pruning happens here too,
    /// exactly as `current.filter(id => imageIdSet.has(id))` does.
    func toggleVisibleImages() {
        guard !imageActionBusy, !visibleImageIds.isEmpty else { return }
        var next = validSelectedImageIds
        if allVisibleImagesSelected {
            let visible = Set(visibleImageIds)
            next.removeAll { visible.contains($0) }
        } else {
            let present = Set(next)
            next.append(contentsOf: visibleImageIds.filter { !present.contains($0) })
        }
        selectedImageIds = next
    }

    /// §8's 选择未使用. The sweep asks the daemon, one image at a time, whether anything still
    /// references it; its progress drives §11's 正在检查 pill.
    ///
    /// `unusedImageScanRunningRef` has no counterpart: `@State` on the main actor reads back what
    /// it was just given, so `unusedScanChecking` is already the synchronous guard the ref was
    /// added to be. The request counter survives, because a cancelled sweep can still return a
    /// partial report rather than throwing.
    func selectUnusedImages() {
        guard !imageActionBusy, !unusedScanChecking, !visibleImageIds.isEmpty else { return }
        scanRequest += 1
        let id = scanRequest
        let targets = visibleImageIds
        unusedScanChecking = true
        localError = ""
        localNotice = ""
        unusedScanProgress = DockerProgress(total: targets.count)
        scanTask = Task { await runScan(targets, id) }
    }

    private func runScan(_ targets: [String], _ id: Int) async {
        defer {
            unusedScanChecking = false
            unusedScanProgress = nil
            scanTask = nil
        }
        let progressSink = _unusedScanProgress
        let requestSink = _scanRequest
        let fallback = targets.count
        do {
            let report = try await DockerService.scanUnusedImages(targets) { progress in
                Task { @MainActor in
                    guard requestSink.wrappedValue == id else { return }
                    let reported = progress["totalCount"]?.asInt ?? 0
                    progressSink.wrappedValue = DockerProgress(
                        completed: progress["completedCount"]?.asInt ?? 0,
                        total: reported == 0 ? fallback : reported
                    )
                }
            }
            guard scanRequest == id else { return }
            applyScan(report)
        } catch {
            guard scanRequest == id else { return }
            localError = error.luckyMessage("检查镜像使用情况失败")
        }
    }

    /// The report's three counts. A sweep where everything failed prints the first failure's own
    /// message instead of a summary, because 已选择 0 个未使用镜像，0 个正在使用 would read as a
    /// clean result.
    private func applyScan(_ report: JSONValue) {
        let known = imageIdSet
        let unused = (report["unused"]?.list ?? [])
            .map(\.asDisplayString)
            .filter { known.contains($0) }
        let used = report["usedCount"]?.asInt ?? 0
        let failed = report["failedCount"]?.asInt ?? 0
        selectedImageIds = unused
        if unused.isEmpty, used == 0, failed > 0 {
            let first = report["failed"]?.list.first?["error"]?.asDisplayString ?? ""
            localError = first.isEmpty ? "未能确认镜像使用情况" : first
            return
        }
        let suffix = failed > 0 ? "，\(failed) 个无法确认" : ""
        localNotice = "已选择 \(unused.count) 个未使用镜像，\(used) 个正在使用\(suffix)"
    }

    /// §8's 检测升级. Only the **first** tag of each selected image is checked — a `nginx` carrying
    /// four tags is one registry round-trip, not four — and duplicates collapse in first-seen
    /// order.
    func detectImageUpgrades() {
        guard !imageActionBusy else { return }
        localError = ""
        localNotice = ""
        var references: [String] = []
        for entry in imageEntries where selectedImageSet.contains(entry.id) {
            guard let first = entry.references.first, !first.isEmpty,
                  !references.contains(first) else { continue }
            references.append(first)
        }
        guard !references.isEmpty else {
            localError = validSelectedImageIds.isEmpty
                ? "请先选择需要检测的镜像"
                : "所选镜像没有可检测的标签"
            return
        }
        detailRequest += 1
        let id = detailRequest
        let title = "检测镜像升级 · \(references.count) 个主标签"
        imageUpgradeChecking = true
        detail = DockerDetail(title, loading: true, status: "正在检测 0/\(references.count)",
                              value: .object([
                                  ("completedCount", .int(0)),
                                  ("totalCount", .int(references.count)),
                                  ("checkedCount", .int(0)),
                                  ("failedCount", .int(0)),
                                  ("inProgress", .bool(true)),
                              ]))
        upgradeTask = Task {
            await runUpgradeSweep(references, title, id)
            // The original's `finally`, which runs even when the request id has moved on.
            imageUpgradeChecking = false
            upgradeTask = nil
            // The sweep records what it found in 维护状态, so 设置 has to read it again.
            await invalidate(keys: [.maintenance])
        }
    }

    /// The sweep, then the status read that follows it. Both are guarded by the request id, so
    /// closing the viewer mid-check leaves the screen alone.
    private func runUpgradeSweep(_ references: [String], _ title: String, _ id: Int) async {
        let detailSink = _detail
        let requestSink = _detailRequest
        let fallback = references.count
        let checked: JSONValue
        do {
            checked = try await DockerService.checkImagesUpgrade(references) { progress in
                Task { @MainActor in
                    guard requestSink.wrappedValue == id else { return }
                    let completed = progress["completedCount"]?.asInt ?? 0
                    let reported = progress["totalCount"]?.asInt ?? 0
                    let total = reported == 0 ? fallback : reported
                    detailSink.wrappedValue = DockerDetail(
                        title, loading: completed < total,
                        status: "正在检测 \(completed)/\(total)", value: progress
                    )
                }
            }
        } catch {
            guard detailRequest == id else { return }
            detail = DockerDetail(title, error: error.luckyMessage("检测镜像升级失败"))
            return
        }
        guard detailRequest == id else { return }
        detail = DockerDetail(title, loading: true, status: "正在读取升级状态", value: checked)
        var value = checked.record
        do {
            value["imageUpgrades"] = try await DockerService.imageUpgradeStatus()
        } catch {
            value["statusError"] = .string(error.luckyMessage("读取升级状态失败"))
        }
        guard detailRequest == id else { return }
        detail = DockerDetail(title, value: .object(value))
    }

    /// §11's 升级状态 — the stored result of an earlier sweep. Nothing is written, so unlike
    /// `detectImageUpgrades` this one does not invalidate 维护状态 on the way out, and it leaves the
    /// notice and error slots as it found them.
    func showImageUpgradeStatus() {
        guard !imageActionBusy else { return }
        detailRequest += 1
        let id = detailRequest
        let title = "镜像升级状态"
        imageUpgradeChecking = true
        detail = DockerDetail(title, loading: true, status: "正在读取升级状态")
        upgradeTask = Task {
            do {
                let upgrades = try await DockerService.imageUpgradeStatus()
                if detailRequest == id {
                    detail = DockerDetail(title, value: .object([("imageUpgrades", upgrades)]))
                }
            } catch {
                if detailRequest == id {
                    detail = DockerDetail(title, error: error.luckyMessage("读取升级状态失败"))
                }
            }
            imageUpgradeChecking = false
            upgradeTask = nil
        }
    }

    /// §8's 删除所选. The daemon skips images that are still in use, which the confirmation says out
    /// loud; the ones that fail stay selected afterwards (§20's `images-remove-batch` success arm).
    func removeSelectedImages() {
        guard !imageActionBusy else { return }
        let ids = validSelectedImageIds
        guard !ids.isEmpty else {
            localError = "请先选择要删除的镜像"
            return
        }
        danger("批量删除镜像", "确定删除已选择的 \(ids.count) 个镜像？正在使用的镜像会自动跳过。") {
            let payload = JSONValue.array(ids.map { JSONValue.string($0) })
            run(DockerMutation(.imagesRemoveBatch, value: .object([("ids", payload)])))
        }
    }
}

// MARK: - 文件选择

extension DockerScreen {
    /// §9's `chooseDockerArchive`. The two MIME lists are gone — `.fileImporter` takes `UTType`s
    /// and `application/x-zip-compressed` has no declaring app to borrow one from — so the sheet
    /// offers every file and the daemon rejects a wrong archive, as it would a wrong one that had
    /// passed a filter.
    func chooseArchive(_ kind: DockerEditorKind) {
        localError = ""
        pick = kind == .imageBuildZip
            ? DockerPick(kind: kind, title: "从 ZIP 构建镜像", key: nil, fields: JSONObject([
                ("tag", .string("")), ("dockerfile", .string("Dockerfile")),
                ("build_args", .object([])), ("no_cache", .bool(false)),
            ]), fileFirst: true)
            : DockerPick(kind: kind, title: "加载镜像归档", key: nil, fields: JSONObject(),
                         fileFirst: true)
        picking = true
    }

    /// §9's `chooseDockerUpload` — five call sites, each with its own title and pre-filled fields.
    func chooseUpload(_ kind: DockerEditorKind, key: String, title: String, fields: JSONObject) {
        localError = ""
        pick = DockerPick(kind: kind, title: title, key: key, fields: fields, fileFirst: false)
        picking = true
    }

    /// The `.fileImporter` completion. The picker is boolean-presented and hands back only a `URL`,
    /// so the kind, title, key and pre-filled fields waited in `pick` while it was up.
    ///
    /// `DockerAsset` holds bytes rather than a URL — `MultipartBody` needs them when the request is
    /// built, and the security-scoped URL will not still be open then — so the file is read here.
    /// A cancelled pick calls this with no `pick` pending and is dropped.
    func receive(_ result: Result<URL, Error>) {
        guard let request = pick else { return }
        pick = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let content = try Data(contentsOf: url)
            let name = url.lastPathComponent
            upload = DockerAsset(name: name, mimeType: DockerFile.mimeType(for: url),
                                 content: content)
            var fields = request.fields
            // §9's one derived field: an import with no name yet borrows the archive's, stripped of
            // its `.tar.gz` and of the `-backup-YYYYMMDD-HHMMSS` stamp 备份 adds.
            let named = fields["volume_name"]?.asDisplayString.jsTrimmed ?? ""
            if request.kind == .volumeImport, named.isEmpty {
                fields["volume_name"] = .string(DockerFile.volumeName(from: name))
            }
            // `JSONObject` keeps insertion order and the form draws its rows in that order, so the
            // two file keys go where the original's spread put them.
            var value = JSONObject()
            if request.fileFirst { file(&value, name, url) }
            for pair in fields.pairs { value[pair.key] = pair.value }
            if !request.fileFirst { file(&value, name, url) }
            openEditor(request.kind, title: request.title, value: .object(value), key: request.key)
        } catch {
            localError = error.luckyMessage(request.failure)
        }
    }

    /// `file_uri` is read by nothing on this platform — `DockerFile.uploadForm` drops it — but the
    /// form still prints it, so it carries the picked URL as the original carried the cache one.
    private func file(_ value: inout JSONObject, _ name: String, _ url: URL) {
        value["file_name"] = .string(name)
        value["file_uri"] = .string(url.absoluteString)
    }
}

// MARK: - 表单保存

extension DockerScreen {
    /// §19.2's `save(value)`. Five of the forty-three forms never reach the mutation at all — they
    /// run a read here and open the detail viewer — and two more go out under their `-save` twin's
    /// name. `DockerEditorKind.mutation` is where the rest of that mapping lives.
    func save(_ request: DockerEditorRequest, _ value: JSONValue) async {
        switch request.kind {
        case .containerFileDownload:
            let path = value["path"]?.asDisplayString.jsTrimmed ?? ""
            guard !path.isEmpty else {
                localError = "请输入容器内文件路径"
                return
            }
            let id = request.key ?? ""
            editor = nil
            // `split(separator:)` drops empty pieces, which is what `.filter(Boolean)` was for.
            let tail = path.split(separator: "/").last.map(String.init)
            await download("下载容器文件 · \(path)", as: tail ?? "container-file.bin") {
                try await DockerService.downloadContainerFile(id, path: path)
            }
        case .imageFilesystemView:
            let typed = (value["path"]?.asDisplayString ?? "/").jsTrimmed
            let path = typed.isEmpty ? "/" : typed
            let id = request.key ?? ""
            editor = nil
            await openDetail("镜像文件系统 · \(path)") {
                try await DockerService.imageFilesystem(id, path: path)
            }
        case .composeDiscover:
            // Alone among the five this one closes the form *after* the read, so a failure leaves
            // it open. The original then drops the rejection — `save` is typed `=> void`, so it
            // escapes into a promise nobody awaits — where this prints it on the error card.
            do {
                let scanPath = value["scan_path"]?.asDisplayString ?? ""
                let result = try await DockerService.discoverCompose(scanPath: scanPath)
                editor = nil
                detail = DockerDetail("Compose 扫描结果", value: result)
            } catch {
                localError = error.luckyMessage()
            }
        case .composeReadFile:
            let projectPath = value["project_path"]?.asDisplayString.jsTrimmed ?? ""
            let filePath = value["file_path"]?.asDisplayString.jsTrimmed ?? ""
            guard !projectPath.isEmpty, !filePath.isEmpty else {
                localError = "请输入 Compose 项目路径和文件路径"
                return
            }
            editor = nil
            await openDetail("读取 Compose 文件 · \(filePath)") {
                try await DockerService.readComposeFile(workingDirectory: projectPath,
                                                       filename: filePath)
            }
        case .composeBackupDownload:
            let project = value["project_name"]?.asDisplayString.jsTrimmed ?? ""
            let backup = value["backup"]?.asDisplayString.jsTrimmed ?? ""
            guard !project.isEmpty, !backup.isEmpty else {
                localError = "请输入 Compose 项目名称和备份文件"
                return
            }
            editor = nil
            let tail = backup.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last
            await download("下载 Compose 备份 · \(project)",
                           as: tail.map(String.init) ?? "\(project)-backup.tar.gz") {
                try await DockerService.downloadComposeBackup(projectName: project, backup: backup)
            }
        default:
            submit(request, value)
        }
    }

    /// The three remaining shapes: `mirror-remove` sends its own field as the key and no body,
    /// the two compose editors carry the project path forward from the request when the form has
    /// none, and everything else goes out exactly as the form produced it.
    private func submit(_ request: DockerEditorRequest, _ value: JSONValue) {
        guard let type = request.kind.mutation else { return }
        if let field = request.kind.sendsFieldAsKey {
            run(DockerMutation(type, key: value[field]?.asDisplayString ?? ""))
            return
        }
        switch request.kind {
        case .composeConfig, .composeDockerfile:
            var fields = value.record
            // `String(value.project_path ?? editor.key ?? "")` — `??` skips only a null, so a
            // present-but-empty path stays empty rather than falling back to the request's.
            var path = request.key ?? ""
            if let present = fields["project_path"], !present.isNull {
                path = present.asDisplayString
            }
            fields["project_path"] = .string(path)
            run(DockerMutation(type, value: .object(fields)))
        default:
            run(DockerMutation(type, key: request.key, value: value))
        }
    }
}
