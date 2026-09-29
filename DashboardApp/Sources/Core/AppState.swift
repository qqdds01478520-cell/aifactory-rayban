import SwiftUI
import LocalAuthentication
import UserNotifications
import BackgroundTasks

// 出貨版不得內建任何伺服器網址（董事長 9/29 驗收：新客戶開 app 看到陌生人的 URL）。
// 空字串＝尚未設定 → RootView 顯示「連線設定」（掃 QR／手動輸入）；設定值存 UserDefaults aif_base。
let DEFAULT_BASE = ""
// 尚未設定伺服器時 APIClient 的佔位網址（不會真的被打：所有請求／WebView 都以 hasBase 閘住）
let PLACEHOLDER_BASE = URL(string: "http://aifactory.invalid")!
let RELAY_BASE = "https://rayban-relay.goingtosheon.workers.dev"
let BG_REFRESH_ID = "com.aifactory.dashboard.refresh"

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @AppStorage("aif_base") var baseString: String = DEFAULT_BASE { didSet { hasBase = AppState.normalizeBase(baseString) != nil } }
    @AppStorage("aif_user") var username: String = ""
    @AppStorage("aif_role") var role: String = ""
    @AppStorage("aif_faceid") var faceIDEnabled: Bool = false
    @AppStorage("aif_haptics") var hapticsEnabled: Bool = true
    @AppStorage("aif_bg") var bgRefreshEnabled: Bool = true
    @AppStorage("aif_dispatch_agent") var dispatchAgent: String = "COO"
    @AppStorage("aif_last_bg") var lastBackgroundRefresh: Double = 0

    @Published var hasBase: Bool = false        // 已設定伺服器網址（false → 顯示連線設定畫面）
    @Published var loggedIn: Bool = false
    @Published var locked: Bool = false
    @Published var offline: Bool = false
    @Published var lastError: String?

    @Published var agents: [Agent] = []
    @Published var env: String = ""
    @Published var tenant: String = ""
    @Published var health: HealthResponse?
    @Published var usage: [String: UsageAgent] = [:]
    @Published var usageLoading = false
    @Published var groups: [ChatGroup] = []
    @Published var readMarks: [Int: Int] = DiskCache.load([Int: Int].self, key: "readmarks") ?? [:]
    @Published var pushStatus: String = "—"
    @Published var pendingShare: String?     // 分享表單／URL scheme 進來待派工的文字

    let api: APIClient
    var isAdmin: Bool { role == "admin" || role == "owner" }
    var senderName: String { username.isEmpty ? "Chairman" : username }

    private init() {
        let stored = AppState.normalizeBase(UserDefaults.standard.string(forKey: "aif_base") ?? DEFAULT_BASE)
        api = APIClient(baseURL: stored ?? PLACEHOLDER_BASE)
        hasBase = stored != nil
        api.token = Keychain.get("token")
        api.refreshToken = Keychain.get("refresh")
        api.onTokens = { t, r in
            Keychain.set(t, for: "token")
            if let r { Keychain.set(r, for: "refresh") }
        }
        api.onSessionExpired = { [weak self] in Task { @MainActor in self?.logout(keepServer: true) } }
        loggedIn = api.token != nil
        locked = loggedIn && faceIDEnabled
        // 離線快取先上畫面
        if let s = DiskCache.load(StateResponse.self, key: "state") { agents = s.agents; env = s.env ?? ""; tenant = s.tenant ?? "" }
        if let g = DiskCache.load(GroupsResponse.self, key: "groups") { groups = g.groups }
        if let h = DiskCache.load(HealthResponse.self, key: "health") { health = h }
        if let u = DiskCache.load([String: UsageAgent].self, key: "usage") { usage = u }
    }

    // MARK: server base
    // 網址正規化：去頭尾空白＋去尾斜線；只收 http(s) 且有 host，其餘回 nil
    nonisolated static func normalizeBase(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty, let u = URL(string: s), let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let h = u.host, !h.isEmpty else { return nil }
        return u
    }
    // 掃 QR／手動輸入／aifactory://connect 共用入口；成功＝存 aif_base＋切 APIClient，回 true
    @discardableResult
    func setBase(_ raw: String) -> Bool {
        guard let u = AppState.normalizeBase(raw) else { return false }
        api.baseURL = u
        baseString = u.absoluteString
        hasBase = true
        offline = false; lastError = nil
        return true
    }
    // QR 內容可能是純網址，或 aifactory://connect?base=<網址>（電腦版精靈兩種都可能出）
    nonisolated static func baseFromScan(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizeBase(t) != nil { return t }
        if let u = URL(string: t), u.scheme?.lowercased() == "aifactory",
           let q = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems,
           let b = q.first(where: { $0.name == "base" || $0.name == "url" })?.value, normalizeBase(b) != nil { return b }
        return nil
    }

    // MARK: auth
    func login(user: String, pass: String, server: String) async throws {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: trimmed), u.scheme != nil else { throw APIError(status: 0, message: "bad server url") }
        api.baseURL = u
        baseString = trimmed
        let r: LoginResponse = try await api.request("/api/auth/login", method: "POST",
                                                     body: ["username": user, "password": pass], auth: false, retry: false)
        await finishLogin(r, user: user)
    }
    // 設定伺服器網址（登入前 needs-setup / register / reset 也要打對台）
    func applyServer(_ server: String) throws {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: trimmed), u.scheme != nil else { throw APIError(status: 0, message: L("伺服器網址格式不對")) }
        api.baseURL = u
        baseString = trimmed
    }
    // 登入／註冊／首次建帳 拿到 token 後共用
    func finishLogin(_ r: LoginResponse, user: String) async {
        api.token = r.token
        api.refreshToken = r.refresh_token
        Keychain.set(r.token, for: "token")
        if let rt = r.refresh_token { Keychain.set(rt, for: "refresh") }
        username = r.username ?? user
        role = r.role ?? "user"
        loggedIn = true
        locked = false
        Haptic.success()
        await refreshAll()
    }

    func logout(keepServer: Bool = true) {
        Keychain.delete("token"); Keychain.delete("refresh")
        api.token = nil; api.refreshToken = nil
        loggedIn = false; locked = false
        agents = []; groups = []; usage = [:]
        DiskCache.clear()
    }

    // MARK: Face ID（B1）
    func unlock() async {
        let ctx = LAContext()
        ctx.localizedCancelTitle = L("取消")
        var err: NSError?
        let policy: LAPolicy = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
            ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        do {
            let ok = try await ctx.evaluatePolicy(policy, localizedReason: L("使用 Face ID 解鎖控制台"))
            if ok { locked = false; Haptic.success() }
        } catch { /* 留在鎖定畫面 */ }
    }
    func lockIfNeeded() { if loggedIn && faceIDEnabled { locked = true } }

    // MARK: data
    func refreshAll() async {
        async let a: () = refreshState()
        async let b: () = refreshHealth()
        async let c: () = refreshGroups()
        _ = await (a, b, c)
        if usage.isEmpty { Task { await refreshUsage() } }
    }

    func refreshState() async {
        guard hasBase else { return }
        do {
            let s: StateResponse = try await api.request("/api/state")
            agents = s.agents; env = s.env ?? ""; tenant = s.tenant ?? ""
            offline = false
            DiskCache.save(s, key: "state")
        } catch let e as APIError where e.isAuth {
        } catch { offline = true; lastError = error.localizedDescription }
    }
    func refreshHealth() async {
        guard hasBase else { return }
        do {
            let h: HealthResponse = try await api.request("/api/health", auth: false, retry: false, timeout: 10)
            health = h; DiskCache.save(h, key: "health")
        } catch { }
    }
    func refreshGroups() async {
        guard hasBase else { return }
        do {
            let g: GroupsResponse = try await api.request("/api/group-chat/groups")
            groups = g.groups.sorted { ($0.last_ts ?? 0, $0.last_msg_id ?? 0) > ($1.last_ts ?? 0, $1.last_msg_id ?? 0) }
            DiskCache.save(GroupsResponse(groups: groups), key: "groups")
        } catch { }
    }
    // /api/usage 首掃可能數分鐘 → 長逾時、失敗靜默
    func refreshUsage() async {
        if usageLoading || !hasBase { return }
        usageLoading = true
        defer { usageLoading = false }
        do {
            let u: UsageResponse = try await api.request("/api/usage?range=7d&granularity=day", timeout: 180)
            var m: [String: UsageAgent] = [:]
            for a in u.agents ?? [] { m[a.name] = a }
            usage = m; DiskCache.save(m, key: "usage")
        } catch { }
    }

    var sortedAgents: [Agent] {
        agents.sorted { a, b in
            if a.isRunning != b.isRunning { return a.isRunning }
            let ua = usage[a.name]?.total7d ?? 0, ub = usage[b.name]?.total7d ?? 0
            if ua != ub { return ua > ub }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }
    var tokens7d: Double { usage.values.reduce(0) { $0 + ($1.input ?? 0) + ($1.output ?? 0) } }
    var unreadTotal: Int { groups.filter { ($0.last_msg_id ?? 0) > (readMarks[$0.id] ?? 0) }.count }
    func markRead(_ g: ChatGroup) {
        readMarks[g.id] = max(readMarks[g.id] ?? 0, g.last_msg_id ?? 0)
        DiskCache.save(readMarks, key: "readmarks")
    }

    func startAgent(_ name: String) async -> String? {
        do {
            let r: OkResponse = try await api.request("/api/agents/\(name)/start", method: "POST", timeout: 60)
            if r.ok == false { Haptic.error(); return r.error ?? "start failed" }
            Haptic.success(); await refreshState(); return nil
        } catch { Haptic.error(); return error.localizedDescription }
    }
    func stopAgent(_ name: String) async -> String? {
        do {
            let _: OkResponse = try await api.request("/api/agents/\(name)/stop", method: "POST", timeout: 60)
            Haptic.medium(); await refreshState(); return nil
        } catch { Haptic.error(); return error.localizedDescription }
    }
    // 派工到員工終端機（B6 分享／URL scheme 落點）：走 group_reply=true 一般文字＝boss 信封
    func dispatch(text: String, to agent: String) async -> String? {
        guard hasBase else { return L("尚未設定伺服器網址") }
        do {
            let _: OkResponse = try await api.request("/api/terminal/input", method: "POST",
                                                      body: ["name": agent, "text": text, "group_reply": true])
            Haptic.success(); return nil
        } catch { Haptic.error(); return error.localizedDescription }
    }

    // MARK: push（B4）
    func registerPushToken(hex: String) {
        let key = (Bundle.main.object(forInfoDictionaryKey: "RelayAuthKey") as? String) ?? ""
        guard var comps = URLComponents(string: RELAY_BASE + "/dash-token") else { return }
        comps.queryItems = [URLQueryItem(name: "k", value: key)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone) AIFactory/2.0", forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": hex, "user": username, "app": "dashboard-native"])
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            Task { @MainActor in self.pushStatus = code == 200 ? "已註冊" : "註冊失敗 \(code)" }
        }.resume()
    }

    // MARK: background refresh（B10）
    func scheduleBackgroundRefresh() {
        guard bgRefreshEnabled else { return }
        let req = BGAppRefreshTaskRequest(identifier: BG_REFRESH_ID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }
    func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()
        let work = Task { @MainActor in
            await refreshState()
            await refreshGroups()
            lastBackgroundRefresh = Date().timeIntervalSince1970
            task.setTaskCompleted(success: !offline)
        }
        task.expirationHandler = { work.cancel(); task.setTaskCompleted(success: false) }
    }
}
