import SwiftUI

/// The page scaffold every screen is built on: ambient backdrop, one scroll view, page margins, and
/// the soft scroll edge effect that lets content fade under the glass navigation bar.
///
/// Screens supply only their cards. Nothing here is glass — the glass in a page comes from the
/// system chrome (nav bar, tab bar) and from whatever the screen puts in a `safeAreaBar`.
struct LuckyPage<Content: View>: View {
    var spacing: CGFloat = LuckyTheme.Space.stack
    /// Pull-to-refresh. Most screens have a refresh action; the login screen does not.
    var refresh: (@Sendable () async -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            LuckyBackdrop()
            scroll
        }
    }

    @ViewBuilder
    private var scroll: some View {
        if let refresh {
            base.refreshable { await refresh() }
        } else {
            base
        }
    }

    private var base: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing, content: content)
                .padding(.horizontal, LuckyTheme.Space.gutter)
                .padding(.top, LuckyTheme.Space.s)
                .padding(.bottom, LuckyTheme.Space.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Soft at the top so cards dissolve under the title; hard at the bottom so a list does not
        // smear into the tab bar while scrolling.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }
}

/// The hero block at the top of the dashboard: the server it is talking to, its version, and
/// whether the status socket is live. Deliberately not a card — it reads as part of the page, and
/// the nav bar's glass passes over it.
struct LuckyPageHero<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var detail: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: LuckyTheme.Space.m) {
            VStack(alignment: .leading, spacing: LuckyTheme.Space.xs) {
                Text(title)
                    .font(LuckyTheme.Text.hero)
                    .foregroundStyle(LuckyTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(LuckyTheme.Text.body)
                        .foregroundStyle(LuckyTheme.textSecondary)
                        .lineLimit(2)
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(LuckyTheme.Text.codeSmall)
                        .foregroundStyle(LuckyTheme.textTertiary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.bottom, LuckyTheme.Space.xs)
    }
}

extension LuckyPageHero where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, detail: String? = nil) {
        self.init(title: title, subtitle: subtitle, detail: detail) { EmptyView() }
    }
}

extension View {
    /// `<Page title subtitle>` from `src/components/lucky-ui.tsx`, which draws an icon tile, a
    /// 26pt title and a caption at the top of the scroll view. Here the pair goes to the real
    /// navigation bar — iOS 26's `navigationSubtitle` is exactly this shape — so the title
    /// collapses on scroll and the glass bar refracts the cards passing under it.
    func luckyTitle(_ title: String, _ subtitle: String? = nil) -> some View {
        navigationTitle(title)
            .navigationSubtitle(subtitle ?? "")
    }

    /// The bottom action bar used by the editors and the debugger. `safeAreaBar` rather than
    /// `safeAreaInset` because only the former extends the scroll view's edge effect under the bar.
    func luckyActionBar<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        safeAreaBar(edge: .bottom) {
            LuckyGlassBar(content: content)
        }
    }
}

/// A grid of equal-width tiles that stays readable from an iPhone SE to a Max. Used for the
/// dashboard metrics and the Docker state summary, both of which are fixed-length — hence
/// `LazyVGrid` only for the column maths, not for lazy loading.
struct LuckyTileGrid<Content: View>: View {
    var minimum: CGFloat = 150
    var spacing: CGFloat = LuckyTheme.Space.s
    @ViewBuilder var content: () -> Content

    var body: some View {
        let column = GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .topLeading)
        LazyVGrid(columns: [column], alignment: .leading, spacing: spacing, content: content)
    }
}
