import SwiftUI
import WebKit

// v3.0 殼（董事長 2026-09-29 TG10182「一律網頁版，然後把我要的新功能加回去，然後我要滿版的」）：
// 畫面＝8896 網頁原碼滿版跑在 WKWebView；原生只做：Face ID 鎖、推播註冊、觸覺回饋、左緣右滑返回、
// 背景更新、分享／捷徑派工、App 設定（網頁「更多」頁的 App 設定列 → postMessage settings）。
struct ShellView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var shell = ShellModel()
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            WebShell(model: shell).ignoresSafeArea()
                .blur(radius: state.locked ? 18 : 0)
                .allowsHitTesting(!state.locked)
            if shell.loading && !shell.failed {
                VStack(spacing: 12) { ProgressView().tint(Theme.primary); Text(L("載入控制台…")).font(WF.sans(13)).foregroundColor(Theme.text2) }
            }
            if shell.failed { failView }
            if state.locked { LockView() }
        }
        .animation(.easeInOut(duration: 0.2), value: state.locked)
        .sheet(isPresented: $shell.showSettings) { AppSettingsSheet().environmentObject(state).environmentObject(L10n.shared) }
        .onAppear { shell.state = state }
    }
    // 連不上網頁：可改伺服器網址重試（網頁本身沒有這欄，殼要有）
    private var failView: some View {
        VStack(spacing: 14) {
            Text("⚠️").font(.system(size: 40))
            Text(L("連不上控制台")).font(WF.sans(17, .semibold)).foregroundColor(Theme.text)
            Text(shell.failText).font(WF.sans(12)).foregroundColor(Theme.text2).multilineTextAlignment(.center).padding(.horizontal, 24)
            TextField("https://…", text: $shell.serverDraft).noAutoCap().inputWarm(padV: 10, padH: 12, size: 13).padding(.horizontal, 24)
            Button(L("重試")) {
                if let u = URL(string: shell.serverDraft.trimmingCharacters(in: .whitespaces)), u.scheme != nil {
                    state.baseString = u.absoluteString; state.api.baseURL = u
                }
                shell.reload()
            }.buttonStyle(PrimaryButtonStyle()).frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { if shell.serverDraft.isEmpty { shell.serverDraft = state.baseString } }
    }
}

@MainActor
final class ShellModel: ObservableObject {
    @Published var loading = true
    @Published var failed = false
    @Published var failText = ""
    @Published var showSettings = false
    @Published var serverDraft = ""
    weak var webView: WKWebView?
    weak var state: AppState?
    func reload() {
        failed = false; loading = true
        guard let w = webView, let s = state else { return }
        w.load(URLRequest(url: s.api.url("/"), cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30))
    }
    func nativeBack() {
        Haptic.tap()
        webView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('aif-native-back'))") { _, _ in }
    }
}

struct WebShell: UIViewRepresentable {
    @ObservedObject var model: ShellModel
    @EnvironmentObject var state: AppState

    func makeCoordinator() -> Coord { Coord(self) }
    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.userContentController.add(context.coordinator, name: "native")
        cfg.userContentController.addUserScript(WKUserScript(source: Self.bridgeJS(token: state.api.token, refresh: state.api.refreshToken),
                                                             injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.navigationDelegate = context.coordinator
        w.uiDelegate = context.coordinator
        w.isOpaque = false
        w.backgroundColor = UIColor(Theme.bg)
        w.scrollView.backgroundColor = UIColor(Theme.bg)
        w.scrollView.contentInsetAdjustmentBehavior = .never      // 滿版：網頁自己用 env(safe-area-inset-*) 讓開瀏海
        w.allowsBackForwardNavigationGestures = false              // SPA 沒有歷史，返回走 aif-native-back
        w.customUserAgent = (w.value(forKey: "userAgent") as? String ?? "Mozilla/5.0 (iPhone)") + " AIFactoryApp/3.0"
        // 左緣右滑＝上一頁（董事長 TG10178「沒有左滑上一頁了」）
        let edge = UIScreenEdgePanGestureRecognizer(target: context.coordinator, action: #selector(Coord.edgePan(_:)))
        edge.edges = .left
        edge.delegate = context.coordinator
        w.addGestureRecognizer(edge)
        // 下拉重新整理
        let rc = UIRefreshControl()
        rc.addTarget(context.coordinator, action: #selector(Coord.pull(_:)), for: .valueChanged)
        w.scrollView.refreshControl = rc
        model.webView = w
        model.state = state
        w.load(URLRequest(url: state.api.url("/"), cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30))
        return w
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { context.coordinator.parent = self }

    // 注入網頁：①把原生 Keychain 的 token 種進 localStorage（v2 原生登入過的人不用再登）②localStorage 的 token／帳號變了就回報原生
    // （分享派工、背景更新、推播註冊要用）③按到按鈕／連結／開關＝觸覺
    static func bridgeJS(token: String?, refresh: String?) -> String {
        func js(_ s: String?) -> String {
            let d = (try? JSONSerialization.data(withJSONObject: [s ?? ""])) ?? Data("[\"\"]".utf8)
            let arr = String(decoding: d, as: UTF8.self)
            return String(arr.dropFirst().dropLast())
        }
        return """
        (function(){
          var NT = \(js(token)), NR = \(js(refresh));
          try { if (NT && !localStorage.getItem('aif_token')) { localStorage.setItem('aif_token', NT); if (NR) localStorage.setItem('aif_refresh_token', NR); } } catch(e){}
          var post = function(m){ try { window.webkit.messageHandlers.native.postMessage(m); } catch(e){} };
          var last = null;
          setInterval(function(){
            try {
              var t = localStorage.getItem('aif_token') || '';
              var k = t + '|' + (localStorage.getItem('aif_user') || '') + '|' + (localStorage.getItem('aif_role') || '');
              if (k !== last) { last = k; post({type:'token', token:t, refresh: localStorage.getItem('aif_refresh_token') || '', user: localStorage.getItem('aif_user') || '', role: localStorage.getItem('aif_role') || ''}); }
            } catch(e){}
          }, 1500);
          document.addEventListener('click', function(e){
            var el = e.target && e.target.closest && e.target.closest('button,a,[role="button"],input[type="checkbox"],input[type="radio"],select,label,[data-tour]');
            if (el) post({type:'haptic'});
          }, true);
          window.addEventListener('load', function(){ post({type:'loaded'}); });
        })();
        """
    }

    final class Coord: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate {
        var parent: WebShell
        init(_ p: WebShell) { parent = p }

        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let body = m.body as? [String: Any], let t = body["type"] as? String else { return }
            let state = parent.state
            switch t {
            case "haptic": Haptic.tap()
            case "settings": parent.model.showSettings = true
            case "loaded": parent.model.loading = false; parent.model.failed = false
            case "token":
                let tok = (body["token"] as? String) ?? ""
                if tok.isEmpty {
                    if state.api.token != nil { state.logout() }
                } else {
                    let changed = state.api.token != tok
                    state.api.token = tok
                    let r = (body["refresh"] as? String) ?? ""
                    state.api.refreshToken = r.isEmpty ? nil : r
                    Keychain.set(tok, for: "token")
                    if !r.isEmpty { Keychain.set(r, for: "refresh") }
                    if let u = body["user"] as? String, !u.isEmpty { state.username = u }
                    if let ro = body["role"] as? String, !ro.isEmpty { state.role = ro }
                    state.loggedIn = true
                    if changed { Task { await state.refreshState() } }   // 派工目標員工清單用；不常態輪詢
                }
            default: break
            }
        }

        // 外站連結（登入網址、新視窗）交給 Safari；同站導航留在殼裡
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let u = action.request.url, action.navigationType == .linkActivated,
               let h = u.host?.lowercased(), let base = parent.state.api.baseURL.host?.lowercased(), h != base,
               ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
                UIApplication.shared.open(u); decisionHandler(.cancel); return
            }
            if action.targetFrame == nil, let u = action.request.url { UIApplication.shared.open(u); decisionHandler(.cancel); return }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let u = action.request.url { UIApplication.shared.open(u) }
            return nil
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.model.loading = false; parent.model.failed = false
            webView.scrollView.refreshControl?.endRefreshing()
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        private func fail(_ error: Error) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            parent.model.loading = false; parent.model.failed = true; parent.model.failText = error.localizedDescription
            parent.model.webView?.scrollView.refreshControl?.endRefreshing()
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

        // JS alert/confirm → 原生對話框（網頁刪除確認用 confirm）
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: L("好"), style: .default) { _ in completionHandler() })
            present(a) ?? completionHandler()
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: L("取消"), style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: L("確定"), style: .default) { _ in completionHandler(true) })
            present(a) ?? completionHandler(false)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText }
            a.addAction(UIAlertAction(title: L("取消"), style: .cancel) { _ in completionHandler(nil) })
            a.addAction(UIAlertAction(title: L("確定"), style: .default) { _ in completionHandler(a.textFields?.first?.text) })
            present(a) ?? completionHandler(nil)
        }
        private func present(_ a: UIAlertController) -> Void? {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                  var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
            while let p = top.presentedViewController { top = p }
            top.present(a, animated: true)
            return ()
        }

        @objc func edgePan(_ g: UIScreenEdgePanGestureRecognizer) {
            guard g.state == .ended else { return }
            let tx = g.translation(in: g.view).x
            let vx = g.velocity(in: g.view).x
            if tx > 60 || vx > 600 { parent.model.nativeBack() }
        }
        @objc func pull(_ rc: UIRefreshControl) { Haptic.medium(); parent.model.webView?.reload() }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// App 設定（原本在原生「更多」頁；現由網頁「更多 → App 設定」列叫出）
struct AppSettingsSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var l10n: L10n
    @Environment(\.dismiss) var dismiss
    @State private var cacheSize = DiskCache.sizeBytes
    var version: String {
        let d = Bundle.main.infoDictionary
        return "\(d?["CFBundleShortVersionString"] as? String ?? "") (\(d?["CFBundleVersion"] as? String ?? ""))"
    }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("App 設定")) { dismiss() }
            List {
                Section {
                    Toggle(L("Face ID 鎖定"), isOn: $state.faceIDEnabled)
                    Toggle(L("觸覺回饋"), isOn: $state.hapticsEnabled)
                    Toggle(L("背景更新"), isOn: $state.bgRefreshEnabled)
                    Picker(L("分享派工目標員工"), selection: $state.dispatchAgent) {
                        ForEach(state.sortedAgents) { a in Text(a.name).tag(a.name) }
                        if !state.sortedAgents.contains(where: { $0.name == state.dispatchAgent }) { Text(state.dispatchAgent).tag(state.dispatchAgent) }
                    }
                } footer: { Text(L("分享派工：用 iPhone 分享表單／捷徑把文字丟進 aifactory://dispatch，會派給這位員工的終端機")) }
                .listRowBackground(Theme.surface)
                Section {
                    Button {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    } label: {
                        HStack { Text(L("推播通知")).foregroundColor(Theme.text); Spacer(); Text(state.pushStatus).foregroundColor(Theme.text2); Text("›").foregroundColor(Theme.text3) }
                    }
                    HStack { Text(L("伺服器")); Spacer(); Text(state.baseString).font(WF.sans(12)).foregroundColor(Theme.text2).lineLimit(1) }
                    HStack { Text(L("App 版本")); Spacer(); Text(version).foregroundColor(Theme.text2) }
                    HStack { Text(L("離線快取")); Spacer(); Text(Fmt.bytes(cacheSize)).foregroundColor(Theme.text2) }
                    Button(L("清除快取")) { DiskCache.clear(); cacheSize = 0; Haptic.medium() }
                }.listRowBackground(Theme.surface)
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .onChange(of: state.bgRefreshEnabled) { on in if on { state.scheduleBackgroundRefresh() } }
            .task { if state.agents.isEmpty { await state.refreshState() } }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
