import SwiftUI
import WebKit
import UIKit

/// 極簡 WKWebView 包裝。用來嵌 YouTube 播放器與 Google 地圖（免 API key 的 embed）。
struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = .clear
        v.scrollView.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: WKWebView, context: Context) {
        if v.url != url { v.load(URLRequest(url: url)) }
    }
}
