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
                #endif
        }
    }
}
