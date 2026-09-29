import SwiftUI
import LocalAuthentication
import UserNotifications
import BackgroundTasks

let DEFAULT_BASE = "https://aifactory-dashboard.tail825b5f.ts.net"
let RELAY_BASE = "https://rayban-relay.goingtosheon.workers.dev"
let BG_REFRESH_ID = "com.aifactory.dashboard.refresh"

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @AppStorage("aif_base") var baseString: String = DEFAULT_BASE
    @AppStorage("aif_user") var username: String = ""
    @AppStorage("aif_role") var role: String = ""
    @AppStorage("aif_faceid") var faceIDEnabled: Bool = false
    @AppStorage("aif_haptics") var hapticsEnabled: Bool = true
    @AppStorage("aif_bg") var bgRefreshEnabled: Bool = true
    @AppStorage("aif_dispatch_agent") var dispatchAgent: String = "COO"
    @AppStorage("aif_last_bg") var lastBackgroundRefresh: Double = 0

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
        api = APIClient(baseURL: URL(string: UserDefaults.standard.string(forKey: "aif_base") ?? DEFAULT_BASE) ?? URL(string: DEFAULT_BASE)!)
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

    // MARK: auth
    func login(user: String, pass: String, server: String) async throws {
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: trimmed), u.scheme != nil else { throw APIError(status: 0, message: "bad server url") }
        api.baseURL = u
        baseString = trimmed
        let r: LoginResponse = try await api.request("/api/auth/login", method: "POST",
                                                     body: ["username": user, "password": pass], auth: false, retry: false)
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
        ctx.localizedCancelTitle = L("common.cancel")
        var err: NSError?
        let policy: LAPolicy = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
            ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        do {
            let ok = try await ctx.evaluatePolicy(policy, localizedReason: L("login.faceid"))
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
        do {
            let s: StateResponse = try await api.request("/api/state")
            agents = s.agents; env = s.env ?? ""; tenant = s.tenant ?? ""
            offline = false
            DiskCache.save(s, key: "state")
        } catch let e as APIError where e.isAuth {
        } catch { offline = true; lastError = error.localizedDescription }
    }
    func refreshHealth() async {
        do {
            let h: HealthResponse = try await api.request("/api/health", auth: false, retry: false, timeout: 10)
            health = h; DiskCache.save(h, key: "health")
        } catch { }
    }
    func refreshGroups() async {
        do {
            let g: GroupsResponse = try await api.request("/api/group-chat/groups")
            groups = g.groups.sorted { ($0.last_ts ?? 0, $0.last_msg_id ?? 0) > ($1.last_ts ?? 0, $1.last_msg_id ?? 0) }
            DiskCache.save(GroupsResponse(groups: groups), key: "groups")
        } catch { }
    }
    // /api/usage 首掃可能數分鐘 → 長逾時、失敗靜默
    func refreshUsage() async {
        if usageLoading { return }
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
