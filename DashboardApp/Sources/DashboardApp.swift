import SwiftUI
import WebKit

let DASHBOARD_URL = URL(string: "https://aifactory-dashboard.tail825b5f.ts.net")!

@main
struct AIFactoryDashboardApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
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
