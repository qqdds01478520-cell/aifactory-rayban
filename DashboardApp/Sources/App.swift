import SwiftUI
import UserNotifications
import BackgroundTasks
import WebKit

@main
struct AIFactoryDashboardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState.shared
    @StateObject private var l10n = L10n.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(l10n)
                .tint(Theme.primary)
                .onOpenURL { url in handle(url) }
        }
        .onChange(of: phase) { p in
            switch p {
            case .background:
                state.lockIfNeeded()
                state.scheduleBackgroundRefresh()
            case .active:
                break   // 網頁自己輪詢；殼不再打 /api/state（8/10 董事長：手機外網輪詢曾悶死伺服器）
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
    var body: some View {
        ShellView()
            .sheet(isPresented: Binding(get: { state.pendingShare != nil }, set: { if !$0 { state.pendingShare = nil } })) {
                DispatchSheet(text: state.pendingShare ?? "")
            }
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
