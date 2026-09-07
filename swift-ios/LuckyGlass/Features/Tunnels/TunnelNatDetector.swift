import SwiftUI

/// `NatDetector` — the NAT-type probe, on `/api/natdetect/ws`.
///
/// The socket is one-shot: the module streams `log` lines while it probes and finishes with a
/// `result` or an `error`, at which point the run stops itself. `generation` stands in for the
/// original's `socketRef.current !== socket` guard, so a frame from a socket that 停止检测 has
/// already abandoned is dropped rather than appended to a later run's output.
struct TunnelNatDetector: View {
    var close: () -> Void

    @State private var server = "stun.miwifi.com:3478"
    @State private var lines: [String] = []
    @State private var busy = false
    @State private var generation = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        ServiceSheet(title: "NAT 类型检测", close: dismiss) {
            LuckyPillButton(title: busy ? "停止检测" : "开始检测", symbol: LuckySymbol.network,
                            prominent: !busy) {
                if busy { stop() } else { start() }
            }
        } content: {
            LuckyCard {
                LuckyTextField(label: "STUN 服务器", text: $server, mono: true)
                    .disabled(busy)
            }
            if !lines.isEmpty {
                // The original leaves its modal's `ScrollView` wherever the user left it. A probe
                // that streams for up to a minute is what `follows` exists for.
                LuckyLogView(lines: lines, follows: true, height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: LuckyTheme.Radius.card,
                                                style: .continuous))
            }
        }
        .onDisappear { stop() }
    }

    private func dismiss() {
        stop()
        close()
    }
}

// MARK: - Running

extension TunnelNatDetector {
    /// `start()`. Bumping the generation first is what makes a second tap on 开始检测 abandon the
    /// socket the first one opened, exactly as reassigning `socketRef.current` does.
    private func start() {
        stop()
        lines = []
        let target = server.jsTrimmed
        guard !target.isEmpty else {
            lines = ["请填写 STUN 服务器"]
            return
        }
        let credentials = LuckySession.shared.credentials
        guard let url = Self.socketURL(baseUrl: credentials.baseUrl, token: credentials.token,
                                       server: target) else {
            // `catch (e) { setLines([…]) }` around the `new URL(…)` the original builds.
            lines = ["无法启动检测"]
            return
        }
        busy = true
        generation += 1
        let mine = generation
        task = Task { await listen(url, generation: mine) }
    }

    /// `stop()` — `clearTimeout`, drop the ref, close the socket, clear the flag. The timeout and
    /// the receive loop both live inside `task`, so cancelling it does the first and the third.
    private func stop() {
        generation += 1
        task?.cancel()
        task = nil
        busy = false
    }

    private func listen(_ url: URL, generation mine: Int) async {
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
        defer { socket.cancel() }
        // `setTimeout(…, 60000)`. A probe that has not answered inside a minute never will.
        let deadline = Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, generation == mine else { return }
            append("检测超时")
            stop()
        }
        defer { deadline.cancel() }
        while !Task.isCancelled, generation == mine {
            do {
                let message = try await socket.receive()
                guard generation == mine, handle(message) else { continue }
                stop()
                return
            } catch {
                guard !Task.isCancelled, generation == mine else { return }
                // `onclose` stops the run without saying anything; only `onerror` reports. A server
                // that sent a close frame has set `closeCode`, which is how the two are told apart.
                if socket.closeCode == .invalid {
                    append("检测连接失败，请检查服务端连接")
                }
                stop()
                return
            }
        }
    }
}

// MARK: - Frames

extension TunnelNatDetector {
    /// `socket.onmessage`. A frame that parses as JSON contributes `log`, `result` or `error` — in
    /// that order — and one that does not is appended verbatim. The answer is whether it ended.
    private func handle(_ message: URLSessionWebSocketTask.Message) -> Bool {
        let raw: String
        switch message {
        case .string(let text): raw = text
        case .data(let payload): raw = String(decoding: payload, as: UTF8.self)
        @unknown default: return false
        }
        guard let payload = JSONParser.tryParse(raw) else {
            // The `catch` branch appends the frame as it arrived, skipping the emptiness filter the
            // JSON branch applies — so a frame of whitespace does leave a blank line behind.
            lines = Array((lines + [raw]).suffix(200))
            return false
        }
        append(TunnelRecord.text(first(payload, of: ["log", "result", "error"])))
        // `if (data.result || data.error)` is truthiness, so a `result` of 0 or "" keeps probing.
        return payload["result"]?.isTruthy == true || payload["error"]?.isTruthy == true
    }

    /// `data.log ?? data.result ?? data.error` — `??` steps over `null` but stops at anything else,
    /// including an object, which `text` then renders as the empty string.
    private func first(_ payload: JSONValue, of keys: [String]) -> JSONValue? {
        for key in keys {
            guard let value = payload[key], !value.isNull else { continue }
            return value
        }
        return nil
    }

    /// `setLines(current => [...current, line].filter(Boolean).slice(-200))`. The filter runs over
    /// the whole array, so an empty line an earlier non-JSON frame left behind goes with it.
    ///
    /// The 检测超时 and 检测连接失败 lines route through here too. The original appends those without
    /// the cap, which can only ever matter for the single line that ends the run.
    private func append(_ line: String) {
        lines = Array((lines + [line]).filter { !$0.isEmpty }.suffix(200))
    }

    /// `new URL(…)` with `http`→`ws`, then the three parameters `URLSearchParams` writes.
    static func socketURL(baseUrl: String, token: String, server: String) -> URL? {
        var base = baseUrl.jsTrimmed.withoutTrailingSlashes
        if let range = base.range(of: "http:", options: [.caseInsensitive, .anchored]) {
            base.replaceSubrange(range, with: "ws:")
        } else if let range = base.range(of: "https:", options: [.caseInsensitive, .anchored]) {
            base.replaceSubrange(range, with: "wss:")
        }
        let stamp = Int64(Date().timeIntervalSince1970 * 1000)
        let query = LuckyQuery.form([
            ("Lucky-Admin-Token", .string(token)),
            ("server", .string(server)),
            ("_", .string(String(stamp))),
        ])
        return URL(string: "\(base)/api/natdetect/ws?\(query)")
    }
}
