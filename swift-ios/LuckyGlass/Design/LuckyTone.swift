import SwiftUI

/// The six meanings a surface can carry, and the colours that express them.
///
/// The hues are new but the *semantics* are the original's: `docker-overview.tsx` paints a running
/// container with `colors.success`, a paused one with `colors.warning`, an exited one with
/// `colors.danger` and a merely created one with `colors.primary`, so the same four map onto
/// `.ok` / `.warning` / `.danger` / `.brand` here.
enum LuckyTone: String, Sendable, CaseIterable {
    case ok, warning, danger, brand, info, idle

    /// Line, glyph and text colour. Also the tint handed to `Glass.tint(_:)` — which is why a tone
    /// is required to *mean* something: a tinted glass control that only looks nice is a pitfall.
    var tint: Color {
        switch self {
        case .ok: LuckyTheme.success
        case .warning: LuckyTheme.warning
        case .danger: LuckyTheme.danger
        case .brand: LuckyTheme.accent
        case .info: LuckyTheme.info
        case .idle: LuckyTheme.idle
        }
    }

    /// The same hue at fill strength, for a chip background on the content layer.
    var fill: Color {
        switch self {
        case .ok: LuckyTheme.successSoft
        case .warning: LuckyTheme.warningSoft
        case .danger: LuckyTheme.dangerSoft
        case .brand: LuckyTheme.accentSoft
        case .info: LuckyTheme.infoSoft
        case .idle: LuckyTheme.idleSoft
        }
    }

    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .brand: "sparkles"
        case .info: "info.circle.fill"
        case .idle: "moon.zzz.fill"
        }
    }

    /// `Enable` / `enable` as the lists report it, through `Format.asEnabled` so a module that
    /// answers `"off"` or `0` reads the same here as it does on the original screens.
    static func enabled(_ value: JSONValue?, fallback: Bool = true) -> LuckyTone {
        Format.asEnabled(value, fallback: fallback) ? .ok : .idle
    }

    /// A container / rule / task state word. Unknown vocabulary is `.idle` rather than `.danger`:
    /// Lucky's modules disagree about spelling and a stale word must not read as a failure.
    static func state(_ text: String?) -> LuckyTone {
        guard let text = text?.jsTrimmed.lowercased(), !text.isEmpty else { return .idle }
        if text.contains("pause") || text.contains("restart") || text.contains("removing")
            || text.contains("暂停") || text.contains("重启") { return .warning }
        if text.contains("exit") || text.contains("stopped") || text.contains("dead")
            || text.contains("fail") || text.contains("error")
            || text.contains("失败") || text.contains("异常") || text.contains("错误") { return .danger }
        if text.contains("running") || text.contains("active") || text.contains("healthy")
            || text.contains("success") || text.contains("ok")
            || text.contains("运行") || text.contains("成功") || text.contains("正常") { return .ok }
        if text.contains("created") || text.contains("pending")
            || text.contains("已创建") { return .brand }
        return .idle
    }

    /// An HTTP status line, for the endpoint debugger and the request log.
    static func httpStatus(_ status: Int) -> LuckyTone {
        switch status {
        case 200..<300: .ok
        case 300..<400: .info
        case 400..<500: .warning
        case 500...: .danger
        default: .idle
        }
    }

    /// A 0–100 utilisation reading. The thresholds are the port's own: the original monitor screen
    /// draws its bars in a single colour, which makes a full disk invisible.
    static func load(_ percent: Double) -> LuckyTone {
        guard percent.isFinite else { return .idle }
        if percent >= 90 { return .danger }
        if percent >= 75 { return .warning }
        return .ok
    }
}
