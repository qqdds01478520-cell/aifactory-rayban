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
                    // 背景常駐保活：app 一開就佔住 audio 背景模式，退背景/鎖屏都不凍結，
                    // 讓遠端指令橋 24 小時領得到單（董事長「裝一次之後你自己遠端搞」）。
                    BackgroundKeepAlive.shared.start()
                    // 掛狀態監看；不開機自動拍照（會搶眼鏡畫面＋背景凍結留殭屍 session）
                    guard AppConfig.hasRelayKey else { return }
                    GlassesManager.shared.watchState()
                }
                #endif
        }
    }
}
