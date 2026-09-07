import SwiftUI

/// §21.5 — the 子规则 accordion of the rule editor.
///
/// One card per `ProxyList` entry, at most one of them open. Identity is the *draft id*, not the
/// index: `proxyDraftIds` is seeded alongside the list and travels with an entry, so removing the
/// second sub-rule cannot leave the third one open in its place.
///
/// The list is only ever reordered by 子规则排序 (§7.5), which is why there are no arrows here —
/// only 编辑, 移除 and the footer's 添加子规则.
struct WebEditorProxyList: View {
    var proxies: [JSONValue]
    /// `proxyDraftIds`. Shorter than `proxies` only if a write raced the seed, which the
    /// `proxy-${index}` fallback covers.
    var draftIds: [String]
    /// `String(value.DiaglogShowMode ?? "simple")`. `diyMode` is derived from it rather than
    /// passed: the original's `value.DiaglogShowMode === "diy"` and `ruleMode === "diy"` can only
    /// ever agree.
    var ruleMode: String
    var tlsEnabled: Bool
    var context: WebEditorContext
    @Binding var expandedProxyId: String
    @Binding var openSelect: String
    var write: (Int, String, JSONValue) -> Void
    var remove: (Int, String) -> Void
    var add: () -> Void

    private var diyMode: Bool { ruleMode == "diy" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ForEach(Array(proxies.enumerated()), id: \.offset) { index, proxy in
                card(index, proxy)
            }
            footer
        }
    }
}

extension WebEditorProxyList {
    /// 30pt rather than `WebFormSection`'s 26: this heading stands outside a section card, so §21.5
    /// gives it the taller row.
    private var header: some View {
        HStack(spacing: LuckyTheme.Space.s) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LuckyTheme.accent)
            Text("子规则")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(LuckyTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(proxies.count) 项")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(LuckyTheme.textSecondary)
        }
        .frame(minHeight: 30)
    }

    /// Drawn rather than a `ServiceActionButton(fill: .tinted)`: §21.5 gives this one a
    /// full-strength accent border, a 17pt glyph and a 13/800 label, where the shared control would
    /// draw a 45% border, 13pt and 12/500.
    private var footer: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button(action: add) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                Text("添加子规则")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(LuckyTheme.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(shape.fill(LuckyTheme.accentSoft))
            .overlay(shape.strokeBorder(LuckyTheme.accent, lineWidth: LuckyTheme.strokeWidth))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

extension WebEditorProxyList {
    private func draftId(_ index: Int) -> String {
        index < draftIds.count ? draftIds[index] : "proxy-\(index)"
    }

    /// `pick(proxy, ["Remark"], fallback) || fallback` — the `||` is what catches an explicit empty
    /// remark, which `pick` alone would return as the empty string.
    private func title(_ index: Int, _ proxy: JSONValue) -> String {
        let fallback = "子规则 \(index + 1)"
        let remark = WebRecord.pick(proxy, ["Remark"], fallback)
        return remark.isEmpty ? fallback : remark
    }

    private func card(_ index: Int, _ proxy: JSONValue) -> some View {
        let id = draftId(index)
        let open = expandedProxyId == id
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: LuckyTheme.Space.m) {
            head(index, proxy, id, open)
            if open { expansion(index, proxy, id) }
        }
        .padding(LuckyTheme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(LuckyTheme.surface))
        .overlay(shape.strokeBorder(open ? LuckyTheme.accent : LuckyTheme.hairline,
                                    lineWidth: LuckyTheme.strokeWidth))
    }

    private func head(_ index: Int, _ proxy: JSONValue, _ id: String, _ open: Bool) -> some View {
        let name = title(index, proxy)
        return VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
            disclosure(proxy, id, open, name)
            // `justifyContent: "flex-end"` on a wrapping row that only ever holds these two chips.
            HStack(spacing: 7) {
                Spacer(minLength: 0)
                WebIconButton(symbol: "pencil", name: "编辑\(name)", text: "编辑",
                              tint: LuckyTheme.accent) {
                    // 编辑 opens the entry; unlike the header it never closes it again.
                    expandedProxyId = id
                }
                WebIconButton(symbol: LuckySymbol.delete, name: "移除\(name)", text: "移除",
                              tint: LuckyTheme.danger) {
                    remove(index, id)
                }
            }
        }
    }

    private func disclosure(_ proxy: JSONValue, _ id: String, _ open: Bool,
                            _ name: String) -> some View {
        // `cleanLines(proxy.Domains)[0] ?? "未填写前端地址"` — the first non-blank front-end address.
        let domain = WebRecord.lines(proxy["Domains"]).first ?? "未填写前端地址"
        return Button {
            expandedProxyId = open ? "" : id
        } label: {
            HStack(spacing: 9) {
                LuckyIconTile(symbol: LuckySymbol.network, size: 34, glyph: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(LuckyTheme.textPrimary)
                        .lineLimit(1)
                    Text(domain)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(LuckyTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LuckyTheme.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(domain)
        .accessibilityHint(open ? "收起子规则设置" : "展开子规则设置")
    }

    /// The open body. `showIpFilter` opens up in 定制模式 or for an SNI route, which needs the
    /// filter in either mode — and the comparison is strict, so only the literal string counts.
    private func expansion(_ index: Int, _ proxy: JSONValue, _ id: String) -> some View {
        let record = proxy.record
        let showIpFilter = diyMode || proxy["WebServiceType"]?.stringValue == "SNIRouting"
        let write: (String, JSONValue) -> Void = { field, next in self.write(index, field, next) }
        return VStack(alignment: .leading, spacing: 0) {
            LuckyHairline()
            VStack(alignment: .leading, spacing: 10) {
                WebSubRuleFields(data: record, scope: id, ruleMode: ruleMode,
                                 tlsEnabled: tlsEnabled, context: context,
                                 openSelect: $openSelect, write: write)
                WebSecurityHeading()
                WebSecurityFields(data: record, scope: "\(id)-security",
                                  showIpFilter: showIpFilter, context: context,
                                  openSelect: $openSelect, write: write)
            }
            .padding(.top, LuckyTheme.Space.m)
        }
    }
}
