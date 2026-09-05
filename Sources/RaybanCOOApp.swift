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
                    // 董事長 2026-09-05：「點開 app 手機就背景錄音」要拿掉。改成不常駐、不自動錄音——
                    // 只在真的下指令要聽的當下才開麥、聽完立刻關（listenOnce 內自行 start→stop）。
                    // 這裡只預先要權限（避免第一次聽時才跳窗），絕不 startAlwaysOn。
                    await AudioHub.shared.requestPermission()
                    // 掛狀態監看；不開機自動拍照（會搶眼鏡畫面＋背景凍結留殭屍 session）
                    guard AppConfig.hasRelayKey else { return }
                    GlassesManager.shared.watchState()
                }
                #endif
        }
    }
}
