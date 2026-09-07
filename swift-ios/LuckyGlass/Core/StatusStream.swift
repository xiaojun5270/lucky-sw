import Foundation
import Observation

/// Port of `useLuckyStatus`. The hook's local variables become stored properties: the
/// socket, the reconnect backoff, and the "latest frame wins" throttle.
///
/// One shared instance is reference-counted instead of one socket per view. The original
/// creates a socket per focused screen, but only the focused screen ever has one, so the
/// observable difference is that the chart keeps its last frame across tab switches
/// instead of blanking for a second — every frame carries the full 90-sample history.
@MainActor
@Observable
final class LuckyStatusStore {
    static let shared = LuckyStatusStore()

    private(set) var data: LuckyLiveStatus?
    private(set) var connected = false
    private(set) var error = ""

    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var runner: Task<Void, Never>?
    private var flushTimer: Task<Void, Never>?
    private var holders = 0
    /// Bumped on every start/stop so a decode that finishes late cannot publish into a
    /// newer connection — this is the `disposed` flag from the hook's closure.
    private var generation = 0

    private var pending: Data?
    private var lastUpdate: Date = .distantPast
    private var decoding = false

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    // MARK: - Lifecycle

    func retain() {
        holders += 1
        guard runner == nil else { return }
        generation += 1
        let current = generation
        runner = Task { [weak self] in await self?.run(generation: current) }
    }

    func release() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        generation += 1
        runner?.cancel()
        runner = nil
        flushTimer?.cancel()
        flushTimer = nil
        socket?.cancel()
        socket = nil
        pending = nil
        decoding = false
        connected = false
    }

    // MARK: - Connection

    private func run(generation: Int) async {
        var delay = LuckyStatusConstants.reconnectDelay
        while !Task.isCancelled, generation == self.generation {
            let credentials = LuckySession.shared.credentials
            // `connect()` bails out without scheduling a reconnect when there is nothing
            // to authenticate with.
            guard !credentials.baseUrl.isEmpty, !credentials.token.isEmpty else { return }
            guard let url = Self.socketURL(baseUrl: credentials.baseUrl, token: credentials.token) else {
                error = "实时状态连接失败"
                return
            }

            let socket = session.webSocketTask(with: url)
            self.socket = socket
            socket.resume()

            let opened = await receiveLoop(
                socket: socket,
                socketToken: credentials.token,
                generation: generation
            )
            socket.cancel()
            if self.socket === socket { self.socket = nil }
            guard !Task.isCancelled, generation == self.generation else { return }
            connected = false

            // The backoff resets once a connection has produced anything.
            if opened { delay = LuckyStatusConstants.reconnectDelay }
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, LuckyStatusConstants.maxReconnectDelay)
        }
    }

    /// Returns whether the socket ever delivered a frame, which stands in for `onopen`.
    private func receiveLoop(
        socket: URLSessionWebSocketTask,
        socketToken: String,
        generation: Int
    ) async -> Bool {
        var opened = false
        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await socket.receive()
            } catch {
                // A transport failure leaves no close code — that is the original's
                // `onerror`. A clean close from the server is silent, as `onclose` is.
                if !Task.isCancelled, generation == self.generation, socket.closeCode == .invalid {
                    self.error = "实时状态连接失败"
                }
                return opened
            }
            guard !Task.isCancelled, generation == self.generation else { return opened }

            if !opened {
                // The original clears the error in `onopen`; the first frame is the
                // earliest signal available without a session delegate.
                opened = true
                error = ""
            }

            switch message {
            case .string(let text):
                if await handleText(text, socketToken: socketToken, generation: generation) { return opened }
            case .data(let payload):
                pending = payload
                flush(generation: generation)
            @unknown default:
                error = "无法识别状态数据格式"
            }
        }
    }

    /// String frames are never status data: they are either an auth complaint or an error.
    /// Returns `true` when the socket should be dropped so it reconnects with a new token.
    private func handleText(_ text: String, socketToken: String, generation: Int) async -> Bool {
        guard JSRegex.containsAny(text, ["token", "login", "invalid"]) else {
            error = text.isEmpty ? "状态服务返回了错误" : text
            return false
        }
        do {
            // Skip the refresh if another request already replaced the token this socket used.
            if socketToken == LuckySession.shared.token {
                _ = try await LuckyClient.shared.refreshToken()
            }
            if generation == self.generation { error = "" }
        } catch {
            await LuckySession.shared.end()
            if generation == self.generation { self.error = "登录已失效，请重新登录" }
        }
        return true
    }

    // MARK: - Throttled decoding

    /// `flushStatus` — at most one frame per second, always the newest one, and never two
    /// decodes at once. Frames arrive faster than the charts can usefully redraw.
    private func flush(generation: Int) {
        guard generation == self.generation, !decoding, let payload = pending else { return }
        let wait = LuckyStatusConstants.updateInterval - Date().timeIntervalSince(lastUpdate)
        if wait > 0 {
            guard flushTimer == nil else { return }
            flushTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard let self, !Task.isCancelled else { return }
                self.flushTimer = nil
                self.flush(generation: generation)
            }
            return
        }

        pending = nil
        decoding = true
        Task { [weak self] in
            // Inflate and decode off the main actor: a frame carries 90 samples.
            let decoded = await Task.detached(priority: .userInitiated) {
                do { return Result<LuckyLiveStatus, LuckyError>.success(try LuckyLiveStatus.decode(gzipped: payload)) }
                catch { return .failure(LuckyError(error.luckyMessage("状态数据解析失败"))) }
            }.value
            guard let self else { return }
            self.apply(decoded, generation: generation)
        }
    }

    private func apply(_ decoded: Result<LuckyLiveStatus, LuckyError>, generation: Int) {
        defer {
            decoding = false
            if pending != nil { flush(generation: generation) }
        }
        guard generation == self.generation else { return }
        switch decoded {
        case .success(let status):
            lastUpdate = Date()
            data = status
            connected = true
            error = ""
        case .failure(let failure):
            error = failure.message
        }
    }

    // MARK: - URL

    /// `statusSocketUrl()` — `http`→`ws`, `https`→`wss`, token in the query string
    /// because there is no way to set headers on a browser WebSocket. The `_` parameter is
    /// the raw millisecond clock here, not the request nonce.
    static func socketURL(baseUrl: String, token: String, millis: Int64? = nil) -> URL? {
        var base = baseUrl.jsTrimmed.withoutTrailingSlashes
        if let range = base.range(of: "http:", options: [.caseInsensitive, .anchored]) {
            base.replaceSubrange(range, with: "ws:")
        } else if let range = base.range(of: "https:", options: [.caseInsensitive, .anchored]) {
            base.replaceSubrange(range, with: "wss:")
        }
        let stamp = millis ?? Int64(Date().timeIntervalSince1970 * 1000)
        let query = "?Lucky-Admin-Token=\(JSCompat.encodeURIComponent(token))&_=\(stamp)"
        return URL(string: "\(base)/api/status/ws\(query)")
    }
}
