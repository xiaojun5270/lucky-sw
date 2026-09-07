import SwiftUI

/// The infrastructure subsystem a screen is operating on. A scene is context, not decoration: it
/// gives the shell and accessibility summaries one vocabulary without coupling them to a service.
enum LuckySceneModule: String, Sendable {
    case overview, services, web, tunnel, docker, automation, developer, logs, settings, login
}

enum LuckyHealthState: Sendable {
    case nominal, attention, critical, unknown

    var tone: LuckyTone {
        switch self {
        case .nominal: .ok
        case .attention: .warning
        case .critical: .danger
        case .unknown: .idle
        }
    }
}

struct LuckySceneDescriptor: Sendable {
    var module: LuckySceneModule
    var title: String
    var subtitle: String = ""
    var symbol: String
    var tone: LuckyTone = .brand
    var health: LuckyHealthState = .unknown
}

private struct LuckySceneKey: EnvironmentKey {
    static let defaultValue = LuckySceneDescriptor(
        module: .overview,
        title: "Lucky",
        symbol: LuckySymbol.dashboard
    )
}

extension EnvironmentValues {
    var luckyScene: LuckySceneDescriptor {
        get { self[LuckySceneKey.self] }
        set { self[LuckySceneKey.self] = newValue }
    }
}

extension View {
    func luckyScene(_ descriptor: LuckySceneDescriptor) -> some View {
        environment(\.luckyScene, descriptor)
    }
}

/// A small control-plane header for bespoke workspaces. It avoids repeating navigation titles and
/// instead identifies the active subsystem, its health and the machine context below it.
struct LuckySceneStrip<Trailing: View>: View {
    var descriptor: LuckySceneDescriptor
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: LuckyTheme.Space.m) {
            LuckyIconTile(symbol: descriptor.symbol, size: 34, glyph: 16, tone: descriptor.tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.title)
                    .font(LuckyTheme.Text.cardTitle)
                    .foregroundStyle(LuckyTheme.textPrimary)
                if !descriptor.subtitle.isEmpty {
                    Text(descriptor.subtitle)
                        .font(LuckyTheme.Text.caption)
                        .foregroundStyle(LuckyTheme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: LuckyTheme.Space.s)
            LuckyStatusDot(tone: descriptor.health.tone)
            trailing()
        }
        .padding(.vertical, LuckyTheme.Space.xs)
    }
}

extension LuckySceneStrip where Trailing == EmptyView {
    init(_ descriptor: LuckySceneDescriptor) {
        self.init(descriptor: descriptor) { EmptyView() }
    }
}
