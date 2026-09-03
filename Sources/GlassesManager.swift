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
/// 時序鐵則（2026-09-03 noEligibleDevice 實機教訓，官方 display-access SKILL 明文）：
///  1. AutoDeviceSelector 要長駐，等 activeDeviceStream 給出裝置才可 createSession
///  2. session.start() 後要等 state == .started 才能 addDisplay/addCamera
@MainActor
final class GlassesManager: ObservableObject, CommandExecutor {
    static let shared = GlassesManager()

    @Published var registered = false
    @Published var hasDevice = false     // 眼鏡此刻在線（裝置偵測流）
    @Published var connected = false
    @Published var lastError = ""

    private var selector: AutoDeviceSelector?
    private var session: DeviceSession?
    private var display: Display?
    private var camera: Camera?
    private var tokens: [Any] = []       // listen 回傳的訂閱 token，要抓著不放
    private var watching = false

    /// 開機就盯註冊狀態流＋裝置偵測流，反映到 UI。（冪等，可重複呼叫）
    func watchState() {
        guard !watching else { return }
        watching = true
        if selector == nil { selector = AutoDeviceSelector(wearables: Wearables.shared) }
        Task { [weak self] in
            for await state in Wearables.shared.registrationStateStream() {
                // 精確比對——"unregistered" 也包含 "registered" 子字串，不能用 contains
                self?.registered = "\(state)" == "registered"
            }
        }
        Task { [weak self] in
            guard let sel = self?.selector else { return }
            for await dev in sel.activeDeviceStream() {
                self?.hasDevice = dev != nil
            }
        }
    }

    static func configure() {
        do { try Wearables.configure() }
        catch { NSLog("Wearables.configure 失敗: \(error)") }
    }

    func handleUrl(_ url: URL) async {
        _ = try? await Wearables.shared.handleUrl(url)
    }

    func register() async throws {
        watchState()
        try await Wearables.shared.startRegistration()
    }

    func connect() async throws {
        lastError = ""
        watchState()
        guard registered else { throw GlassesError.notRegistered }
        // 1) 等眼鏡在線（最多 12 秒；watchState 的裝置流會把 hasDevice 翻 true）
        var waited = 0
        while !hasDevice && waited < 48 {
            try await Task.sleep(nanoseconds: 250_000_000)
            waited += 1
        }
        guard hasDevice else { throw GlassesError.noDeviceOnline }
        // 2) 建 session（先訂狀態再 start，不漏初始轉換）
        guard let sel = selector else { throw GlassesError.noDeviceOnline }
        let s = try Wearables.shared.createSession(deviceSelector: sel)
        session = s
        tokens.append(s.statePublisher.listen { [weak self] st in
            Task { @MainActor in
                if st == .stopped { self?.connected = false }
            }
        })
        tokens.append(s.errorPublisher.listen { [weak self] err in
            Task { @MainActor in self?.lastError = "\(err)" }
        })
        try s.start()
        // 3) 等 .started（最多 15 秒）才掛能力
        waited = 0
        while s.state != .started && waited < 60 {
            try await Task.sleep(nanoseconds: 250_000_000)
            waited += 1
        }
        guard s.state == .started else { throw GlassesError.sessionTimeout("\(s.state)") }
        let d = try s.addDisplay()
        d.start()
        display = d
        let cfg = StreamConfiguration(videoCodec: .hvc1, resolution: .medium, frameRate: 24)
        if let c = try s.addCamera(config: cfg) {
            c.stream.start()
            camera = c
        }
        connected = true
    }

    func disconnect() {
        camera?.stop()
        display?.stop()
        session?.stop()
        camera = nil; display = nil; session = nil
        tokens.removeAll()
        connected = false
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
        let s = session != nil ? "up" : "no-session"
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

enum GlassesError: LocalizedError {
    case notConnected
    case notRegistered
    case noDeviceOnline
    case sessionTimeout(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "還沒連線眼鏡（先按②）"
        case .notRegistered: return "還沒綁定（先按①，跳 Meta AI 按同意）"
        case .noDeviceOnline: return "眼鏡不在線——確認眼鏡開機戴著、Meta AI app 顯示已連線，再按一次"
        case .sessionTimeout(let s): return "連線逾時（卡在 \(s)）——眼鏡收一下再展開重試"
        }
    }
}
#endif
