import SwiftUI

/// The app's glyph vocabulary.
///
/// The original uses lucide icons imported per screen; SF Symbols are the native equivalent and
/// they also give the tab bar and the toolbars their correct optical alignment. Every name here is
/// a symbol that has existed since iOS 16 or earlier — a missing symbol renders as a blank box, and
/// the endpoint browser draws 45 of them at once.
enum LuckySymbol {
    // MARK: - Sections

    static let dashboard = "speedometer"
    static let services = "square.stack.3d.up"
    static let docker = "cube.transparent"
    static let monitor = "waveform.path.ecg"
    static let debugger = "curlybraces.square"
    static let settings = "gearshape"
    static let logs = "text.alignleft"
    static let login = "person.badge.key"

    // MARK: - Recurring actions

    static let refresh = "arrow.clockwise"
    static let copy = "doc.on.doc"
    static let start = "play.fill"
    static let stop = "stop.fill"
    static let restart = "arrow.triangle.2.circlepath"
    static let delete = "trash"
    static let edit = "square.and.pencil"
    static let add = "plus"
    static let send = "paperplane.fill"
    static let download = "arrow.down.circle"
    static let upload = "arrow.up.circle"
    static let search = "magnifyingglass"
    static let filter = "line.3.horizontal.decrease.circle"
    static let expand = "chevron.down"
    static let external = "arrow.up.right.square"
    static let danger = "exclamationmark.triangle.fill"
    static let clock = "clock"
    static let key = "key.fill"
    static let network = "network"
    static let memory = "memorychip"
    static let cpu = "cpu"
    static let disk = "internaldrive"
    static let uptime = "clock.arrow.circlepath"

    // MARK: - Service kinds

    static func kind(_ kind: LuckyServiceKind) -> String {
        switch kind {
        case .webservice: "network"
        case .ddns: "globe.asia.australia"
        case .docker: "cube.transparent"
        case .ssl: "lock.shield"
        }
    }

    // MARK: - Registry modules

    /// One glyph per module key in `LuckyEndpoints.json`. All 45 are listed explicitly rather than
    /// pattern-matched: `stunrulelist_lite` and `portforwards_lite` would otherwise collide with
    /// their full-list siblings, and a wrong-but-plausible glyph is worse than a generic one.
    private static let moduleSymbols: [String: String] = [
        "update": "arrow.down.circle",
        "storagemanagement": "internaldrive",
        "login": "person.badge.key",
        "third": "puzzlepiece.extension",
        "thirdPartyAuthManager": "person.crop.circle.badge.checkmark",
        "ddns": "globe.asia.australia",
        "portforward": "arrow.left.arrow.right",
        "portforwards_lite": "list.dash",
        "portforwards": "list.bullet",
        "webservice": "network",
        "restoreconfigureconfirm": "arrow.counterclockwise.circle",
        "baseconfigure": "slider.horizontal.3",
        "base": "shippingbox",
        "cron": "clock.arrow.circlepath",
        "modules": "square.grid.2x2",
        "logs": "text.alignleft",
        "twofapassword": "key.fill",
        "iconlib": "photo.on.rectangle.angled",
        "logout": "rectangle.portrait.and.arrow.right",
        "wol": "power",
        "netinterfaces": "cable.connector",
        "info": "info.circle",
        "status": "waveform.path.ecg",
        "reboot_program": "arrow.triangle.2.circlepath",
        "cloudflared": "cloud",
        "coraza": "shield.lefthalf.filled",
        "ddnstasklist": "list.bullet.rectangle",
        "dlnaservice": "airplayvideo",
        "docker": "cube.transparent",
        "frp": "point.3.connected.trianglepath.dotted",
        "ftpserver": "server.rack",
        "ipregtest": "testtube.2",
        "ipfliter": "hand.raised",
        "ipdb": "tablecells",
        "lucky": "sparkles",
        "oauth": "person.badge.shield.checkmark",
        "rclone": "externaldrive.badge.icloud",
        "ssl": "lock.shield",
        "stun": "antenna.radiowaves.left.and.right",
        "stunrule": "dot.radiowaves.left.and.right",
        "stunrulelist": "list.bullet.below.rectangle",
        "stunrulelist_lite": "list.dash",
        "v2l": "v.circle",
        "webdav": "folder.badge.person.crop",
        "webterminal": "terminal",
    ]

    /// Falls back to a neutral glyph so a module added by a newer Lucky build still draws.
    static func module(_ key: String) -> String {
        moduleSymbols[key] ?? "circle.grid.2x2"
    }
}

/// Restrained endpoint marker used in rows and scene strips. The fixed-width glyph column keeps
/// titles aligned while avoiding the old grid of coloured rounded tiles.
struct LuckyIconTile: View {
    var symbol: String
    var size: CGFloat = 38
    var glyph: CGFloat = 18
    var tone: LuckyTone = .brand

    var body: some View {
        ZStack {
            Capsule()
                .fill(tone.tint.opacity(0.20))
                .frame(width: 2, height: max(18, size - 8))
                .offset(x: -(size / 2) + 2)
            Image(systemName: symbol)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(tone.tint)
                .symbolRenderingMode(.monochrome)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Presentation metadata for the three tunnel kinds, taken from the tiles in `manage.tsx`: STUN is
/// the primary tone, Cloudflared is amber and FRP is cyan.
extension TunnelKind {
    var symbol: String {
        switch self {
        case .stun: "point.3.filled.connected.trianglepath.dotted"
        case .cloudflared: "cloud"
        case .frp: "globe.asia.australia"
        }
    }

    /// `detail` on the tile.
    var detail: String {
        switch self {
        case .stun: "穿透规则与公网地址"
        case .cloudflared: "隧道与域名路由"
        case .frp: "客户端、服务端与代理"
        }
    }

    var tone: LuckyTone {
        switch self {
        case .stun: .brand
        case .cloudflared: .warning
        case .frp: .info
        }
    }
}
