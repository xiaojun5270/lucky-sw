import SwiftUI

/// §13 — Docker 网络. The plainest of the six lists: one glyph, two lines and a single verb.
struct DockerNetworksView: View {
    var items: [LuckyListItem]
    var loading: Bool
    var busy: Bool
    var refresh: @Sendable () async -> Void
    /// `(key, name)` — the mutation is keyed by `keyOf`, the confirmation quotes the name.
    var remove: (String, String) -> Void

    var body: some View {
        DockerListPane(count: items.count, loading: loading,
                       empty: DockerView.networks.emptyMessage,
                       symbol: DockerView.networks.symbol,
                       loadingText: "正在读取 Docker 网络", refresh: refresh) {
            // 创建网络 is the glass bar's; nothing else was ever in this header.
            LuckySectionHeader(title: DockerView.networks.title,
                               symbol: DockerView.networks.symbol) {
                DockerCountChip(count: items.count)
            }
        } rows: {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                DockerNetworkCard(item: item, index: index, busy: busy, remove: remove)
            }
        }
    }
}

private struct DockerNetworkCard: View {
    var item: LuckyListItem
    var index: Int
    var busy: Bool
    var remove: (String, String) -> Void

    private var key: String { DockerRecord.keyOf(item, index) }

    private var name: String { DockerRecord.pick(item, ["Name", "name"], key) }

    /// `${pick(item,["Driver"])} · ${pick(item,["Scope"])}` — both fall back to `""`, so a network
    /// that reports neither renders a bare separator. Kept verbatim: the row is still identifiable
    /// by its name, and inventing a placeholder would be inventing data.
    private var subtitle: String {
        "\(DockerRecord.pick(item, ["Driver"])) · \(DockerRecord.pick(item, ["Scope"]))"
    }

    var body: some View {
        LuckyCard(spacing: LuckyTheme.Space.m) {
            HStack(spacing: LuckyTheme.Space.s + 2) {
                LuckyIconTile(symbol: DockerView.networks.symbol, size: 38, glyph: 19, tone: .info)
                VStack(alignment: .leading, spacing: LuckyTheme.Space.hair) {
                    Text(name)
                        .font(LuckyTheme.Text.cardTitle)
                        .foregroundStyle(LuckyTheme.textPrimary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(LuckyTheme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The one non-`fluid` button in the port: it hugs its label and lets the name have
                // the rest of the row.
                DockerIconButton(symbol: LuckySymbol.delete, label: "删除",
                                 tint: LuckyTheme.danger, disabled: busy) {
                    remove(key, name)
                }
            }
        }
    }
}
