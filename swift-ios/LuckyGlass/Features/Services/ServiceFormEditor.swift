import SwiftUI

/// The chrome every 服务 sheet shares.
///
/// The original mounts each editor as a full-screen `Modal` with a hand-built header — an
/// `IconTile`, the title, and an X — and a primary button pinned below a `KeyboardAvoidingView`.
/// Here that becomes a `.sheet` holding a `NavigationStack`: the title and 关闭 come from the real
/// toolbar, and the pinned button becomes the same bottom glass bar the endpoint debugger uses, so
/// the keyboard avoidance the original wires by hand is handled by the scroll view.
struct ServiceSheet<Content: View, Actions: View>: View {
    var title: String
    /// The line the original prints under the modal's title — the record's name. Empty for the
    /// editors, which name their subject in the title itself.
    var subtitle: String = ""
    var close: () -> Void
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            ZStack {
                LuckyBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: LuckyTheme.Space.stack, content: content)
                        .padding(.horizontal, LuckyTheme.Space.gutter)
                        .padding(.top, LuckyTheme.Space.s)
                        .padding(.bottom, LuckyTheme.Space.xxl)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollIndicators(.hidden)
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .luckyActionBar(content: actions)
        }
    }
}

/// `ServiceFormEditor` — the generic record editor behind 编辑 and 模块设置.
///
/// It knows nothing about DDNS or SSL: whatever fields the module returned are the fields it edits,
/// which is why the same component serves a task, a certificate and both settings records.
struct ServiceFormEditor: View {
    var request: ServiceEditorRequest
    var busy: Bool
    var close: () -> Void
    var save: (JSONObject) -> Void

    /// `useState(() => JSON.parse(JSON.stringify(editor.value)))`. The deep copy is what keeps a
    /// cancelled edit from touching the row behind the sheet — and `JSONObject` being a value type
    /// means the copy *is* the assignment.
    @State private var value: JSONObject

    init(
        request: ServiceEditorRequest,
        busy: Bool,
        close: @escaping () -> Void,
        save: @escaping (JSONObject) -> Void
    ) {
        self.request = request
        self.busy = busy
        self.close = close
        self.save = save
        _value = State(initialValue: request.value)
    }

    var body: some View {
        ServiceSheet(title: request.title, close: close) {
            LuckyPillButton(title: busy ? "保存中" : "保存", symbol: "square.and.arrow.down",
                            prominent: true, loading: busy) {
                save(value)
            }
        } content: {
            LuckyCard {
                StructuredForm(value: $value)
            }
        }
    }
}
