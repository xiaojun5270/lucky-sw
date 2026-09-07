import SwiftUI

/// Form controls, all on the content layer.
///
/// The structured request form generates dozens of these at once from a schema, so they are plain
/// value-typed views with no glass, no shadow and no per-field animation — the cost of one of them
/// times fifty is what decides whether that screen scrolls smoothly.
struct LuckyTextField: View {
    var label: String
    @Binding var text: String
    var placeholder: String = ""
    var symbol: String?
    var hint: String?
    var mono: Bool = false
    var secure: Bool = false
    /// A vertical-axis field grows with its content, but Return then inserts a newline instead of
    /// submitting — so single-line stays the default and the login form keeps its 登录 key.
    var multiline: Bool = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var submitLabel: SubmitLabel = .return
    var tone: LuckyTone?
    var onSubmit: (() -> Void)?

    @FocusState private var focused: Bool
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.xs) {
            LuckyFieldLabel(label: label, symbol: symbol, hint: hint, tone: tone)
            HStack(spacing: LuckyTheme.Space.s) {
                field
                    .font(mono ? LuckyTheme.Text.code : LuckyTheme.Text.body)
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .keyboardType(keyboard)
                    .textContentType(contentType)
                    .submitLabel(submitLabel)
                    .textInputAutocapitalization(mono || secure ? .never : .sentences)
                    .autocorrectionDisabled(mono || secure)
                    .focused($focused)
                    .onSubmit { onSubmit?() }
                if secure {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LuckyTheme.textTertiary)
                    .accessibilityLabel(revealed ? "隐藏内容" : "显示内容")
                } else if !text.isEmpty, focused {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(LuckyTheme.textTertiary)
                    .accessibilityLabel("清空")
                }
            }
            .padding(.horizontal, LuckyTheme.Space.m)
            .padding(.vertical, 11)
            .background(fieldBackground)
        }
    }

    /// `SecureField` cannot be toggled into a visible field in place — swapping the view is the
    /// only way, and it must keep the same binding so the text survives the swap.
    @ViewBuilder
    private var field: some View {
        if secure, !revealed {
            SecureField(placeholder, text: $text)
        } else if multiline {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(2...8)
        } else {
            TextField(placeholder, text: $text)
        }
    }

    private var fieldBackground: some View {
        let shape = RoundedRectangle(cornerRadius: LuckyTheme.Radius.field, style: .continuous)
        return shape
            .fill(LuckyTheme.surfaceSunken)
            .overlay(
                shape.strokeBorder(
                    focused ? (tone ?? .brand).tint.opacity(0.7) : LuckyTheme.hairline,
                    lineWidth: focused ? 1.6 : LuckyTheme.strokeWidth
                )
            )
    }
}

/// The label line shared by every field: name, optional glyph, optional hint, optional tone.
/// Lucky's own field descriptions are long Chinese sentences, so the hint wraps rather than
/// truncating.
struct LuckyFieldLabel: View {
    var label: String
    var symbol: String?
    var hint: String?
    var tone: LuckyTone?
    var required: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: LuckyTheme.Space.xs) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle((tone ?? .brand).tint)
                }
                Text(label)
                    .font(LuckyTheme.Text.label)
                    .foregroundStyle(LuckyTheme.textSecondary)
                if required {
                    Text("*")
                        .font(LuckyTheme.Text.label)
                        .foregroundStyle(LuckyTheme.danger)
                        .accessibilityLabel("必填")
                }
            }
            if let hint, !hint.isEmpty {
                Text(hint)
                    .font(LuckyTheme.Text.caption)
                    .foregroundStyle(LuckyTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A switch row. Lucky reports switch state as a bool, a number or a word, so screens convert with
/// `Format.asEnabled` before binding — this view only ever sees a `Bool`.
struct LuckyToggleRow: View {
    var label: String
    var hint: String?
    var symbol: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            LuckyFieldLabel(label: label, symbol: symbol, hint: hint,
                            tone: isOn ? .ok : .idle)
        }
        .toggleStyle(.switch)
        .tint(LuckyTheme.accent)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}

/// A JSON / YAML / compose editor. `TextEditor` rather than a vertical `TextField` because the
/// debugger's body box must keep its height while empty and must not grow the page as the user
/// types.
struct LuckyCodeEditor: View {
    var label: String
    @Binding var text: String
    var hint: String?
    var height: CGFloat = 180
    var tone: LuckyTone?

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.xs) {
            LuckyFieldLabel(label: label, symbol: "curlybraces", hint: hint, tone: tone)
            TextEditor(text: $text)
                .font(LuckyTheme.Text.code)
                .foregroundStyle(LuckyTheme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(height: height)
                .padding(LuckyTheme.Space.s)
                .background {
                    let shape = RoundedRectangle(cornerRadius: LuckyTheme.Radius.field,
                                                 style: .continuous)
                    shape.fill(LuckyTheme.surfaceSunken)
                        .overlay(
                            shape.strokeBorder(
                                focused ? (tone ?? .brand).tint.opacity(0.7) : LuckyTheme.hairline,
                                lineWidth: focused ? 1.6 : LuckyTheme.strokeWidth
                            )
                        )
                }
        }
    }
}
