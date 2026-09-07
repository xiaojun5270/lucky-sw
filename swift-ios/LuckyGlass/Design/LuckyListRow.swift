import SwiftUI

/// A chip described by data rather than by a view, so a row built in a `ForEach` over server
/// records can declare its chips inline.
struct LuckyChipSpec: Identifiable, Hashable {
    var text: String
    var tone: LuckyTone
    var symbol: String?

    var id: String { "\(text)-\(tone.rawValue)-\(symbol ?? "")" }

    init(_ text: String, tone: LuckyTone = .idle, symbol: String? = nil) {
        self.text = text
        self.tone = tone
        self.symbol = symbol
    }
}

/// The default operational record. A parent may place many rows on one `LuckyDataRail`; the row
/// itself owns no background or shadow, so records read as a continuous ledger rather than cards.
struct LuckyListRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    /// Monospaced supporting line — a path, an address, a container id.
    var detail: String?
    var symbol: String?
    var tone: LuckyTone = .brand
    var chips: [LuckyChipSpec] = []
    var dot: LuckyTone?
    var showsChevron: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: LuckyTheme.Space.m) {
            marker
            VStack(alignment: .leading, spacing: LuckyTheme.Space.xs) {
                heading
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(LuckyTheme.Text.caption)
                        .foregroundStyle(LuckyTheme.textSecondary)
                        .lineLimit(2)
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(LuckyTheme.Text.codeSmall)
                        .foregroundStyle(LuckyTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !chips.isEmpty { metadata }
            }
            Spacer(minLength: 0)
            trailing()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LuckyTheme.textTertiary)
            }
        }
        .padding(.horizontal, LuckyTheme.Space.m)
        .padding(.vertical, LuckyTheme.Space.s)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var marker: some View {
        if let symbol {
            LuckyRailMarker(tone: tone, active: dot != nil, symbol: symbol)
        } else if let dot {
            LuckyRailMarker(tone: dot, active: true)
        }
    }

    private var heading: some View {
        HStack(spacing: LuckyTheme.Space.xs) {
            if let dot { LuckyStatusDot(tone: dot, size: 6) }
            Text(title)
                .font(LuckyTheme.Text.cardTitle)
                .foregroundStyle(LuckyTheme.textPrimary)
                .lineLimit(1)
        }
    }

    private var metadata: some View {
        LuckyWrap(spacing: LuckyTheme.Space.xs, lineSpacing: LuckyTheme.Space.xs) {
            ForEach(chips) { chip in
                LuckyChip(text: chip.text, tone: chip.tone, symbol: chip.symbol, filled: false)
            }
        }
    }
}

extension LuckyListRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, detail: String? = nil, symbol: String? = nil,
         tone: LuckyTone = .brand, chips: [LuckyChipSpec] = [], dot: LuckyTone? = nil,
         showsChevron: Bool = true) {
        self.init(title: title, subtitle: subtitle, detail: detail, symbol: symbol, tone: tone,
                  chips: chips, dot: dot, showsChevron: showsChevron) { EmptyView() }
    }
}
