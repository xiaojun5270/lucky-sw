import SwiftUI

// MARK: - 下拉行

/// §7.7 `SelectField` — the editor's own dropdown, expanding in place.
///
/// Neither `LuckyGlassMenuPicker` (glass, so it may not sit in scrolling content) nor `SslDropdown`
/// (whose open state is its own): the original keeps a single `openSelect` for the whole form, so
/// opening any select closes every other one. That key is `` `${scope}.${field}` `` and travels
/// here as a binding, which is also what keeps two sub-rules editing the same field apart.
struct WebSelect: View {
    var label: String
    var field: String
    var options: [WebOption]
    var data: JSONObject
    var scope: String = "root"
    @Binding var openSelect: String
    var write: (String, JSONValue) -> Void

    private var selectKey: String { "\(scope).\(field)" }

    /// `String(source[field] ?? "")` — stringified, so a numeric `TLSMinVersion` still matches the
    /// option whose value is "2".
    private var current: String { data[field]?.asDisplayString ?? "" }

    private var open: Bool { openSelect == selectKey }

    /// `options.find(o => o.value === current)?.label ?? (current || "请选择")` — a stored value the
    /// list does not carry shows as itself, and only an empty one falls through to the placeholder.
    private var selectedLabel: String {
        if let match = options.first(where: { $0.value == current }) { return match.label }
        return current.isEmpty ? "请选择" : current
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            WebFieldTitle(text: label)
            summary
            if open { list }
        }
    }
}

extension WebSelect {
    private var summary: some View {
        Button {
            openSelect = open ? "" : selectKey
        } label: {
            HStack(spacing: LuckyTheme.Space.s) {
                Text(selectedLabel)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(current.isEmpty ? LuckyTheme.textTertiary
                                                      : LuckyTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(open ? LuckyTheme.accent : LuckyTheme.textSecondary)
            }
            .padding(.horizontal, LuckyTheme.Space.m)
            .frame(minHeight: 44)
            .background(shape.fill(LuckyTheme.surface))
            .overlay(shape.strokeBorder(open ? LuckyTheme.accent : LuckyTheme.hairline,
                                        lineWidth: LuckyTheme.strokeWidth))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(selectedLabel)
    }

    /// `overflow: "hidden"` around rows whose selected fill runs edge to edge, which is why the
    /// stroke is drawn over the clipped stack rather than on the rows themselves.
    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                row(index, option)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth))
    }

    private func row(_ index: Int, _ option: WebOption) -> some View {
        let active = option.value == current
        return Button {
            write(field, .string(option.value))
            openSelect = ""
        } label: {
            VStack(spacing: 0) {
                // `borderTopWidth: index ? 1 : 0` — the hairline parts the rows, so the first
                // one carries none.
                if index > 0 { LuckyHairline() }
                HStack(spacing: 9) {
                    Text(option.label)
                        .font(.system(size: 13, weight: active ? .bold : .medium, design: .rounded))
                        .foregroundStyle(active ? LuckyTheme.accent : LuckyTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if active {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(LuckyTheme.accent)
                    }
                }
                .padding(.horizontal, LuckyTheme.Space.m)
                .frame(minHeight: 42)
            }
            .background(active ? LuckyTheme.accentSoft : LuckyTheme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 监听类型

/// §21.1 `ListenTypeSelector` — the IPv4 / IPv6 pair, drawn as checkboxes rather than as one
/// segmented control because both may be on at once (`Network` is then `"tcp"`).
struct WebListenTypes: View {
    var data: JSONObject
    var toggle: (String) -> Void

    /// `String(value.Network ?? "tcp6")` — `??` skips null as well as absent, so a null network
    /// reads as tcp6 and not as the empty string.
    private var network: String {
        guard let raw = data["Network"], !raw.isNull else { return "tcp6" }
        return raw.asDisplayString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            WebFieldTitle(text: "监听类型")
            HStack(spacing: LuckyTheme.Space.s) {
                pill("IPv4", "tcp4", network == "tcp" || network == "tcp4")
                pill("IPv6", "tcp6", network == "tcp" || network == "tcp6")
            }
        }
    }
}

extension WebListenTypes {
    private func pill(_ label: String, _ value: String, _ selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button {
            toggle(value)
        } label: {
            HStack(spacing: 7) {
                box(selected)
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? LuckyTheme.accent : LuckyTheme.textPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(shape.fill(selected ? LuckyTheme.accentSoft : LuckyTheme.surface))
            .overlay(shape.strokeBorder(selected ? LuckyTheme.accent : LuckyTheme.hairline,
                                        lineWidth: LuckyTheme.strokeWidth))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// The 18×18 tick box. `strokeWidth 3` on a 12pt glyph is a heavy `checkmark`, and its white is
    /// literal: it sits on the accent fill and must stay light in either colour scheme.
    private func box(_ selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return shape
            .fill(selected ? LuckyTheme.accent : LuckyTheme.surface)
            .overlay(shape.strokeBorder(selected ? LuckyTheme.accent : LuckyTheme.hairline,
                                        lineWidth: LuckyTheme.strokeWidth))
            .overlay {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 18, height: 18)
    }
}

// MARK: - 端口步进

/// §21.1 `PortStepper` — 监听端口, with a minus and a plus around a five-digit field.
///
/// The two writers disagree on type and that is faithful: a step writes a number, while typing
/// writes the digits as a string. `save()` runs both through `Number()` before the payload leaves.
struct WebPortStepper: View {
    var data: JSONObject
    var write: (String, JSONValue) -> Void

    /// `String(value.ListenPort ?? "")` — a null port shows as empty, which `asDisplayString`
    /// already does.
    private var raw: String { data["ListenPort"]?.asDisplayString ?? "" }

    private var text: Binding<String> {
        Binding(
            get: { raw },
            // `next.replace(/\D/g, "")`, and `maxLength 5` — which RN enforces on the keystroke and
            // this enforces on the write, so five digits is the cap either way.
            set: { next in write("ListenPort", .string(String(next.jsDigitsOnly.prefix(5)))) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            WebFieldTitle(text: "监听端口")
            HStack(spacing: LuckyTheme.Space.s) {
                stepper("minus", name: "减少端口", offset: -1)
                field
                stepper("plus", name: "增加端口", offset: 1)
            }
        }
    }
}

extension WebPortStepper {
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    /// `selectTextOnFocus` has no SwiftUI equivalent; the field keeps the caret where it is tapped.
    private var field: some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(LuckyTheme.textPrimary)
            .tint(LuckyTheme.accent)
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(shape.fill(LuckyTheme.surface))
            .overlay(shape.strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth))
            .accessibilityLabel("监听端口")
    }

    private func stepper(_ symbol: String, name: String, offset: Double) -> some View {
        Button {
            step(offset)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LuckyTheme.accent)
                .frame(width: 42, height: 42)
                .background(shape.fill(LuckyTheme.surface))
                .overlay(shape.strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }

    /// `Number.isInteger(parsed) && parsed > 0 ? parsed : 16666`, then clamped to 1…65535.
    ///
    /// `parseInt` only ever answers a whole number, NaN or infinity, so `isInteger` amounts to the
    /// finiteness test — and a port stored as `"16666x"` still steps from 16666.
    private func step(_ offset: Double) {
        let parsed = JSCompat.parseInt(raw)
        let current = parsed.isFinite && parsed > 0 ? parsed : 16666
        write("ListenPort", .number(min(65535, max(1, current + offset))))
    }
}
