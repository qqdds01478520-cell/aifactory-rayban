import SwiftUI
import WebKit

// 商雲端 iOS app v1.0（董事長 2026-10-12）：畫面＝商雲端網頁原碼滿版跑在 WKWebView（同控制台 App 9/29 定案做法）。
// 原生只做：深色滿版、按鈕觸覺、左緣右滑＝上一頁、外站連結交 Safari、JS 對話框、連不上時重試。
let HOME = URL(string: "https://shangyun.goingtosheon.workers.dev/")!
let BG = Color(red: 7 / 255, green: 7 / 255, blue: 11 / 255)

@main
struct ShangyunApp: App {
    var body: some Scene {
        WindowGroup { RootView().preferredColorScheme(.dark) }
    }
}

final class Shell: ObservableObject {
    @Published var loading = true
    @Published var failed = false
    @Published var failText = ""
    weak var web: WKWebView?
    func reload() {
        failed = false; loading = true
        web?.load(URLRequest(url: web?.url ?? HOME, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30))
    }
}

struct RootView: View {
    @StateObject var shell = Shell()
    var body: some View {
        ZStack {
            BG.ignoresSafeArea()
            WebShell(shell: shell).ignoresSafeArea()
            if shell.loading && !shell.failed { ProgressView().tint(.white) }
            if shell.failed {
                VStack(spacing: 14) {
                    Text("連不上商雲端").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                    Text(shell.failText).font(.system(size: 13)).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 28)
                    Button("重試") { shell.reload() }
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 48).padding(.vertical, 12)
                        .background(LinearGradient(colors: [Color(red: 0.545, green: 0.361, blue: 0.965), Color(red: 0.133, green: 0.827, blue: 0.933)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(BG.ignoresSafeArea())
            }
        }
    }
}

struct WebShell: UIViewRepresentable {
    let shell: Shell
    func makeCoordinator() -> Coord { Coord(shell) }
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.websiteDataStore = .default()                      // 登入（localStorage）留著，下次打開免再登
        cfg.userContentController.add(context.coordinator, name: "native")
        cfg.userContentController.addUserScript(WKUserScript(source: """
          (function(){
            var post = function(m){ try { window.webkit.messageHandlers.native.postMessage(m); } catch(e){} };
            document.addEventListener('click', function(e){
              var el = e.target && e.target.closest && e.target.closest('button,a,[data-id],[data-p],.chip,.pc,.hero');
              if (el) post({type:'haptic'});
            }, true);
          })();
          """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.navigationDelegate = context.coordinator
        w.uiDelegate = context.coordinator
        w.isOpaque = false
        w.backgroundColor = UIColor(BG)
        w.scrollView.backgroundColor = UIColor(BG)
        w.scrollView.contentInsetAdjustmentBehavior = .never     // 滿版：網頁自己用 env(safe-area-inset-*) 讓開瀏海
        w.scrollView.bounces = false
        w.customUserAgent = (w.value(forKey: "userAgent") as? String ?? "Mozilla/5.0 (iPhone)") + " ShangyunApp/1.0"
        let edge = UIScreenEdgePanGestureRecognizer(target: context.coordinator, action: #selector(Coord.edgePan(_:)))
        edge.edges = .left
        edge.delegate = context.coordinator
        w.addGestureRecognizer(edge)
        shell.web = w
        w.load(URLRequest(url: HOME, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30))
        return w
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coord: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate {
        let shell: Shell
        let tap = UIImpactFeedbackGenerator(style: .light)
        init(_ s: Shell) { shell = s }

        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            if let b = m.body as? [String: Any], b["type"] as? String == "haptic" { tap.impactOccurred() }
        }
        // 外站連結（Claude 設定頁、條款外連）交給 Safari；商雲端自己的頁面留在 App 裡
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let u = action.request.url, ["http", "https"].contains(u.scheme?.lowercased() ?? ""),
               (action.targetFrame == nil || (action.navigationType == .linkActivated && u.host?.lowercased() != HOME.host)) {
                UIApplication.shared.open(u); decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let u = action.request.url { UIApplication.shared.open(u) }
            return nil
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.shell.loading = false; self.shell.failed = false }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        private func fail(_ error: Error) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            DispatchQueue.main.async { self.shell.loading = false; self.shell.failed = true; self.shell.failText = error.localizedDescription }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

        // 網頁的 alert／confirm／prompt（刪除確認、清除對話等）→ 原生對話框
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            present(a) ?? completionHandler()
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: "確定", style: .default) { _ in completionHandler(true) })
            present(a) ?? completionHandler(false)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText }
            a.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
            a.addAction(UIAlertAction(title: "確定", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
            present(a) ?? completionHandler(nil)
        }
        private func present(_ a: UIAlertController) -> Void? {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
                  var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
            while let p = top.presentedViewController { top = p }
            top.present(a, animated: true)
            return ()
        }
        // 左緣右滑＝上一頁（網頁每進一頁推一筆歷史，history.back 就回上一頁）
        @objc func edgePan(_ g: UIScreenEdgePanGestureRecognizer) {
            guard g.state == .ended, let v = g.view as? WKWebView else { return }
            if g.translation(in: v).x > 60 || g.velocity(in: v).x > 600 {
                tap.impactOccurred()
                v.evaluateJavaScript("history.back()") { _, _ in }
            }
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
