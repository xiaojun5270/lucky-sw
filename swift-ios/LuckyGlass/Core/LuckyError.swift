import Foundation

/// Thrown when the server rejects the current token and re-login fails.
/// Views treat this specially: it routes back to the login screen.
struct LuckyAuthError: LocalizedError {
    let message: String

    init(_ message: String? = nil) {
        let trimmed = message?.jsTrimmed ?? ""
        self.message = trimmed.isEmpty ? "登录已失效，请重新登录" : trimmed
    }

    var errorDescription: String? { message }
}

/// Every other failure surfaced to the UI. The original throws bare `Error(msg)` with
/// Chinese copy that is displayed verbatim, so the message is the whole payload.
struct LuckyError: LocalizedError {
    let message: String

    init(_ message: String) { self.message = message }

    var errorDescription: String? { message }
}

extension Error {
    /// The string the original renders via `caught instanceof Error ? caught.message : fallback`.
    func luckyMessage(_ fallback: String = "请求失败") -> String {
        if let error = self as? LuckyAuthError { return error.message }
        if let error = self as? LuckyError { return error.message }
        if let error = self as? LocalizedError, let description = error.errorDescription { return description }
        if self is CancellationError { return "请求已取消" }
        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorCancelled: return "请求已取消"
            case NSURLErrorTimedOut: return "请求超时，请检查服务器连接"
            default: return nsError.localizedDescription
            }
        }
        let description = nsError.localizedDescription
        return description.isEmpty ? fallback : description
    }

    var isCancellation: Bool {
        if self is CancellationError { return true }
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
