import SwiftUI

/// Loading, empty, error and transient states.
///
/// Lucky's API answers with `{ret, msg}`, so almost every screen has the same three failure shapes:
/// no server configured, a request that failed with Chinese copy from the server, and an empty list
/// that is not an error. These views keep that vocabulary consistent.
struct LuckyLoadingView: View {
    var text: String = "加载中…"

    var body: some View {
        VStack(spacing: LuckyTheme.Space.m) {
            ProgressView().controlSize(.large)
            Text(text)
                .font(LuckyTheme.Text.caption)
                .foregroundStyle(LuckyTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LuckyTheme.Space.xxl)
    }
}

/// An empty list. `ContentUnavailableView` is the system's own shape for this, so it inherits the
/// right metrics and the right behaviour inside a scroll view.
struct LuckyEmptyState<Actions: View>: View {
    var symbol: String
    var title: String
    var message: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
                .font(LuckyTheme.Text.cardTitle)
        } description: {
            if let message, !message.isEmpty {
                Text(message).font(LuckyTheme.Text.body)
            }
        } actions: {
            actions()
        }
        .foregroundStyle(LuckyTheme.textSecondary)
    }
}

extension LuckyEmptyState where Actions == EmptyView {
    init(symbol: String, title: String, message: String? = nil) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// A failed request. The message is the server's own `msg` whenever there is one, which is why it
/// is selectable and allowed to wrap — some of Lucky's errors are a full sentence with a path in
/// them.
struct LuckyErrorCard: View {
    var message: String
    var title: String = "请求失败"
    var retry: (() -> Void)?

    var body: some View {
        LuckyCard(tone: .danger) {
            HStack(alignment: .top, spacing: LuckyTheme.Space.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LuckyTheme.danger)
                VStack(alignment: .leading, spacing: LuckyTheme.Space.xs) {
                    Text(title)
                        .font(LuckyTheme.Text.cardTitle)
                        .foregroundStyle(LuckyTheme.textPrimary)
                    Text(message)
                        .font(LuckyTheme.Text.body)
                        .foregroundStyle(LuckyTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            if let retry {
                LuckyPillButton(title: "重试", symbol: "arrow.clockwise", tone: .danger,
                                action: retry)
            }
        }
    }
}

/// Placeholder rows while a list loads. A shimmer is deliberately absent: the phase animation would
/// run on every row of a 300-item list, and the refresh here is usually under a second.
struct LuckySkeleton: View {
    var rows: Int = 3

    var body: some View {
        VStack(spacing: LuckyTheme.Space.stack) {
            ForEach(0..<rows, id: \.self) { index in
                LuckyCard {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LuckyTheme.surfaceRaised)
                        .frame(width: index.isMultiple(of: 2) ? 160 : 120, height: 14)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LuckyTheme.surfaceRaised)
                        .frame(height: 10)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LuckyTheme.surfaceRaised)
                        .frame(width: 90, height: 10)
                }
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

/// A transient confirmation. The original screens use `Alert.alert` for "已复制" and for the result of
/// every mutation, which stops the app dead; this port shows the same copy as a floating glass pill
/// and keeps alerts for decisions only.
struct LuckyToast: Identifiable, Equatable, Sendable {
    let id = UUID()
    var text: String
    var tone: LuckyTone = .ok
    var symbol: String?

    static func ok(_ text: String) -> LuckyToast { LuckyToast(text: text, tone: .ok) }
    static func failed(_ text: String) -> LuckyToast { LuckyToast(text: text, tone: .danger) }
    static func note(_ text: String) -> LuckyToast { LuckyToast(text: text, tone: .info) }
}

private struct LuckyToastModifier: ViewModifier {
    @Binding var toast: LuckyToast?
    /// Long server messages need longer than the usual two seconds to be read.
    private var seconds: Double { (toast?.text.count ?? 0) > 24 ? 3.6 : 2.2 }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let current = toast {
                    LuckyGlassBadge(text: current.text,
                                    symbol: current.symbol ?? current.tone.symbol,
                                    tone: current.tone)
                        .padding(.top, LuckyTheme.Space.s)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: current.id) {
                            try? await Task.sleep(for: .seconds(seconds))
                            guard !Task.isCancelled else { return }
                            withAnimation(LuckyTheme.Motion.snap) { toast = nil }
                        }
                        .onTapGesture {
                            withAnimation(LuckyTheme.Motion.snap) { toast = nil }
                        }
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .animation(LuckyTheme.Motion.snap, value: toast)
    }
}

extension View {
    /// Screens keep one `@State var toast: LuckyToast?` and set it; dismissal is automatic.
    func luckyToast(_ toast: Binding<LuckyToast?>) -> some View {
        modifier(LuckyToastModifier(toast: toast))
    }
}
