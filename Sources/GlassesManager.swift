import Foundation
import MWDATCore
import MWDATCamera
import MWDATDisplay

/// 封裝 Meta Wearables DAT SDK：連眼鏡、顯示文字、拍照。
/// 並實作 CommandExecutor，讓遠端除錯橋能把 COO 的指令落到眼鏡硬體上。
///
/// 能力邊界（2026-09-01 SDK 研究定案）：
///  - 顯示、拍照 = DAT SDK 原生支援。
///  - 麥克風、喇叭 = SDK 無 API，另由 AudioIO.swift 走 iOS AVAudioEngine + 藍牙 HFP 路由。
@MainActor
final class GlassesManager: CommandExecutor {
    static let shared = GlassesManager()

    private var session: DeviceSession?
    private var display: Display?
    private var camera: Camera?

    /// 在 App init 呼叫一次。
    static func configure() {
        do { try Wearables.configure() }
        catch { NSLog("Wearables.configure 失敗: \(error)") }
    }

    /// Meta AI app 授權回呼（.onOpenURL 轉進來）。
    func handleUrl(_ url: URL) async {
        _ = try? await Wearables.shared.handleUrl(url)
    }

    /// 與眼鏡配對授權（首次）。
    func register() async throws {
        try await Wearables.shared.startRegistration()
    }

    /// 建立並啟動 session，掛上顯示與相機 capability。
    func connect() async throws {
        let s = try Wearables.shared.createSession(
            deviceSelector: AutoDeviceSelector(wearables: Wearables.shared))
        try s.start()
        session = s
        // 顯示
        let d = try s.addDisplay()
        d.start()
        display = d
        // 相機（中畫質 24fps，拍照夠用）
        let cfg = StreamConfiguration(videoCodec: .hvc1, resolution: .medium, frameRate: 24)
        if let c = try s.addCamera(config: cfg) {
            c.stream.start()
            camera = c
        }
    }

    func disconnect() {
        camera?.stop()
        display?.stop()
        session?.stop()
        camera = nil; display = nil; session = nil
    }

    // MARK: 顯示

    /// 在鏡片顯示一段文字（標題 + 內文）。
    func showText(title: String, body: String) async throws {
        guard let display else { throw GlassesError.notConnected }
        try await display.send(
            FlexBox(direction: .column, spacing: 10) {
                Text(title, style: .heading)
                Text(body, style: .body, color: .secondary)
            }
            .padding(24)
            .background(.card)
        )
    }

    // MARK: 拍照

    /// 拍一張照，回傳 JPEG data。
    func capturePhoto() async throws -> Data {
        guard let camera else { throw GlassesError.notConnected }
        return try await withCheckedThrowingContinuation { cont in
            let token = camera.stream.photoDataPublisher.listen { photo in
                cont.resume(returning: photo.data)
            }
            camera.stream.capturePhoto(format: .jpeg)
            _ = token // 由 SDK 生命週期管理
        }
    }

    // MARK: 狀態

    func statusText() -> String {
        let s = session?.statePublisher.value.map { "\($0)" } ?? "no-session"
        let hasDisplay = display != nil
        let hasCamera = camera != nil
        return "session=\(s) display=\(hasDisplay) camera=\(hasCamera)"
    }

    // MARK: CommandExecutor（遠端除錯橋）

    func execute(_ cmd: RemoteCommand) async -> CommandResult {
        do {
            switch cmd.action {
            case "display":
                try await showText(title: cmd.args?["title"] ?? "COO",
                                   body: cmd.args?["text"] ?? "")
                return CommandResult(id: cmd.id, ok: true, result: "displayed", log: "")
            case "capture":
                let data = try await capturePhoto()
                let id = try await RelayClient(authKey: AppConfig.authKey).uploadPhoto(data)
                return CommandResult(id: cmd.id, ok: true, result: "photo:\(id)", log: "\(data.count)B")
            case "status":
                return CommandResult(id: cmd.id, ok: true, result: statusText(), log: "")
            default:
                return CommandResult(id: cmd.id, ok: false, result: "", log: "unknown action \(cmd.action)")
            }
        } catch {
            return CommandResult(id: cmd.id, ok: false, result: "", log: "\(error)")
        }
    }
}

enum GlassesError: Error { case notConnected }

enum AppConfig {
    // ⚠ 真值不進公開 repo。編譯用 placeholder；真 key 由執行期注入
    //   （首次啟動設定畫面 / 不提交的 Secrets.plist / CI build secret）。
    static let authKey: String = {
        if let k = Bundle.main.object(forInfoDictionaryKey: "RelayAuthKey") as? String,
           !k.isEmpty, k != "$(RELAY_AUTH_KEY)" { return k }
        return "SET_AT_RUNTIME"
    }()
    static let relayBase = "https://rayban-relay.goingtosheon.workers.dev"
}
