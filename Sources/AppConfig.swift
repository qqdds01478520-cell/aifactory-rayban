import Foundation

/// 全 app 共用設定。獨立於眼鏡 SDK（MWDAT），第一批純手機 UI 也能用。
/// 真值不進公開 repo：authKey 由 Info.plist 的 RelayAuthKey（CI build secret 注入）帶入，
/// 沒有就退成 placeholder（UI 照樣能編譯、能截圖，只是連不到 relay 時顯示引導狀態）。
enum AppConfig {
    static let relayBase = "https://rayban-relay.goingtosheon.workers.dev"

    static let authKey: String = {
        if let k = Bundle.main.object(forInfoDictionaryKey: "RelayAuthKey") as? String,
           !k.isEmpty, k != "$(RELAY_AUTH_KEY)" { return k }
        return "SET_AT_RUNTIME"
    }()

    static var hasRelayKey: Bool { authKey != "SET_AT_RUNTIME" }
}
