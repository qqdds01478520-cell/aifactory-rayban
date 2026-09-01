// 眼鏡（Meta DAT SDK）整合——第二批「進眼鏡」時啟用。
// 用 #if canImport 包住：第一批純手機 UI（project.yml 不含 MWDAT）時整檔不編譯，
// 確保雲端模擬器一定編得出畫面截圖；第二批把 MWDAT 加回 project.yml 即自動啟用。
#if canImport(MWDATCore)
import Foundation
import MWDATCore
import MWDATCamera
import MWDATDisplay

/// 封裝 Meta Wearables DAT SDK：連眼鏡、顯示文字、拍照。
/// 並實作 CommandExecutor，讓遠端除錯橋能把 COO 的指令落到眼鏡硬體上。
///
/// 能力邊界（2026-09-01 SDK 研究定案）：
///  - 顯示、拍照 = DAT SDK 原生支援。
///  - 麥克風、喇叭 = SDK 無 API，另由 VoiceAssistant 走 iOS AVAudioEngine + 藍牙 HFP 路由。
@MainActor
final class GlassesManager: CommandExecutor {
    static let shared = GlassesManager()

    private var session: DeviceSession?
    private var display: Display?
    private var camera: Camera?

    static func configure() {
        do { try Wearables.configure() }
        catch { NSLog("Wearables.configure 失敗: \(error)") }
    }

    func handleUrl(_ url: URL) async {
        _ = try? await Wearables.shared.handleUrl(url)
    }

    func register() async throws {
        try await Wearables.shared.startRegistration()
    }

    func connect() async throws {
        let s = try Wearables.shared.createSession(
            deviceSelector: AutoDeviceSelector(wearables: Wearables.shared))
        try s.start()
        session = s
        let d = try s.addDisplay()
        d.start()
        display = d
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

    func capturePhoto() async throws -> Data {
        guard let camera else { throw GlassesError.notConnected }
        return try await withCheckedThrowingContinuation { cont in
            let token = camera.stream.photoDataPublisher.listen { photo in
                cont.resume(returning: photo.data)
            }
            camera.stream.capturePhoto(format: .jpeg)
            _ = token
        }
    }

    func statusText() -> String {
        let s = session?.statePublisher.value.map { "\($0)" } ?? "no-session"
        return "session=\(s) display=\(display != nil) camera=\(camera != nil)"
    }

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
#endif
