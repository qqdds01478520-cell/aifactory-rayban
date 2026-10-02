import SwiftUI

/// 操作眼鏡（董 2026-10-02 TG10503／TG10506）：鏡像眼鏡上的 Claco HUD 畫面，手機直接點／方向鍵／打字操作。
/// 本體＝claco-hud 的 mirror.html（網頁跟眼鏡 app 同一套，改功能只要部署 Worker、不用重編 app）。
struct MirrorView: View {
    @Environment(\.colorScheme) private var scheme
    private let url = URL(string: "https://claco-hud.goingtosheon.workers.dev/mirror.html")!

    var body: some View {
        WebView(url: url)
            .background(Theme.ground(scheme))
    }
}
