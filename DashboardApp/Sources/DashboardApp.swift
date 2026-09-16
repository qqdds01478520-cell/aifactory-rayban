import SwiftUI
import WebKit
import UserNotifications

let DASHBOARD_URL = URL(string: "https://aifactory-dashboard.tail825b5f.ts.net")!
let RELAY_BASE = "https://rayban-relay.goingtosheon.workers.dev"

@main
struct AIFactoryDashboardApp: App {
    @UIApplicationDelegateAdaptor(PushDelegate.self) var pushDelegate
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

final class PushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted { DispatchQueue.main.async { app.registerForRemoteNotifications() } }
        }
        return true
    }

    func application(_ app: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        let key = (Bundle.main.object(forInfoDictionaryKey: "RelayAuthKey") as? String) ?? ""
        guard var comps = URLComponents(string: RELAY_BASE + "/dash-token") else { return }
        comps.queryItems = [URLQueryItem(name: "k", value: key)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": hex])
        URLSession.shared.dataTask(with: req).resume()
    }

    // App 開在前景時通知照樣跳橫幅
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound, .badge])
    }
}

struct ContentView: View {
    @StateObject private var model = WebModel()
    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08).ignoresSafeArea()
            WebContainer(model: model)
            if model.failed {
                VStack(spacing: 18) {
                    Text("連不上控制台").font(.title2).foregroundColor(.white)
                    Text("請確認 iPhone 已連上 Tailscale 或有網路")
                        .font(.footnote).foregroundColor(.gray)
                    Button("重試") { model.reload() }
                        .padding(.horizontal, 32).padding(.vertical, 12)
                        .background(Color.orange).foregroundColor(.black)
                        .cornerRadius(12)
                }
            }
        }
    }
}

final class WebModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var failed = false
    let webView: WKWebView

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        reload()
    }

    func reload() {
        failed = false
        webView.load(URLRequest(url: DASHBOARD_URL, timeoutInterval: 15))
    }

    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { markFail(e) }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { markFail(e) }
    private func markFail(_ e: Error) {
        if (e as NSError).code == NSURLErrorCancelled { return }
        failed = true
    }
}

struct WebContainer: UIViewRepresentable {
    let model: WebModel
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
