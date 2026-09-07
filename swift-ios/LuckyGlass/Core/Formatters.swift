import Foundation

/// Display helpers ported verbatim from the screens.
///
/// `bytes` exists twice in the original with different unit lists and different empty
/// values, so both survive here. Merging them would change what the Docker cards show.
enum Format {
    /// `monitor.tsx` — `bytes(value, speed)`, units through PB, `0 B` when there is nothing.
    static func bytes(_ value: Double, speed: Bool = false) -> String {
        guard value.isFinite, value > 0 else { return speed ? "0 B/s" : "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        let index = unitIndex(value, count: units.count)
        let scaled = value / pow(1024, Double(index))
        return "\(JSCompat.toFixed(scaled, index == 0 ? 0 : 2)) \(units[index])\(speed ? "/s" : "")"
    }

    /// `docker-overview.tsx` / `docker.tsx` — `bytes(value)`, units through TB, `--` for zero.
    static func dockerBytes(_ value: JSONValue?) -> String {
        let size = value?.asNumber ?? 0
        guard size.isFinite, size != 0 else { return "--" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        let index = unitIndex(size, count: units.count)
        let scaled = size / pow(1024, Double(index))
        return "\(JSCompat.toFixed(scaled, index == 0 ? 0 : 2)) \(units[index])"
    }

    /// `Math.min(Math.floor(Math.log(v) / Math.log(1024)), units.length - 1)`, clamped at
    /// zero as well — the original returns `NaN undefined` for values below one byte.
    private static func unitIndex(_ value: Double, count: Int) -> Int {
        let raw = Int(floor(log(value) / log(1024)))
        return min(max(raw, 0), count - 1)
    }

    /// `percent(used, total)`
    static func percent(_ used: Double, _ total: Double) -> Double {
        total > 0 ? used / total * 100 : 0
    }

    /// `/^(?:false|0|off|no|disabled)$/i.test(value.trim())` — Lucky reports switch state as
    /// a bool, a number, or any of these words depending on the module.
    static func isDisabledWord(_ text: String) -> Bool {
        ["false", "0", "off", "no", "disabled"].contains(text.jsTrimmed.lowercased())
    }

    /// `monitor.tsx` — `asEnabled(value, fallback)`. Absent, null and `''` mean "unknown",
    /// which reads as enabled for modules that never report the field.
    static func asEnabled(_ value: JSONValue?, fallback: Bool = true) -> Bool {
        guard let value, !value.isNull else { return fallback }
        if case .string(let text) = value {
            if text.isEmpty { return fallback }
            return !isDisabledWord(text)
        }
        if case .bool(false) = value { return false }
        if case .number(let number) = value, number == 0 { return false }
        return true
    }
}
