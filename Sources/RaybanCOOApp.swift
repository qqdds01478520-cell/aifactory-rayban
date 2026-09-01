import SwiftUI

@main
struct RaybanCOOApp: App {
    init() {
        GlassesManager.configure()   // Wearables.configure() 一次
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in       // Meta AI app 授權回呼（必接）
                    Task { await GlassesManager.shared.handleUrl(url) }
                }
        }
    }
}
