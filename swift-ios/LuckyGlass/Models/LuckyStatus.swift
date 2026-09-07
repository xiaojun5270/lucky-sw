import Foundation

/// `LuckyStatusSample` — one point in the rolling history the monitor screen charts.
struct LuckyStatusSample: Sendable, Hashable {
    var time: Double = 0
    var systemCpuPercent: Double = 0
    var processCpuPercent: Double = 0
    var totalMem: Double = 0
    var usedMem: Double = 0
    var netInTransfer: Double = 0
    var netOutTransfer: Double = 0
    var netInSpeed: Double = 0
    var netOutSpeed: Double = 0
}

/// `LuckyLiveStatus` — the decoded `StatusMsg` frame.
///
/// Every numeric field is a `Double` on purpose: the wire types are a mix of `uint64`,
/// `int64` and `float`, and the original coerces all of them with `Number(value) || 0`
/// before display, so widening here keeps the formatting identical.
struct LuckyLiveStatus: Sendable, Hashable {
    var totalMem: Double = 0
    var usedMem: Double = 0
    var usedCpu: Double = 0
    var currentProcessUsedCpu: Double = 0
    var goroutine: Double = 0
    var processUsedMem: Double = 0
    var netIn: Double = 0
    var netOut: Double = 0
    var lastNetInSpeed: Double = 0
    var lastNetOutSpeed: Double = 0
    var handleCount: Double = 0
    var numGc: Double = 0
    var heapInuse: Double = 0
    var runTime: String = ""
    var queryTime: String = ""
    var history: [LuckyStatusSample] = []
}

enum LuckyStatusConstants {
    /// `STATUS_UPDATE_INTERVAL = 1000`
    static let updateInterval: TimeInterval = 1
    /// `STATUS_HISTORY_LIMIT = 90`
    static let historyLimit = 90
    /// `reconnectDelay` starts here, doubles, and caps at `maxReconnectDelay`.
    static let reconnectDelay: TimeInterval = 1
    static let maxReconnectDelay: TimeInterval = 15
}
