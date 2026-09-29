import SwiftUI
import UserNotifications
import BackgroundTasks
import WebKit

let DEFAULT_BASE = "https://aifactory-dashboard.tail825b5f.ts.net"
let RELAY_BASE = "https://rayban-relay.goingtosheon.workers.dev"
let BG_REFRESH_ID = "com.aifactory.dashboard.refresh"

@main
struct AIFactoryDashboardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState.shared
    @StateObject private var l10n = L10n.shared
    @StateObject private var nav = Nav.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(l10n)
                .environmentObject(nav)
                .tint(Theme.primary)
                .onOpenURL { url in handle(url) }
        }
        .onChange(of: phase) { p in
            switch p {
            case .background:
                state.lockIfNeeded()
                state.scheduleBackgroundRefresh()
            case .active:
                if state.loggedIn && !state.locked { Task { await state.refreshAll() } }
            default: break
            }
        }
    }

    // aifactory://dispatch?text=…&agent=COO （捷徑／分享捷徑進來派工）
    private func handle(_ url: URL) {
        guard url.scheme == "aifactory" else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let q = comps?.queryItems ?? []
        if url.host == "dispatch", let text = q.first(where: { $0.name == "text" })?.value, !text.isEmpty {
            if let a = q.first(where: { $0.name == "agent" })?.value, !a.isEmpty { state.dispatchAgent = a }
            state.pendingShare = text
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted { DispatchQueue.main.async { app.registerForRemoteNotifications() } }
            else { Task { @MainActor in AppState.shared.pushStatus = "未授權" } }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BG_REFRESH_ID, using: nil) { task in
            guard let t = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in AppState.shared.handleBackgroundRefresh(t) }
        }
        return true
    }
    func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in AppState.shared.registerPushToken(hex: hex) }
    }
    func application(_ app: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in AppState.shared.pushStatus = "失敗：\(error.localizedDescription)" }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound, .badge])
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if !state.loggedIn {
                LoginView()
            } else {
                MainTabView()
                    .blur(radius: state.locked ? 18 : 0)
                    .allowsHitTesting(!state.locked)
                if state.locked { LockView() }
            }
            if let t = nav.toast {
                VStack { ToastView(msg: t).padding(.top, 8); Spacer() }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(99)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.locked)
        .animation(.easeInOut(duration: 0.2), value: state.loggedIn)
    }
}

struct LockView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "faceid").font(.system(size: 56)).foregroundColor(Theme.primary)
            Text(L("已鎖定")).font(WF.sans(18, .semibold)).foregroundColor(Theme.text)
            Button(L("解鎖")) { Task { await state.unlock() } }
                .buttonStyle(PrimaryButtonStyle()).frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.opacity(0.85).ignoresSafeArea())
        .task { await state.unlock() }
    }
}

// 主殼＝網頁 App.jsx：五分頁浮動列 ＋ 子頁返回列（子頁／插件頁／聊天室內隱藏分頁列）
struct MainTabView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @EnvironmentObject var l10n: L10n

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !nav.tabBarHidden {
                FloatingTabBar()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onChange(of: nav.tab) { _ in if state.hapticsEnabled { Haptic.select() } }
        .sheet(isPresented: Binding(get: { state.pendingShare != nil }, set: { if !$0 { state.pendingShare = nil } })) {
            DispatchSheet(text: state.pendingShare ?? "")
        }
        .task { await state.refreshAll() }
    }

    @ViewBuilder
    private var content: some View {
        if let p = nav.plugin {
            PluginPage(plugin: p)
        } else if let s = nav.sub {
            SubPageHost(page: s)
        } else {
            switch nav.tab {
            case .overview: OverviewView()
            case .agents: AgentsView()
            case .terminal: TerminalView()
            case .chat: ChatView()
            case .more: MoreView()
            }
        }
    }
}

// 子頁：返回列 ＋ 內容
struct SubPageHost: View {
    @EnvironmentObject var nav: Nav
    let page: SubPage
    var body: some View {
        VStack(spacing: 0) {
            BackHeader(title: page.title) { nav.back() }
            Group {
                switch page {
                case .usage: UsagePage()
                case .backup: BackupPage()
                case .search: SearchPage()
                case .license: LicensePage()
                case .users: UsersPage()
                case .knowledge: KnowledgePage()
                case .products: ProductsPage()
                case .store: StorePage()
                case .admin: AdminPage()
                case .claudeToken: ClaudeTokenPage()
                case .remote: RemotePage()
                case .company: CompanyPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

// 浮動分頁列：📊 總覽 / 🤖 Agents（紅色運行數徽章）/ 💻 終端機（44 橘圓、上浮 8）/ 🗨️ 群聊 / ⚙️ 更多
struct FloatingTabBar: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @EnvironmentObject var l10n: L10n
    var running: Int { state.agents.filter { $0.isRunning }.count }

    var body: some View {
        HStack(spacing: 0) {
            tabBtn(.overview, "📊", L("總覽"))
            tabBtn(.agents, "🤖", "Agents", badge: running)
            centerBtn
            tabBtn(.chat, "🗨️", L("群聊"))
            tabBtn(.more, "⚙️", L("更多"))
        }
        .frame(height: 64)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.surface.opacity(0.78))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow(color: Color(hex: 0x2c1810, alpha: 0.1), radius: 16, x: 0, y: 8)
    }

    private func tabBtn(_ t: Tab, _ icon: String, _ label: String, badge: Int = 0) -> some View {
        let active = nav.tab == t
        return Button { nav.go(t) } label: {
            VStack(spacing: 2) {
                Text(icon).font(.system(size: 20))
                    .padding(.vertical, 4).padding(.horizontal, 12)
                    .background(active ? Theme.primarySoft : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(label).font(WF.sans(10, .medium))
            }
            .foregroundColor(active ? Theme.primary : Theme.text2)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)").font(WF.sans(9, .bold)).foregroundColor(.white)
                        .frame(minWidth: 16, minHeight: 16).padding(.horizontal, 3)
                        .background(Color(hex: 0xf44336)).clipShape(Capsule())
                        .offset(x: -12, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var centerBtn: some View {
        Button { nav.go(.terminal) } label: {
            VStack(spacing: 2) {
                Text("💻").font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(Theme.primary).clipShape(Circle())
                    .shadow(color: Color(hex: 0xcc6633, alpha: 0.3), radius: 6, x: 0, y: 4)
                    .offset(y: -8)
                Text(L("終端機")).font(WF.sans(10, .medium)).foregroundColor(nav.tab == .terminal ? Theme.primary : Theme.text2).offset(y: -6)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// 語系下拉（網頁 LanguageSelect：bg surface-2、1px border、radius 8、padding 4/8、12px）
struct LanguagePill: View {
    @EnvironmentObject var l10n: L10n
    var body: some View {
        Menu {
            ForEach(LANGS) { l in
                Button { l10n.lang = l.code } label: {
                    if l10n.lang == l.code { Label(l.label, systemImage: "checkmark") } else { Text(l.label) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(l10n.label).font(WF.sans(12))
                Text("▾").font(WF.sans(10))
            }
            .foregroundColor(Theme.text)
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
        }
    }
}

// 我的插件：全螢幕（← 返回 / 名稱 / ↗ 新視窗）＋ WebView（proxied 帶 ?t=token）
struct PluginPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    let plugin: UserPlugin
    var target: URL? {
        guard let raw = plugin.url else { return nil }
        var s = raw.hasPrefix("http") ? raw : state.api.url(raw).absoluteString
        if plugin.proxied == true, let t = state.api.token {
            s += (s.contains("?") ? "&" : "?") + "t=" + t
        }
        return URL(string: s)
    }
    var body: some View {
        VStack(spacing: 0) {
            BackHeader(title: plugin.name, onBack: { nav.back() }) {
                if let u = target {
                    Button { UIApplication.shared.open(u) } label: {
                        Text("↗ " + L("新視窗")).font(WF.sans(12, .semibold)).foregroundColor(Theme.text2)
                            .padding(.vertical, 6).padding(.horizontal, 10).background(Theme.surface)
                            .clipShape(Capsule()).overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                    }
                }
            }
            if let u = target { WebPane(url: u).ignoresSafeArea(edges: .bottom) }
            else { EmptyState(icon: "🧩", title: L("這個插件沒有網址")) }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
struct WebPane: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.scrollView.contentInsetAdjustmentBehavior = .never
        w.load(URLRequest(url: url))
        return w
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// B6：把分享／捷徑帶進來的文字派給指定員工
struct DispatchSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State var text: String
    @State private var agent: String = ""
    @State private var sending = false
    @State private var err: String?
    var body: some View {
        NavigationStack {
            Form {
                Picker(L("員工"), selection: $agent) {
                    ForEach(state.sortedAgents.filter { $0.isRunning }) { a in Text(a.name).tag(a.name) }
                }
                TextEditor(text: $text).frame(minHeight: 140)
                if let err { Text(err).foregroundColor(Theme.danger).font(.footnote) }
            }
            .navigationTitle(L("派工給員工"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "…" : L("派工")) {
                        sending = true
                        Task {
                            err = await state.dispatch(text: text, to: agent)
                            sending = false
                            if err == nil { state.dispatchAgent = agent; dismiss() }
                        }
                    }.disabled(sending || text.isEmpty || agent.isEmpty)
                }
            }
            .onAppear { agent = state.agents.contains(where: { $0.name == state.dispatchAgent && $0.isRunning }) ? state.dispatchAgent : (state.sortedAgents.first(where: { $0.isRunning })?.name ?? "") }
        }
    }
}
