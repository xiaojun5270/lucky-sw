import SwiftUI

/// §7.4 `WebServiceToolsModal` — the 更多操作 drawer a rule or sub-rule row opens.
///
/// Six rows, of which only the first is unconditional: the four log endpoints below it need a
/// sub-rule to read, and the last two need that sub-rule to be a file service. Four of them push a
/// log target into the 日志 pane, two run a mutation.
///
/// Chrome is hand-built rather than `ServiceSheet`, for two reasons: the drawer has no primary
/// verb, and `luckyActionBar` would draw an empty glass bar for one; and §7.4 gives the close
/// button its own accessibility label, which `ServiceSheet` fixes at 关闭.
struct WebToolsSheet: View {
    var target: WebToolsTarget
    var busy: Bool
    var close: () -> Void
    var openLog: (WebLogTarget) -> Void
    var flush: () -> Void
    var updateFolder: () -> Void

    /// §19's 刷新目录缓存 confirmation. Local, because the page's own alert sits *behind* this
    /// sheet and would never appear — the same reason §18.1's confirmation hangs off its sheet.
    @State private var confirmingFlush = false

    var body: some View {
        NavigationStack {
            ZStack {
                LuckyBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: LuckyTheme.Space.s) {
                        rows
                    }
                    .padding(.horizontal, LuckyTheme.Space.gutter)
                    .padding(.top, LuckyTheme.Space.s)
                    .padding(.bottom, LuckyTheme.Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollIndicators(.hidden)
            }
            .navigationTitle(title)
            .navigationSubtitle("更多操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭更多操作")
                }
            }
        }
        // A six-row list at most, so the drawer opens at half height and can still be pulled up.
        .presentationDetents([.medium, .large])
        .alert("刷新目录缓存", isPresented: $confirmingFlush) {
            Button("取消", role: .cancel) {}
            // Default rather than destructive: re-reading a directory only costs time.
            Button("刷新") { flush() }
        } message: {
            Text("确定重新读取此子规则的目录占用信息吗？")
        }
    }
}

extension WebToolsSheet {
    /// `target.subKey ? subTitle : target.ruleName` — an empty sub-key is falsy, so it reads as a
    /// rule row rather than as a nameless sub-rule.
    private var title: String {
        target.hasSubRule ? target.subTitle : target.ruleName
    }

    @ViewBuilder
    private var rows: some View {
        WebToolsRow(title: "HTTP 服务日志", symbol: "server.rack", tone: .info, busy: busy) {
            openLog(WebLogTarget(.http, title: "\(target.ruleName) · HTTP 日志",
                                 ruleKey: target.ruleKey))
        }
        if target.hasSubRule {
            WebToolsRow(title: "子规则日志", symbol: LuckySymbol.logs, tone: .info, busy: busy) {
                open(.subrule, "日志")
            }
            WebToolsRow(title: "访问详情与客户端", symbol: "person.2", tone: .brand, busy: busy) {
                open(.access, "访问详情")
            }
            WebToolsRow(title: "Coraza WAF 日志", symbol: "exclamationmark.shield",
                        tone: .warning, busy: busy) {
                open(.coraza, "WAF 日志")
            }
            if target.fileService {
                WebToolsRow(title: "刷新目录缓存", symbol: "list.bullet.indent", tone: .ok,
                            busy: busy) {
                    confirmingFlush = true
                }
                WebToolsRow(title: "更新文件服务目录", symbol: LuckySymbol.upload, tone: .warning,
                            busy: busy, action: updateFolder)
            }
        }
    }

    /// The three sub-rule endpoints differ only in their kind and the suffix on their title, so the
    /// `${subTitle} · ${suffix}` shape is written once.
    private func open(_ kind: WebLogKind, _ suffix: String) {
        openLog(WebLogTarget(kind, title: "\(target.subTitle) · \(suffix)",
                             ruleKey: target.ruleKey, subKey: target.subKey))
    }
}

/// One action row. Not a `ServiceActionButton`: these are left-aligned, their label stays in the
/// primary text colour while only the glyph carries the tone, and they are dimmed rather than
/// disabled while a mutation runs — exactly as §7.4 draws them.
private struct WebToolsRow: View {
    var title: String
    var symbol: String
    var tone: LuckyTone
    var busy: Bool
    var action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tone.tint)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, LuckyTheme.Space.m)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(shape.fill(LuckyTheme.surfaceRaised))
            .overlay(shape.strokeBorder(LuckyTheme.hairline, lineWidth: LuckyTheme.strokeWidth))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(busy ? 0.5 : 1)
    }
}
