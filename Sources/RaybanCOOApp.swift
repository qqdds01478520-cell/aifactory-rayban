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
                    // 董事長 2026-09-05：手機常駐錄音不要、眼鏡常駐背景聽可以。
                    // startAlwaysOn 只在偵測到眼鏡藍牙麥時才開麥，沒連眼鏡＝完全不錄（見 AudioHub）。
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
