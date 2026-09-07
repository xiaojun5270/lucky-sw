import SwiftUI

// MARK: - 通用表单

/// §19.2's `DockerFormEditor` — the one sheet that serves all forty-three of §24.5's forms.
///
/// It knows nothing about what it is editing: whatever record the call site put into
/// `DockerEditorRequest.value` is what it draws, and `StructuredForm` decides field by field
/// whether that is a switch, a number box, a text box or a nested list. The routing that turns a
/// saved record into a mutation — or into a download, or into a detail read — lives in
/// `DockerScreen.save(_:_:)`, so none of §19.2's table appears here.
struct DockerFormEditor: View {
    var request: DockerEditorRequest
    var busy: Bool
    var close: () -> Void
    var save: (JSONValue) -> Void

    /// `useState(() => clone(editor.value))`. The deep copy is what keeps an abandoned form from
    /// touching the row behind it — and `JSONObject` being a value type means the copy *is* the
    /// assignment.
    @State private var value: JSONObject

    init(
        request: DockerEditorRequest,
        busy: Bool,
        close: @escaping () -> Void,
        save: @escaping (JSONValue) -> Void
    ) {
        self.request = request
        self.busy = busy
        self.close = close
        self.save = save
        _value = State(initialValue: request.value.record)
    }

    var body: some View {
        ServiceSheet(title: request.title, close: close) {
            // 确认执行 rather than 保存: over half of these forms run a command and write nothing,
            // and the original labels every one of them the same way.
            LuckyPillButton(title: busy ? "执行中" : "确认执行", symbol: "tray.and.arrow.down",
                            prominent: true, loading: busy) {
                save(.object(value))
            }
        } content: {
            LuckyCard {
                StructuredForm(value: $value)
            }
        }
    }
}

// MARK: - 创建 Compose

/// §19.1's `ComposeCreateEditor` — the one Docker form that is hand-built rather than generated.
///
/// It earns that because three of its five fields have behaviour a schema cannot express: the
/// config name must be a bare `.yml`/`.yaml` filename, the YAML body has a 1 MB ceiling and three
/// ways to fill it, and the whole thing reports live task progress while it runs.
///
/// `close()` deliberately leaves a running create alive — the screen answers with the
/// `Compose 创建任务正在后台执行` notice — so nothing here cancels anything.
struct ComposeCreateEditor: View {
    var busy: Bool
    var progress: DockerComposeProgress?
    /// The screen's `localError`, which doubles as this sheet's server-error slot.
    var failure: String
    var close: () -> Void
    var save: (DockerComposeCreateValue) -> Void

    @State private var value = DockerComposeCreateValue()
    /// `inputError` — the validation and file-reading messages, which take precedence over the
    /// server's, exactly as `inputError || error` does.
    @State private var inputError = ""
    @State private var picking = false
    @State private var confirmingTemplate = false

    var body: some View {
        // ServiceSheet fixes the close button's label at 关闭 where the original says
        // 关闭创建 Compose; the sheet has a primary verb, so it keeps the shared chrome anyway.
        ServiceSheet(title: "创建 Compose", close: close) {
            LuckyPillButton(title: busy ? "正在创建" : "创建并启动", symbol: LuckySymbol.start,
                            prominent: true, loading: busy) {
                submit()
            }
        } content: {
            tools
            names
            yaml
            if let progress {
                progressPanel(progress)
            }
            if !inputError.isEmpty {
                LuckyErrorCard(message: inputError, title: "无法创建")
            } else if !failure.isEmpty {
                LuckyErrorCard(message: failure)
            }
        }
        // Every `update(key, next)` clears the input error before it stores anything; watching the
        // whole value does that once instead of five times, and covers the picker and the template.
        .onChange(of: value) { inputError = "" }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { result in
            receive(result)
        }
        .alert("加载 Compose 模板", isPresented: $confirmingTemplate) {
            Button("取消", role: .cancel) {}
            Button("替换") { value.composeContent = DockerComposeCreateValue.template }
        } message: {
            Text("当前 YAML 内容将被替换。")
        }
    }
}

// MARK: - 创建 Compose 的字段

extension ComposeCreateEditor {
    /// The three ways to fill the YAML box. `flexBasis: 132` with `flexGrow: 1` — a wrapping row of
    /// equal buttons, which is what `LuckyTileGrid` draws.
    private var tools: some View {
        LuckyTileGrid(minimum: 132, spacing: LuckyTheme.Space.s) {
            ServiceActionButton(title: "导入文件", symbol: LuckySymbol.upload, fill: .tinted,
                                height: 44, radius: 12, disabled: busy, glyph: 16) {
                inputError = ""
                picking = true
            }
            // lucide `ClipboardPaste`. The web branch's secure-context check has no counterpart:
            // `UIPasteboard` is always readable, though iOS may ask the user first.
            ServiceActionButton(title: "粘贴 YAML", symbol: "doc.on.clipboard", fill: .tinted,
                                height: 44, radius: 12, disabled: busy, glyph: 16) {
                paste()
            }
            ServiceActionButton(title: "使用模板", symbol: "doc.text", fill: .tinted,
                                height: 44, radius: 12, disabled: busy, glyph: 16) {
                loadTemplate()
            }
        }
    }

    /// The three names. All three are `autoCapitalize="none" autoCorrect={false}`, which is what
    /// `mono` carries here — and two of them really are paths.
    private var names: some View {
        LuckyCard(spacing: LuckyTheme.Space.stack) {
            LuckyTextField(label: "项目名称（可选）", text: $value.projectName,
                           placeholder: "例如：my-app", mono: true)
            LuckyTextField(label: "工作目录", text: $value.workingDirectory,
                           placeholder: "例如：/opt/compose/my-app", mono: true)
            LuckyTextField(label: "配置文件名", text: $value.configFileName,
                           placeholder: "compose.yaml", mono: true)
        }
        .disabled(busy)
    }

    /// The switch and the YAML box.
    ///
    /// The original prints the character count at the right of the box's label; `LuckyCodeEditor`
    /// has one label line with a hint under it, so the count moves there rather than growing the
    /// design system a trailing slot for one call site.
    private var yaml: some View {
        LuckyCard(spacing: LuckyTheme.Space.stack) {
            LuckyToggleRow(label: "构建镜像", isOn: $value.build)
            LuckyCodeEditor(label: "Compose YAML", text: $value.composeContent,
                            hint: "\(value.composeContent.count) 字符", height: 280)
        }
        .disabled(busy)
    }

    /// `composeProgress` — the accent-tinted panel that replaces the button's spinner as the only
    /// place a `compose-create` reports itself. No bar until the daemon sends a finite percentage.
    private func progressPanel(_ progress: DockerComposeProgress) -> some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            HStack(spacing: LuckyTheme.Space.s) {
                ProgressView().controlSize(.small).tint(LuckyTheme.accent)
                Text(progress.message)
                    .font(LuckyTheme.Text.captionMedium)
                    .foregroundStyle(LuckyTheme.accent)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let percent = progress.progress {
                    Text("\(Int(percent.rounded()))%")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LuckyTheme.accent)
                        .monospacedDigit()
                }
            }
            if let percent = progress.progress {
                ProgressView(value: percent, total: 100)
                    .progressViewStyle(.linear)
                    .tint(LuckyTheme.accent)
            }
            if !progress.taskId.isEmpty {
                Text("任务 ID：\(progress.taskId)")
                    .font(.system(size: 10))
                    .foregroundStyle(LuckyTheme.textSecondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
        .padding(LuckyTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LuckyTheme.accentSoft, in: .rect(cornerRadius: 12))
    }
}

// MARK: - 创建 Compose 的行为

extension ComposeCreateEditor {
    /// `submit()` — the creator's own five checks, whose copy differs from the mutation's even
    /// where the check is the same. `DockerComposeCreateValue.validated()` is where they live.
    private func submit() {
        switch value.validated() {
        case .failed(let message):
            inputError = message
        case .ok(let normalised):
            // The trimmed names are kept, so a second attempt starts from what was actually sent.
            value = normalised
            save(normalised)
        }
    }

    /// `pasteComposeContent()`. Both failures share the box's error slot; neither focuses the
    /// field, because there is no HTTP-page branch to fall back to on iOS.
    private func paste() {
        inputError = ""
        let content = LuckyClipboard.paste()
        if content.jsTrimmed.isEmpty {
            inputError = "剪贴板中没有可粘贴的内容"
            return
        }
        if content.count > DockerComposeCreateValue.contentLimit {
            inputError = "Compose 内容不能超过 1 MB"
            return
        }
        value.composeContent = content
    }

    /// `loadTemplate()` — confirms only when there is something of the user's own to lose. Content
    /// that is already the template, or is blank, is replaced without asking.
    private func loadTemplate() {
        inputError = ""
        let current = value.composeContent
        if !current.jsTrimmed.isEmpty, current != DockerComposeCreateValue.template {
            confirmingTemplate = true
            return
        }
        value.composeContent = DockerComposeCreateValue.template
    }

    /// `importComposeFile()`. The picker's five-MIME filter is gone — `.fileImporter` takes
    /// `UTType`s and `text/x-yaml` has no declaring app to borrow one from — so the extension check
    /// below is what enforces it, as it did in the original for a file that slipped past the
    /// filter.
    ///
    /// Both size checks are kept: the original tests the asset's reported size before it reads and
    /// the string's length after, and a UTF-8 file can pass the first and fail the second.
    private func receive(_ result: Result<URL, Error>) {
        inputError = ""
        do {
            let url = try result.get()
            let name = url.lastPathComponent
            guard DockerComposeCreateValue.isYAMLName(name) else {
                throw LuckyError("请选择 .yml 或 .yaml 文件")
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard data.count <= DockerComposeCreateValue.contentLimit else {
                throw LuckyError("Compose 文件不能超过 1 MB")
            }
            guard let content = String(data: data, encoding: .utf8) else {
                throw LuckyError("读取 Compose 文件失败")
            }
            guard !content.jsTrimmed.isEmpty else { throw LuckyError("Compose 文件内容为空") }
            guard content.count <= DockerComposeCreateValue.contentLimit else {
                throw LuckyError("Compose 文件不能超过 1 MB")
            }
            value.configFileName = name
            value.composeContent = content
        } catch {
            // A cancelled pick reaches `.fileImporter`'s completion as a failure on some builds and
            // not at all on others; `selection.canceled` returned silently, so a
            // cancellation-shaped error does too.
            guard !error.isCancellation else { return }
            inputError = error.luckyMessage("读取 Compose 文件失败")
        }
    }
}

// MARK: - 详情浮层

/// §19's `DockerDetailViewer` — the read-only sheet every inspect, scan report and download receipt
/// lands in.
///
/// Three states, in the original's own order: an error replaces everything; a first read with no
/// payload yet fills the sheet with a spinner and its `status` line; and a payload that is still
/// being added to (a download writing its second and third update under one title) shows the pill
/// above the record.
///
/// Chrome is hand-built rather than `ServiceSheet` for the same two reasons `WebToolsSheet` is: the
/// viewer has no primary verb, so `luckyActionBar` would draw an empty glass bar for it, and §19
/// gives its close button the label 关闭详情.
struct DockerDetailViewer: View {
    var detail: DockerDetail
    var close: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                LuckyBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: LuckyTheme.Space.m) {
                        content
                    }
                    .padding(.horizontal, LuckyTheme.Space.gutter)
                    .padding(.top, LuckyTheme.Space.s)
                    .padding(.bottom, LuckyTheme.Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollIndicators(.hidden)
            }
            .navigationTitle(detail.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭详情")
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = detail.error, !error.isEmpty {
            LuckyErrorCard(message: error)
        } else if detail.loading, detail.value == nil {
            // The original centres a large spinner in the whole modal; a scroll cannot fill, so
            // this is `LuckyLoadingView`'s padded block, which reads the same at this height.
            LuckyLoadingView(text: detail.status ?? "正在读取详情")
        } else {
            if detail.loading {
                statusPill
            }
            LuckyCard {
                StructuredDataView(value: detail.value ?? .null)
            }
        }
    }

    /// The accent pill a still-running flow prints above the payload it has already produced —
    /// 正在下载 over the receipt, 正在检测 3/8 over the partial report.
    private var statusPill: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small).tint(LuckyTheme.accent)
            Text(detail.status ?? "正在处理")
                .font(LuckyTheme.Text.captionMedium)
                .foregroundStyle(LuckyTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, LuckyTheme.Space.m)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LuckyTheme.accentSoft, in: .rect(cornerRadius: 12))
    }
}
