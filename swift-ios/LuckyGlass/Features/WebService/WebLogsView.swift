import SwiftUI

/// §16 — 日志. One pane over seven endpoints: the module's own log, a rule's HTTP log, a sub-rule's
/// log, its access details and its Coraza WAF log.
///
/// The 模块日志 / 最近日志 controls and the pager both live outside this view — a glass control may
/// not sit inside scrolling content, so the screen keeps them in its pinned header and its bottom
/// bar. What is left here is the section header and the rows.
struct WebLogsView: View {
    var target: WebLogTarget
    var entries: [JSONValue]
    var total: Int?
    var page: Int
    var mode: WebLogMode
    var fetching: Bool
    /// §16.2's `disconnecting` — true only while a 断开客户端 is in flight, so a rule toggle running
    /// in another pane cannot dim these rows.
    var disconnecting: Bool
    var refresh: @Sendable () async -> Void
    /// `confirmDisconnectClient(logTarget.ruleKey, clientKey)`, which the original guards on the
    /// rule key being set.
    var disconnect: (String, String) -> Void

    var body: some View {
        WebPaneScroll(refresh: refresh) {
            LuckySectionHeader(title: target.title, symbol: target.kind.symbol) {
                LuckyChip(text: meta, tone: .idle)
            }
            if entries.isEmpty {
                // `logs.isLoading` is "fetching with nothing to show", which is exactly an empty
                // list plus a read in flight — and unlike the screen's `loaded` set, this stays
                // right when the pager moves to a page that has not arrived yet.
                if fetching {
                    LuckyLoadingView(text: "正在读取\(target.title)")
                } else {
                    LuckyEmptyState(symbol: LuckySymbol.logs, title: "暂无\(target.title)")
                        .padding(.vertical, LuckyTheme.Space.xl)
                }
            } else {
                ForEach(rows) { row in
                    WebLogRow(value: row.value, index: row.index, accessDetails: accessDetails,
                              disconnecting: disconnecting, disconnect: onDisconnect)
                }
            }
        }
    }
}

extension WebLogsView {
    /// `最近日志` in tail mode; otherwise the page number until the module volunteers a total, and
    /// the total once it has.
    private var meta: String {
        if mode == .recent { return "最近日志" }
        guard let total else { return "第 \(page) 页" }
        return "共 \(total) 项"
    }

    /// Only 访问详情 draws the 断开客户端 chip, which is what keeps it off a WAF line that happens
    /// to carry a client key.
    private var accessDetails: Bool { target.kind == .access }

    private func onDisconnect(_ clientKey: String) {
        guard let ruleKey = target.ruleKey, !ruleKey.isEmpty else { return }
        disconnect(ruleKey, clientKey)
    }

    /// `keyExtractor` — `` `${logMode}-${logPage}-${itemKey || "row"}-${index}` ``. The mode and
    /// the page are part of the identity on purpose: turning the pager replaces every row rather
    /// than reusing the cells, which is what stops a tall structured row from inheriting a short
    /// one's measured height.
    ///
    /// The original tests `isRecordValue(item)` before reading a key; `WebRecord.pick` already
    /// answers `""` for anything that is not a record, so the test is folded into the call.
    private var rows: [WebLogEntry] {
        entries.enumerated().map { rowIndex, value in
            let named = WebRecord.pick(value, ["ClientKey", "clientKey", "ID", "id", "Key", "key",
                                               "Time", "time"])
            let handle = named.isEmpty ? "row" : named
            return WebLogEntry(
                id: "\(mode.rawValue)-\(page)-\(handle)-\(rowIndex)",
                // Absolute across pages, so 第 N 项 keeps counting instead of restarting at 1.
                index: (page - 1) * WebLogTarget.pageSize + rowIndex,
                value: value
            )
        }
    }
}

/// One row of `logEntries`, carrying the composite key the `FlatList` identified it by.
private struct WebLogEntry: Identifiable {
    var id: String
    var index: Int
    var value: JSONValue
}

// MARK: - 日志行

/// §7.3 `WebLogRow`. A log endpoint may answer lines or records, so the row renders either: a
/// string is monospaced text, and anything else goes to `StructuredDataView`.
private struct WebLogRow: View {
    var value: JSONValue
    var index: Int
    var accessDetails: Bool
    var disconnecting: Bool
    var disconnect: (String) -> Void

    /// `accessDetails ? webServiceClientKey(value) : ""` — the chip needs a handle to post, and
    /// only the access-details endpoint answers rows that carry one.
    private var clientKey: String {
        accessDetails ? WebRecord.clientKey(value) : ""
    }

    var body: some View {
        LuckyCard(radius: LuckyTheme.Radius.row, padding: LuckyTheme.Space.m, spacing: 10) {
            HStack(alignment: .center, spacing: LuckyTheme.Space.s) {
                Text(verbatim: "第 \(index + 1) 项")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(LuckyTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !clientKey.isEmpty { chip }
            }
            body(for: value)
        }
    }
}

extension WebLogRow {
    /// Dimmed while a disconnect is running but never disabled — the original leaves it pressable,
    /// and the confirmation alert is what actually gates a second call.
    private var chip: some View {
        Button {
            disconnect(clientKey)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "nosign").font(.system(size: 13, weight: .semibold))
                Text("断开客户端")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(LuckyTheme.danger)
            .padding(.horizontal, 11)
            .frame(minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LuckyTheme.dangerSoft)
            )
        }
        .buttonStyle(.plain)
        .opacity(disconnecting ? 0.5 : 1)
        .accessibilityLabel("断开客户端")
    }

    /// A string row is a log line and keeps its own spacing; everything else is a record the module
    /// laid out, so the structured reader prints it field by field.
    @ViewBuilder
    private func body(for value: JSONValue) -> some View {
        if case .string(let text) = value {
            Text(text)
                .font(LuckyTheme.Text.codeSmall)
                .foregroundStyle(LuckyTheme.textPrimary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            StructuredDataView(value: value)
        }
    }
}
