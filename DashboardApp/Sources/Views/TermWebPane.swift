import SwiftUI
import WebKit

// 網頁版終端機整段搬進 app（董事長 2026-09-29 TG10176「你不能把代碼整個搬過去嗎」）：
// 畫面＝同一份 xterm.js（Resources/term/term.html），傳輸＝原生 URLSessionWebSocketTask 打 /ws/terminal/{agent}?token=
// （與網頁 TerminalPage 同一條 WS），3 秒沒開／斷線→退 /api/terminal/buffer 1.5s 輪詢（同網頁 startPolling），
// 外網 18 秒沒訊息→殭屍 WS 看門切輪詢（同網頁 armWatchdog）。輸出走 termWrite(base64) 原樣 term.write。
final class TermSession: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var connected = false
    @Published var mode = ""          // "ws" / "polling" / ""
    @Published var err: String?
    weak var webView: WKWebView?
    var api: APIClient?
    var onCopy: ((String) -> Void)?

    private var agent = ""
    private var ws: URLSessionWebSocketTask?
    private var wsSession: URLSession?
    private var wsOpened = false
    private var lastMsg = Date()
    private var pollTask: Task<Void, Never>?
    private var openTimer: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var pageReady = false
    private var pending: [(String, Bool)] = []   // (chunk, isStatusLine)
    private var generation = 0
    private var afterLine = 0

    // MARK: 生命週期
    func start(agent: String) {
        stop()
        generation += 1
        self.agent = agent
        afterLine = 0
        err = nil; connected = false; mode = ""
        js("termReset()")
        guard !agent.isEmpty, let api else { return }
        let gen = generation
        let path = "/ws/terminal/" + (agent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? agent)
        guard var comps = URLComponents(url: api.url(path), resolvingAgainstBaseURL: false) else { return }
        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        comps.queryItems = [URLQueryItem(name: "token", value: api.token ?? "")]
        guard let url = comps.url else { return }
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
        wsSession = s
        wsOpened = false
        lastMsg = Date()
        let task = s.webSocketTask(with: url)
        ws = task
        task.resume()
        receive(task, gen: gen)
        // 網頁：3 秒沒 onopen → 關掉改輪詢
        openTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled, self.generation == gen, !self.wsOpened else { return }
            task.cancel(with: .goingAway, reason: nil)
            self.startPolling(gen: gen)
        }
    }
    func stop() {
        openTimer?.cancel(); openTimer = nil
        watchdog?.cancel(); watchdog = nil
        pollTask?.cancel(); pollTask = nil
        ws?.cancel(with: .goingAway, reason: nil); ws = nil
        wsSession?.invalidateAndCancel(); wsSession = nil
        wsOpened = false
    }
    deinit { stop() }

    // MARK: WS
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard webSocketTask === ws else { return }
        wsOpened = true; openTimer?.cancel()
        connected = true; mode = "ws"; err = nil; lastMsg = Date()
        armWatchdog()
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask === ws else { return }
        handleClose(gen: generation)
    }
    private func handleClose(gen: Int) {
        guard gen == generation else { return }
        if !wsOpened {
            if pollTask == nil { startPolling(gen: gen) }
        } else {
            connected = false
            line("\u{1b}[33m--- WebSocket 斷線，切換 HTTP 模式 ---\u{1b}[0m")
            startPolling(gen: gen)
        }
    }
    private func receive(_ task: URLSessionWebSocketTask, gen: Int) {
        task.receive { [weak self] result in
            guard let self, gen == self.generation, task === self.ws else { return }
            switch result {
            case .failure:
                DispatchQueue.main.async { self.handleClose(gen: gen) }
            case .success(let msg):
                var text = ""
                if case .string(let s) = msg { text = s }
                else if case .data(let d) = msg { text = String(decoding: d, as: UTF8.self) }
                DispatchQueue.main.async {
                    self.lastMsg = Date()
                    if let d = text.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                        let kind = obj["type"] as? String
                        if kind == "output", let ls = obj["lines"] as? [String] { ls.forEach { self.write($0) } }
                        else if kind == "error", let e = obj["data"] as? String { self.err = e; self.line("\u{1b}[31m\(e)\u{1b}[0m") }
                    } else { self.write(text) }
                }
                self.receive(task, gen: gen)
            }
        }
    }
    func sendInput(_ data: String) -> Bool {
        guard let ws, wsOpened, connected, mode == "ws" else { return false }
        if let d = try? JSONSerialization.data(withJSONObject: ["type": "input", "data": data]), let s = String(data: d, encoding: .utf8) {
            ws.send(.string(s)) { _ in }
            return true
        }
        return false
    }
    func sendResize(cols: Int, rows: Int) {
        guard let ws, wsOpened else { return }
        if let d = try? JSONSerialization.data(withJSONObject: ["type": "resize", "cols": cols, "rows": rows]), let s = String(data: d, encoding: .utf8) {
            ws.send(.string(s)) { _ in }
        }
    }
    // 只在非直連（外網 Funnel / 中繼）武裝：18 秒沒訊息＝殭屍 WS → 切輪詢（網頁 armWatchdog 同款）
    private func armWatchdog() {
        guard let host = api?.baseURL.host?.lowercased() else { return }
        let direct = host == "localhost" || host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.")
            || host.range(of: "^172\\.(1[6-9]|2[0-9]|3[01])\\.", options: .regularExpression) != nil
            || host.range(of: "^100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.", options: .regularExpression) != nil
        if direct { return }
        let gen = generation
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self, self.generation == gen, self.pollTask == nil else { return }
                if Date().timeIntervalSince(self.lastMsg) > 18 {
                    self.ws?.cancel(with: .goingAway, reason: nil)
                    self.startPolling(gen: gen)
                    return
                }
            }
        }
    }

    // MARK: HTTP 輪詢（網頁 startPolling：1.5s /api/terminal/buffer?after=）
    private func startPolling(gen: Int) {
        guard pollTask == nil, gen == generation, let api else { return }
        watchdog?.cancel(); watchdog = nil
        mode = "polling"; connected = true
        line("--- HTTP 模式（外網自動切換）---")
        let name = agent
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == gen else { return }
                do {
                    let b: TerminalBuffer = try await api.request("/api/terminal/buffer/\(name)?after=\(self.afterLine)")
                    if b.source == "none" { self.err = "此員工未在運行，先到員工頁啟動"; self.connected = false }
                    else if let ls = b.lines, !ls.isEmpty { ls.forEach { self.write($0) }; self.afterLine = b.total ?? self.afterLine; self.connected = true; self.err = nil }
                } catch let e as APIError where e.status == 404 { self.err = "此員工未在運行，先到員工頁啟動"; self.connected = false }
                catch {}
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    // MARK: 寫進 xterm
    func write(_ chunk: String) { push(chunk, false) }
    func line(_ text: String) { push(text, true) }
    private func push(_ s: String, _ isLine: Bool) {
        guard !s.isEmpty else { return }
        if !pageReady || webView == nil { pending.append((s, isLine)); return }
        let b = Data(s.utf8).base64EncodedString()
        js(isLine ? "termLine('\(b)')" : "termWrite('\(b)')")
    }
    func pageDidLoad() {
        pageReady = true
        let q = pending; pending = []
        q.forEach { push($0.0, $0.1) }
        if let e = err { js("termHint('\(Data(e.utf8).base64EncodedString())')") }
    }
    func copyAll(_ done: @escaping (String) -> Void) {
        webView?.evaluateJavaScript("termText()") { v, _ in done(v as? String ?? "") }
    }
    private func js(_ code: String) { webView?.evaluateJavaScript(code) { _, _ in } }
}

struct TermWebPane: UIViewRepresentable {
    @ObservedObject var session: TermSession
    var onInput: (String) -> Void      // xterm 鍵盤輸入（WS 不在就走 HTTP /api/terminal/input）

    func makeCoordinator() -> Coord { Coord(self) }
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "term")
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.isOpaque = false
        w.backgroundColor = UIColor(red: 0x1c/255, green: 0x19/255, blue: 0x17/255, alpha: 1)
        w.scrollView.isScrollEnabled = false
        w.scrollView.contentInsetAdjustmentBehavior = .never
        w.navigationDelegate = context.coordinator
        session.webView = w
        if let url = Bundle.main.url(forResource: "term", withExtension: "html", subdirectory: "term") {
            w.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else if let url = Bundle.main.url(forResource: "term", withExtension: "html") {
            w.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return w
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { context.coordinator.parent = self }

    final class Coord: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: TermWebPane
        init(_ p: TermWebPane) { parent = p }
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let body = m.body as? [String: Any], let t = body["type"] as? String else { return }
            switch t {
            case "ready": parent.session.pageDidLoad()
            case "input": if let d = body["data"] as? String { parent.onInput(d) }
            case "resize":
                if let c = body["cols"] as? Int, let r = body["rows"] as? Int { parent.session.sendResize(cols: c, rows: r) }
            case "copy": if let d = body["data"] as? String { UIPasteboard.general.string = d; parent.session.onCopy?(d) }
            default: break
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { parent.session.pageDidLoad() }
    }
}
