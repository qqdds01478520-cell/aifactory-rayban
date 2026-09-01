import SwiftUI
import WebKit
import UIKit

/// 極簡 WKWebView 包裝。
/// 兩種來源：
///  - `WebView(url:)`  直接載入網址（YouTube 內嵌播放器用）
///  - `WebView(html:)` 載入 HTML 字串（Google 地圖 embed 必須包在 <iframe> 內，
///    否則 Google 會回「Embed API must be used in an iframe」而不出圖）
struct WebView: UIViewRepresentable {
    enum Source: Equatable {
        case url(URL)
        case html(String)
    }
    let source: Source

    init(url: URL) { self.source = .url(url) }
    init(html: String) { self.source = .html(html) }

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
        switch source {
        case .url(let url):
            if v.url != url { v.load(URLRequest(url: url)) }
        case .html(let html):
            if context.coordinator.loadedHTML != html {
                context.coordinator.loadedHTML = html
                // baseURL 給真實網域，iframe 的遠端來源才有正確安全脈絡可載入
                v.loadHTMLString(html, baseURL: URL(string: "https://www.google.com"))
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var loadedHTML: String? }
}
