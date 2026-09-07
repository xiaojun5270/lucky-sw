import SwiftUI

/// `EditorModal` — the sheet behind 新增, 编辑, STUN 全局设置 and the three child forms.
///
/// It owns its copy of the record — `JSON.parse(JSON.stringify(editor.value))`, and a `JSONObject`
/// being a value type means the copy *is* the assignment — so a cancelled edit never touches the
/// row behind it. Validation runs on save rather than on each keystroke, which is what lets a port
/// field hold `""` while it is being retyped.
struct TunnelEditorSheet: View {
    var editor: TunnelEditor
    var close: () -> Void
    var save: (JSONObject) async throws -> Void

    @State private var value: JSONObject
    @State private var failure = ""
    @State private var result = ""
    @State private var saving = false
    @State private var testing = false

    init(editor: TunnelEditor, close: @escaping () -> Void,
         save: @escaping (JSONObject) async throws -> Void) {
        self.editor = editor
        self.close = close
        self.save = save
        _value = State(initialValue: editor.value)
    }

    private var busy: Bool { saving || testing }

    /// `保存中` / `创建并启用` / `保存`. A webhook test in flight disables the button without renaming
    /// it, because only `mutation.isPending` is asked about.
    private var saveTitle: String {
        if saving { return "保存中" }
        return editor.type == .stun && !editor.editing ? "创建并启用" : "保存"
    }

    /// The webhook door, open for the two STUN forms once 启用 Webhook is on. The original tests
    /// `value.WebhookEnable` for truthiness, so a module answering `1` or `"true"` opens it too.
    private var webhookVisible: Bool {
        guard editor.type == .stun || editor.type == .stunSettings else { return false }
        return value["WebhookEnable"]?.isTruthy == true
    }

    var body: some View {
        ServiceSheet(title: editor.title, close: dismiss) {
            LuckyPillButton(title: saveTitle, symbol: "square.and.arrow.down", prominent: true,
                            loading: saving) {
                Task { await commit() }
            }
            .disabled(busy)
        } content: {
            if !failure.isEmpty {
                LuckyErrorCard(message: failure, title: "无法保存")
            }
            LuckyCard {
                TunnelForm(type: editor.type, value: $value, disabled: busy)
            }
            if webhookVisible {
                ServiceActionButton(title: testing ? "测试中" : "测试 Webhook",
                                    symbol: LuckySymbol.send, fill: .tinted, height: 42,
                                    radius: 12, disabled: busy) {
                    Task { await test() }
                }
            }
            if !result.isEmpty {
                Text(result)
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .interactiveDismissDisabled(busy)
    }

    /// `onRequestClose={() => { if (!busy) close(); }}`, and the X is `disabled={busy}` besides.
    private func dismiss() {
        guard !busy else { return }
        close()
    }
}

// MARK: - Saving

extension TunnelEditorSheet {
    /// `mutation` — validate, hand the record up, close on success. The validator's complaint lands
    /// in the same banner as a failed POST, which is what the shared `error` state does too.
    private func commit() async {
        guard !busy else { return }
        saving = true
        failure = ""
        defer { saving = false }
        do {
            try await save(TunnelSpec.validate(editor.type, value))
            close()
        } catch {
            guard !error.isCancellation else { return }
            failure = error.luckyMessage("保存失败")
        }
    }

    /// `webhook` — the dry run. It validates the whole record before filtering, so a bad port
    /// elsewhere in the form stops the test; that is the original's order and its diagnostic value.
    ///
    /// Unlike `commit`, this does not clear the banner up front: the original clears it only once
    /// the request has come back, so a failed save stays visible while a test is in flight.
    private func test() async {
        guard !busy else { return }
        testing = true
        defer { testing = false }
        do {
            guard !TunnelRecord.text(value["WebhookURL"]).jsTrimmed.isEmpty else {
                throw LuckyError("请先填写 Webhook 地址")
            }
            let candidate = try TunnelSpec.validate(editor.type, value)
            let answer = try await TunnelsService.testStunWebhook(
                key: TunnelRecord.text(value["Key"]),
                value: .object(Self.webhookFields(candidate))
            )
            failure = ""
            result = Self.resultText(answer)
        } catch {
            guard !error.isCancellation else { return }
            failure = error.luckyMessage("Webhook 测试失败")
        }
    }

    /// The `Webhook*` keys plus the two retry keys, in the record's own order. Posting the whole
    /// rule would make the module treat the dry run as a save.
    private static func webhookFields(_ candidate: JSONObject) -> JSONObject {
        candidate.filter { key, _ in
            key.hasPrefix("Webhook") || key == "RetryCount" || key == "RetryInterval"
        }
    }

    /// `text(data.Response) || text(data.msg) || 'Webhook 请求成功'` — `||` falls through an empty
    /// string, so a module that answers `Response: ""` shows the `msg` instead.
    private static func resultText(_ answer: JSONValue) -> String {
        let response = TunnelRecord.text(answer["Response"])
        guard response.isEmpty else { return response }
        let message = TunnelRecord.text(answer["msg"])
        return message.isEmpty ? "Webhook 请求成功" : message
    }
}
