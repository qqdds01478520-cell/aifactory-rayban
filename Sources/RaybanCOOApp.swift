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
                .onOpenURL { url in       // Meta AI app 註冊/授權回呼（全域狀態，DATLab 直接讀 Wearables.shared）
                    Task { await GlassesManager.shared.handleUrl(url) }
                }
                // 2026-09-22 重做：**刻意拿掉 AudioHub.startAlwaysOn 與指令橋**。
                // omi 產品原碼證實：背景常駐 HFP 麥會害 DAT 相機 session 開不起來（Device unavailable）。
                // 這版先驗「乾淨、無背景麥」能不能開得起 session；驗過再決定要不要把耳目那條加回。
                #endif
        }
    }
}
