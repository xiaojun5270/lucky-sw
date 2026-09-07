import SwiftUI

/// The option lists every select inside the Web 服务 editor draws from.
///
/// The original closes over them; here they travel as one value, because `private` is file-scoped
/// and the editor's field groups live in files of their own.
struct WebEditorContext {
    /// `ipFilterOptions`
    var filterOptions: [WebOption] = []
    /// `groupOptions`
    var groupOptions: [WebOption] = []
    /// `wafOptions`
    var wafOptions: [WebOption] = []
    /// `[{跟随主规则, main}, ...wafOptions.filter(o => o.value !== "main")]` — what a proxy's own WAF
    /// picker shows, since a proxy may defer to the rule above it.
    var subWafOptions: [WebOption] = []
}

extension WebEditorContext {
    /// `webServiceTypeOptions`
    static let allServiceTypes = [
        WebOption("反向代理", "reverseproxy"),
        WebOption("重定向", "redirect"),
        WebOption("URL 跳转", "url"),
    ]

    /// `tlsOnlyWebServiceTypes` — two service types Lucky only serves over TLS. Neither is in the
    /// list above, so the editor can only ever *keep* one, never choose it.
    static let tlsOnlyTypes: Set<String> = ["SNIRouting", "oauth"]

    /// `availableServiceTypes`. The third arm keeps a TLS-only type that is already selected, so
    /// opening an SNI rule whose TLS is off does not silently rewrite what it serves.
    ///
    /// `option.value === data.WebServiceType` is a strict comparison against the raw value, which
    /// is why this reads `stringValue` and not `asDisplayString`: a numeric or null field matches
    /// nothing at all.
    static func serviceTypes(tlsEnabled: Bool, current: JSONValue?) -> [WebOption] {
        allServiceTypes.filter { option in
            tlsEnabled || !tlsOnlyTypes.contains(option.value)
                || option.value == current?.stringValue
        }
    }
}

// MARK: - 分区

/// §23's `FormSection` — the group card: 14pt padding, radius 14, hairline border, raised fill and
/// a 26pt header row. Not `LuckyCard`, whose radius and inset belong to the page rather than to a
/// form nested inside a sheet.
struct WebFormSection<Content: View>: View {
    var title: String
    var symbol: String?
    var meta: String?
    @ViewBuilder var content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: LuckyTheme.Space.s) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LuckyTheme.accent)
                }
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let meta, !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(LuckyTheme.textSecondary)
                }
            }
            .frame(minHeight: 26)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(LuckyTheme.surfaceRaised))
        .overlay(shape.strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth))
    }
}

/// The 安全设置 sub-heading the rule editor and the sub-rule accordion both draw above their
/// `WebSecurityFields`, preceded by a divider.
struct WebSecurityHeading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LuckyHairline()
                .padding(.vertical, LuckyTheme.Space.hair)
            HStack(spacing: 7) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LuckyTheme.accent)
                Text("安全设置")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(LuckyTheme.textPrimary)
            }
            .padding(.top, LuckyTheme.Space.s)
        }
    }
}

// MARK: - 标签

/// The 12/700 label every editor row carries. Not `LuckyFieldLabel`: that view puts the hint under
/// the label, and §7.7 puts it under the input.
struct WebFieldTitle: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(LuckyTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The 10pt line under an input.
struct WebFieldHint: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .regular, design: .rounded))
            .foregroundStyle(LuckyTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 文本行

/// §7.7 `Field` — one text row of the editor.
///
/// The array/string duality is the load-bearing part: a field whose stored value is an array shows
/// joined on newlines and writes back split on them, while a field holding a string is left as a
/// string. That is what lets `Domains` and `Locations` edit as text and still reach the module as
/// arrays — and what keeps a rule that stored them as text storing them as text.
struct WebField: View {
    var label: String
    var field: String
    var data: JSONObject
    var placeholder: String = ""
    var hint: String?
    var multiline: Bool = false
    var numeric: Bool = false
    var readOnly: Bool = false
    var secret: Bool = false
    var write: (String, JSONValue) -> Void

    private var raw: JSONValue? { data[field] }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    /// `Array.isArray(raw) ? raw.join("\n") : String(raw ?? "")`.
    ///
    /// `Array.prototype.join` prints null and undefined as the empty string — unlike `cleanLines`,
    /// which maps `String` over the same array and keeps the word `null`. Both readers exist in the
    /// original and they disagree, so both are reproduced.
    private var current: String {
        if let list = raw?.arrayValue {
            return list.map { $0.isNull ? "" : $0.asDisplayString }.joined(separator: "\n")
        }
        return raw?.asDisplayString ?? ""
    }

    private var text: Binding<String> {
        Binding(
            get: { current },
            set: { next in
                if raw?.arrayValue != nil {
                    write(field, .array(next.jsLines.map { .string($0) }))
                } else {
                    write(field, .string(next))
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WebFieldTitle(text: label)
            // `numeric && !readOnly` — a read-only numeric field is drawn as plain text, since
            // there is nothing to keep stable.
            if numeric, !readOnly {
                WebNumberInput(value: raw) { write(field, .number($0)) }
            } else {
                input
            }
            if let hint, !hint.isEmpty { WebFieldHint(text: hint) }
        }
    }
}

extension WebField {
    @ViewBuilder
    private var control: some View {
        if secret {
            SecureField(placeholder, text: text)
        } else if multiline {
            TextField(placeholder, text: text, axis: .vertical)
        } else {
            TextField(placeholder, text: text)
        }
    }

    /// `editable={false}` leaves the text selectable; `.disabled` does not. The only read-only row
    /// in the editor is 分组 Key, which the list behind the sheet also prints, so nothing is lost.
    private var input: some View {
        control
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundStyle(readOnly ? LuckyTheme.textSecondary : LuckyTheme.textPrimary)
            .tint(LuckyTheme.accent)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .disabled(readOnly)
            .padding(.horizontal, LuckyTheme.Space.m)
            .padding(.vertical, multiline ? 10 : 8)
            .frame(minHeight: multiline ? 92 : 44, alignment: multiline ? .top : .center)
            .background(shape.fill(readOnly ? LuckyTheme.surfaceRaised : LuckyTheme.surface))
            .overlay(shape.strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth))
    }
}

// MARK: - 数字行

/// `StableNumberInput` — a numeric field that lets a half-typed number stand.
///
/// The draft is what the field shows; the record only hears about it when the text already reads as
/// a plain number, or when the field loses focus. Without that, typing `-` or `1.` would round-trip
/// through `Number()` and be erased under the cursor.
struct WebNumberInput: View {
    var value: JSONValue?
    var change: (Double) -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    init(value: JSONValue?, change: @escaping (Double) -> Void) {
        self.value = value
        self.change = change
        _draft = State(initialValue: Self.text(value))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundStyle(LuckyTheme.textPrimary)
            .tint(LuckyTheme.accent)
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)
            .padding(.horizontal, LuckyTheme.Space.m)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(shape.fill(LuckyTheme.surface))
            .overlay(shape.strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth))
            .onChange(of: draft) { _, next in
                // `/^-?\d+(?:\.\d+)?$/` — an eager write for text that is already a number, so the
                // record tracks the keyboard instead of waiting for the field to be dismissed.
                if Self.isPlainNumber(next) { change(JSCompat.number(next)) }
            }
            .onChange(of: Self.text(value)) { _, next in
                // `useEffect([current, focused])` — an outside change only reaches the draft while
                // the field is idle, so a re-render cannot yank the text out from under the cursor.
                if !focused { draft = next }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
    }
}

extension WebNumberInput {
    /// `typeof value === "number" || typeof value === "string" ? String(value) : ""` — a bool, a
    /// null and an absent key all show as empty.
    private static func text(_ value: JSONValue?) -> String {
        switch value {
        case .number, .string: return value?.asDisplayString ?? ""
        default: return ""
        }
    }

    /// `/^-?\d+(?:\.\d+)?$/.test(text)`. Deliberately stricter than `Number()`: leading `+`,
    /// whitespace, `0x` and exponents are all left to the blur.
    private static func isPlainNumber(_ text: String) -> Bool {
        var rest = Substring(text)
        if rest.first == "-" { rest = rest.dropFirst() }
        let whole = rest.prefix { $0.isASCII && $0.isNumber }
        guard !whole.isEmpty else { return false }
        rest = rest.dropFirst(whole.count)
        if rest.isEmpty { return true }
        guard rest.first == "." else { return false }
        let fraction = rest.dropFirst()
        return !fraction.isEmpty && fraction.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// `onBlur` — a finite draft is applied, and anything else snaps back to the stored value.
    private func commit() {
        let parsed = JSCompat.number(draft)
        if !draft.jsTrimmed.isEmpty, parsed.isFinite {
            change(parsed)
        } else {
            draft = Self.text(value)
        }
    }
}

// MARK: - 开关行

/// §7.7 `Toggle`. A 44pt row: label on the left, switch on the right.
struct WebToggle: View {
    var label: String
    var field: String
    var data: JSONObject
    var write: (String, JSONValue) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { WebRecord.bool(data[field]) },
                             set: { write(field, .bool($0)) })) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LuckyTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.switch)
        .tint(LuckyTheme.accent)
        .frame(minHeight: 44)
    }
}

// MARK: - 选项行

/// §7.7 `Choices` — a wrapping row of pills, one of which is selected.
struct WebChoices: View {
    var label: String
    var field: String
    var options: [WebOption]
    var data: JSONObject
    var write: (String, JSONValue) -> Void

    /// `String(source[field] ?? "") === option.value` — the comparison is on the *stringified*
    /// value, which is what lets a numeric `TLSMinVersion` of 2 select the row whose value is "2".
    private var current: String { data[field]?.asDisplayString ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            WebFieldTitle(text: label)
            LuckyWrap(spacing: 7, lineSpacing: 7) {
                ForEach(options) { option in
                    pill(option)
                }
            }
        }
    }

    private func pill(_ option: WebOption) -> some View {
        let selected = option.value == current
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            write(field, .string(option.value))
        } label: {
            Text(option.label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? LuckyTheme.accent : LuckyTheme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, LuckyTheme.Space.m)
                .frame(minWidth: 76, minHeight: 38)
                .background(shape.fill(selected ? LuckyTheme.accentSoft : LuckyTheme.surface))
                .overlay(shape.strokeBorder(selected ? LuckyTheme.accent : LuckyTheme.hairline,
                                            lineWidth: LuckyTheme.strokeWidth))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}
