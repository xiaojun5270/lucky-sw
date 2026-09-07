import SwiftUI

/// `FormField` — one row of a tunnel form, rendered from a `TunnelField` rather than from a schema.
///
/// Every row is controlled by the record instead of holding its own state, and that is what makes
/// the tables reactive: 上报方式 revealing four more fields, or 重试次数 revealing 重试间隔, happens
/// on the keystroke that changes them because the parent re-derives the whole table. A row with
/// local text would fight that, so the bindings below read the record and write through `change`.
struct TunnelFieldRow: View {
    var field: TunnelField
    /// Already resolved through the dotted path — the parent is what reads `Options.SafeMode`.
    var value: JSONValue?
    var disabled: Bool
    var change: (JSONValue) -> Void

    /// `{spec.label}{spec.required ? ' *' : ''}`. `LuckyFieldLabel` does carry a `required` flag
    /// with a coloured marker, but `LuckyTextField` does not forward it — and a form where half the
    /// asterisks are red reads as a bug, so every one of them is part of the label text instead.
    private var label: String { field.required ? "\(field.label) *" : field.label }

    var body: some View {
        if field.kind == .toggle {
            LuckyToggleRow(label: label, isOn: toggle).disabled(disabled)
        } else if let options = field.options {
            chips(options)
        } else {
            editor.disabled(disabled)
        }
    }

    /// The text shapes. `options` outranks all of them, as it does in the original: it is tested
    /// before `type` for everything except a switch.
    @ViewBuilder
    private var editor: some View {
        if field.kind == .number {
            LuckyTextField(label: label, text: text, mono: true, keyboard: .numberPad)
        } else if field.kind == .secret {
            LuckyTextField(label: label, text: text, secure: true)
        } else if field.kind == .lines {
            LuckyTextField(label: label, text: lines, hint: "每行一条", mono: true,
                           multiline: true)
        } else if field.kind == .multiline {
            LuckyCodeEditor(label: label, text: text, height: 112)
        } else {
            LuckyTextField(label: label, text: text, mono: true)
        }
    }
}

// MARK: - Bindings

extension TunnelFieldRow {
    /// `value === true` — a switch the module answers with `1` or `"true"` reads as off here, which
    /// is what the original's forms do. Only the lists are lax about that spelling.
    private var toggle: Binding<Bool> {
        Binding(get: { value?.boolValue == true }, set: { change(.bool($0)) })
    }

    /// `String(value ?? '')` in, a string out — which is why a number field holds text while it is
    /// being typed, and why `TunnelSpec.validate` is the thing that turns it back into a number.
    ///
    /// `??` steps over `null`, so a cleared server field types as empty rather than as `null`.
    private var text: Binding<String> {
        Binding(get: {
            guard let value, !value.isNull else { return "" }
            return TunnelSpec.stringify(value)
        }, set: { change(.string($0)) })
    }

    /// `value.join('\n')` in, `next.split('\n')` out. Blank lines survive editing — only the
    /// validator compacts them — so pressing Return partway down a list does not fight back.
    private var lines: Binding<String> {
        Binding(get: {
            guard let items = value?.arrayValue else { return text.wrappedValue }
            return items.map { $0.isNull ? "" : TunnelSpec.stringify($0) }
                .joined(separator: "\n")
        }, set: { next in change(.array(next.jsLines.map { .string($0) })) })
    }
}

// MARK: - Options

extension TunnelFieldRow {
    /// A fixed option set, as wrapping pills. The original marks each pill `role="radio"` rather
    /// than marking the group, so the selected state rides on the pill here too.
    private func chips(_ options: [String]) -> some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            LuckyFieldLabel(label: label)
            LuckyWrap(spacing: 6, lineSpacing: 6) {
                ForEach(options, id: \.self) { option in
                    chip(option)
                }
            }
        }
        .disabled(disabled)
    }

    private func chip(_ option: String) -> some View {
        // `value === option`, so a module answering a numeric 4 where the option is `'4'` selects
        // nothing at all — the original's strict comparison behaves the same way.
        let selected = value?.stringValue == option
        return Button {
            change(.string(option))
        } label: {
            Text(TunnelSpec.optionLabel(option))
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(selected ? LuckyTheme.accent : LuckyTheme.textPrimary)
                .padding(10)
                .frame(minHeight: 40)
                .background(chipBackground(selected))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    private func chipBackground(_ selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return shape
            .fill(selected ? LuckyTone.brand.fill : LuckyTheme.surface)
            .overlay(shape.strokeBorder(selected ? LuckyTheme.accent : LuckyTheme.hairline,
                                        lineWidth: LuckyTheme.strokeWidth))
    }
}

// MARK: - The form

/// `TunnelForm` — the body of an editor sheet, for any of the seven form types.
///
/// The three folds are the original's. 定制模式参数 appears the moment a STUN rule switches to
/// 定制模式, because those fields start being validated from then on and hiding them would make the
/// error unexplainable. 高级设置 stays collapsed by default for the five non-fixed types. And
/// 其他参数 is the escape hatch: Lucky's modules keep adding keys, a record posted back without one
/// loses it, so whatever the tables do not cover stays editable through `StructuredForm`.
struct TunnelForm: View {
    var type: TunnelFormType
    @Binding var value: JSONObject
    var disabled: Bool = false

    @State private var advanced = false
    @State private var extras = false

    var body: some View {
        VStack(alignment: .leading, spacing: LuckyTheme.Space.l) {
            rows(baseFields)
            if !customFields.isEmpty {
                LuckyHairline()
                Text("定制模式参数")
                    .font(LuckyTheme.Text.cardTitle)
                    .foregroundStyle(LuckyTheme.textPrimary)
                rows(customFields)
            }
            if !type.fixedMode {
                advancedToggle
                rows(shownAdvancedFields)
                if advanced { extrasSection }
            }
        }
    }
}

// MARK: - Field tables

extension TunnelForm {
    private func rows(_ specs: [TunnelField]) -> some View {
        ForEach(specs) { spec in
            TunnelFieldRow(field: spec, value: TunnelSpec.read(value, spec.key),
                           disabled: disabled) { next in
                value = TunnelSpec.update(type, value, key: spec.key, next: next)
            }
        }
    }

    /// A STUN rule being created hides 启用规则: `POST /api/relayrules` enables what it adds, which
    /// is also why that sheet's footer reads 创建并启用.
    private var baseFields: [TunnelField] {
        TunnelSpec.fields(type, value, advanced: false).filter { spec in
            !(type == .stun && !TunnelSpec.truthy(value, "Key") && spec.key == "Enable")
        }
    }

    /// The 定制模式 table, which is the same advanced table the other types fold away — STUN just
    /// shows it inline and under a heading instead.
    private var customFields: [TunnelField] {
        guard type == .stun, value["DiaglogShowMode"]?.stringValue == "diy" else { return [] }
        return TunnelSpec.fields(type, value, advanced: true)
    }

    private var shownAdvancedFields: [TunnelField] {
        guard !type.fixedMode, advanced else { return [] }
        return TunnelSpec.fields(type, value, advanced: true)
    }
}

// MARK: - Disclosures

extension TunnelForm {
    private var advancedToggle: some View {
        Button {
            advanced.toggle()
        } label: {
            HStack(spacing: LuckyTheme.Space.s) {
                Image(systemName: advanced ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                Text("高级设置").font(LuckyTheme.Text.label)
            }
            .foregroundStyle(LuckyTheme.accent)
            .frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var extrasSection: some View {
        Button {
            extras.toggle()
        } label: {
            Text(extras ? "收起其他参数" : "其他参数")
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textTertiary)
                .frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        if extras {
            StructuredForm(value: extraBinding).disabled(disabled)
        }
    }
}

// MARK: - 其他参数

extension TunnelForm {
    /// The keys the fold never shows. `Key` is the identity the sheet posts back, `ret`/`msg` are
    /// the envelope a GET leaves behind, and the four collection names are the module's runtime
    /// aliases — editing those as raw JSON would overwrite the child lists the detail sheet owns.
    private static let hiddenKeys: Set<String> = ["Key", "ret", "msg", "Proxies", "Visitors",
                                                  "proxies", "visitors"]

    /// Everything the two field tables leave uncovered.
    ///
    /// A nested record is filtered child by child rather than kept or dropped whole, because
    /// `Options` is half covered by the 定制模式 table and half not — the fold has to show only the
    /// other half.
    private var extra: JSONObject {
        var covered = Set(TunnelSpec.fields(type, value, advanced: false).map(\.key))
        covered.formUnion(TunnelSpec.fields(type, value, advanced: true).map(\.key))
        var result = JSONObject()
        for pair in value.pairs {
            guard !covered.contains(pair.key), !Self.hiddenKeys.contains(pair.key) else { continue }
            guard let object = pair.value.objectValue else {
                result[pair.key] = pair.value
                continue
            }
            result[pair.key] = .object(object.filter { child, _ in
                !covered.contains("\(pair.key).\(child)")
            })
        }
        return result
    }

    private var extraBinding: Binding<JSONObject> {
        Binding(get: { extra }, set: { mergeExtras($0) })
    }

    /// Putting the fold's result back means first removing exactly what it showed — a nested record
    /// loses the children it exposed and keeps the covered ones — and then writing the returned
    /// keys on top. A key the editor deleted therefore stays deleted, which is the whole point.
    private func mergeExtras(_ next: JSONObject) {
        var merged = value
        for pair in extra.pairs {
            guard let previous = pair.value.objectValue else {
                merged.removeValue(forKey: pair.key)
                continue
            }
            var retained = TunnelSpec.nested(value, pair.key)
            for child in previous.keys { retained.removeValue(forKey: child) }
            merged[pair.key] = .object(retained)
        }
        for pair in next.pairs {
            guard let object = pair.value.objectValue else {
                merged[pair.key] = pair.value
                continue
            }
            merged[pair.key] = .object(TunnelSpec.nested(merged, pair.key).merging(object))
        }
        value = merged
    }
}
