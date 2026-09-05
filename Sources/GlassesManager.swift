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
    private let speech = SpeechRecognizer()
    private var jarvisRunning = false

    /// 開機就盯註冊狀態流＋裝置偵測流，反映到 UI。（冪等，可重複呼叫）
    func watchState() {
        guard !watching else { return }
        watching = true
        if selector == nil { selector = AutoDeviceSelector(wearables: Wearables.shared) }
        // 先讀「當下值」再聽流（官方樣本寫法）——流不重播現值，只聽流會漏掉已綁定狀態
        let now = Wearables.shared.registrationState
        registered = now == .registered
        RemoteLog.send("watchState: registrationState=\(now)")
        Task { [weak self] in
            for await state in Wearables.shared.registrationStateStream() {
                self?.registered = state == .registered
                RemoteLog.send("registrationStateStream → \(state)")
            }
        }
        Task { [weak self] in
            guard let sel = self?.selector else { return }
            for await dev in sel.activeDeviceStream() {
                self?.hasDevice = dev != nil
                RemoteLog.send("activeDeviceStream → \(dev == nil ? "nil" : "device-online")")
            }
        }
    }

    static func configure() {
        do { try Wearables.configure(); RemoteLog.send("Wearables.configure OK") }
        catch {
            NSLog("Wearables.configure 失敗: \(error)")
            RemoteLog.send("Wearables.configure FAIL: \(error)")
        }
    }

    func handleUrl(_ url: URL) async {
        let brief = "\(url.scheme ?? "")://\(url.host ?? "")\(url.path)"
        do {
            let handled = try await Wearables.shared.handleUrl(url)
            RemoteLog.send("handleUrl \(brief) → handled=\(handled) state=\(Wearables.shared.registrationState)")
        } catch {
            lastError = "\(error)"
            RemoteLog.send("handleUrl \(brief) → THROW: \(error)")
        }
    }

    func register() async throws {
        watchState()
        RemoteLog.send("register(): startRegistration… state=\(Wearables.shared.registrationState)")
        do { try await Wearables.shared.startRegistration() }
        catch {
            RemoteLog.send("startRegistration THROW: \(error)")
            throw error
        }
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
        return "reg=\(Wearables.shared.registrationState) device=\(hasDevice) session=\(s) "
             + "display=\(display != nil) camera=\(camera != nil) lastError=\(lastError.isEmpty ? "-" : lastError)"
    }

    /// 聽一句話（最長 maxSeconds 秒；辨識器自然收尾就提早停），回最終文字。
    /// 眼鏡連著時 iOS 會走藍牙麥克風＝眼鏡收音。
    func listenOnce(maxSeconds: Int = 7) async -> String {
        if !speech.authorized { await speech.requestPermission() }
        guard speech.authorized else { return "" }
        speech.transcript = ""
        speech.start { _ in }
        for _ in 0..<(maxSeconds * 4) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !speech.isListening { break }
        }
        speech.stop()
        return speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 賈維斯模式：持續聽寫逐段傳克拉扣＋每 10 秒眼鏡拍一張上傳（＝克拉扣的視野）。
    /// 安全上限 15 分鐘自動停，網頁離開也會下 jarvis_stop。
    private func startJarvis() {
        guard !jarvisRunning else { return }
        jarvisRunning = true
        let relay = RelayClient(authKey: AppConfig.authKey)
        let started = Date()
        Task { [weak self] in   // 聽寫迴圈
            while self?.jarvisRunning == true, Date().timeIntervalSince(started) < 900 {
                guard let self else { break }
                let heard = await self.listenOnce(maxSeconds: 10)
                if !heard.isEmpty, self.jarvisRunning { _ = try? await relay.askText("[賈維斯] " + heard) }
            }
            self?.jarvisRunning = false
        }
        Task { [weak self] in   // 視野迴圈
            while self?.jarvisRunning == true, Date().timeIntervalSince(started) < 900 {
                if let data = try? await self?.capturePhoto() { _ = try? await relay.uploadPhoto(data) }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
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
            case "voiceask":
                // 全域雙捏手勢：聽一句 → 傳克拉扣 → 答案回蓋在當前眼鏡頁上
                let heard = await listenOnce(maxSeconds: 8)
                guard !heard.isEmpty else {
                    return CommandResult(id: cmd.id, ok: false, result: "", log: "沒收到聲音，再捏兩下重講")
                }
                let vr = RelayClient(authKey: AppConfig.authKey)
                let vqid = try await vr.askText("[語音] " + heard)
                if let ans = await vr.pollAnswer(id: vqid, timeout: 90) {
                    return CommandResult(id: cmd.id, ok: true, result: "🗣 \(heard)\n— \(ans)", log: "qid:\(vqid)")
                }
                return CommandResult(id: cmd.id, ok: false, result: "", log: "克拉扣還在想，再捏兩下重問")
            case "jarvis_start":
                startJarvis()
                return CommandResult(id: cmd.id, ok: true, result: "jarvis on", log: "")
            case "jarvis_stop":
                jarvisRunning = false
                return CommandResult(id: cmd.id, ok: true, result: "jarvis off", log: "")
            case "lookask", "menuscan":
                // 眼鏡網頁下的單（網頁＝畫面、app＝後台引擎）：眼鏡拍→送問→答案回網頁
                let data = try await capturePhoto()
                let relay = RelayClient(authKey: AppConfig.authKey)
                let prompt = cmd.action == "lookask"
                    ? "看著問：照片裡是什麼？兩三句講重點，像導遊在耳邊講。"
                    : "菜單翻譯：把照片裡的菜單翻成繁體中文，一行一道「菜名　價錢」，最多八行，最後加一行推薦。"
                let qid = try await relay.askPhoto(data, text: prompt)
                if let ans = await relay.pollAnswer(id: qid) {
                    return CommandResult(id: cmd.id, ok: true, result: ans, log: "qid:\(qid)")
                }
                return CommandResult(id: cmd.id, ok: false, result: "", log: "克拉扣還在想，捏一下重試")
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
