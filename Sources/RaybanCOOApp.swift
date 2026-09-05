import SwiftUI

@main
struct RaybanCOOApp: App {
    init() {
        #if canImport(MWDATCore)
        GlassesManager.configure()   // 第二批：眼鏡 SDK 初始化
        #endif
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if canImport(MWDATCore)
                .onOpenURL { url in       // 第二批：Meta AI app 授權回呼
                    Task { await GlassesManager.shared.handleUrl(url) }
                }
                .task {
                    // 指令橋常駐：眼鏡網頁（畫面）下單 → 本 app（後台引擎）領單執行
                    guard AppConfig.hasRelayKey else { return }
                    let bridge = RemoteDebugBridge(authKey: AppConfig.authKey,
                                                   executor: GlassesManager.shared)
                    await bridge.start()
                }
                .task {
                    // 麥克風常駐：app 一開（前景）就開好麥克風並持續錄音，既佔住 audio 背景模式
                    // 讓 app 永不凍結（遠端指令橋 24h 領得到單），又讓背景也聽得到講話、且不會被 iOS
                    // 掐死（背景只是延續前景就開好的收音，不是重新開麥克風）。董事長「一開就常駐開麥克風」。
                    await AudioHub.shared.requestPermission()
                    AudioHub.shared.startAlwaysOn()
                    // 掛狀態監看；不開機自動拍照（會搶眼鏡畫面＋背景凍結留殭屍 session）
                    guard AppConfig.hasRelayKey else { return }
                    GlassesManager.shared.watchState()
                }
                #endif
        }
    }
}
