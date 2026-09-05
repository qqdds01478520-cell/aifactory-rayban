// 眼鏡（Meta DAT SDK）整合——第二批「進眼鏡」時啟用。
// 用 #if canImport 包住：第一批純手機 UI（project.yml 不含 MWDAT）時整檔不編譯，
// 確保雲端模擬器一定編得出畫面截圖；第二批把 MWDAT 加回 project.yml 即自動啟用。
#if canImport(MWDATCore)
import Foundation
import Network
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
    private var photoToken: Any?         // 拍照回調訂閱——區域變數會被提早釋放害回調永遠不來
    private var displayToken: Any?       // 顯示狀態訂閱（同上，必須存屬性）
    private var displayState: DisplayState?   // 官方要求：send 前必等 .started
    private var streamState: StreamState = .stopped   // 拍照前置條件：必須 .streaming（官方 sample 鐵則）
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
        if Wearables.shared.registrationState == .registered {
            RemoteLog.send("register(): already registered, skip")
            registered = true
            return   // 已綁定重按①＝直接成功，別再叫 SDK（會丟 RegistrationError）
        }
        RemoteLog.send("register(): startRegistration… state=\(Wearables.shared.registrationState)")
        do { try await Wearables.shared.startRegistration() }
        catch {
            RemoteLog.send("startRegistration THROW: \(error)")
            throw error
        }
    }

    private var releaseGen = 0   // 自動斷線世代碼：新動作進來就取消舊的斷線排程

    /// 已連就直接用，沒連就連——③④「用時才連」的入口
    func ensureConnected() async throws {
        releaseGen += 1   // 新動作開始＝取消排程中的自動斷線，別在動作中途被斷
        if connected, let s = session, s.state == .started { return }
        try await connect()
    }

    /// 動作完成後 N 秒自動斷線，把眼鏡畫面還給原生系統（SDK session 期間眼鏡 HUD 會被熄掉，
    /// 董事長 9/5 直令處理——唯一繞法＝不長掛連線）。賈維斯模式運作中不斷。
    func scheduleAutoDisconnect(after seconds: UInt64 = 8) {
        releaseGen += 1
        let gen = releaseGen
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self, self.releaseGen == gen, !self.jarvisRunning else { return }
            self.disconnect()
            RemoteLog.send("session released (auto) — 眼鏡畫面已還原")
        }
    }

    private var lnBrowser: NWBrowser?

    /// 主動戳一下 Bonjour 掃描，逼 iOS 跳「區域網路」詢問（影像走 Wi-Fi 直連，
    /// 這權限沒開＝串流永遠 waitingForDevice；詢問一生只跳一次，被略過就得靠這招補問）
    private func triggerLocalNetworkPrompt() {
        guard lnBrowser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: "_bonjour._tcp", domain: nil), using: .init())
        b.stateUpdateHandler = { st in RemoteLog.send("localNetwork browse state: \(st)") }
        b.start(queue: .main)
        lnBrowser = b
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.lnBrowser?.cancel()
            self?.lnBrowser = nil
        }
    }

    func connect() async throws {
        lastError = ""
        watchState()
        if session != nil { disconnect() }   // 舊 session 沒清就 createSession 會 sessionAlreadyExists
        triggerLocalNetworkPrompt()
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
        // 任何一步失敗都先 disconnect 清掉半開的殭屍 session，避免佔死眼鏡端（iOS 背景凍結後的元兇）
        do {
            try s.start()
            // 3) 等 .started（最多 15 秒）才掛能力
            waited = 0
            while s.state != .started && waited < 60 {
                try await Task.sleep(nanoseconds: 250_000_000)
                waited += 1
            }
            guard s.state == .started else { throw GlassesError.sessionTimeout("\(s.state)") }
            // 眼鏡相機是獨立權限（綁定≠授權）：沒授權串流永遠 waitingForDevice→deviceNotConnected
            let perm = try await Wearables.shared.checkPermissionStatus(.camera)
            RemoteLog.send("camera permission = \(perm)")
            if perm != .granted {
                RemoteLog.send("requestPermission(.camera) → 跳 Meta AI…")
                let res = try await Wearables.shared.requestPermission(.camera)
                RemoteLog.send("camera permission after request = \(res)")
                guard res == .granted else { throw GlassesError.cameraPermissionDenied }
            }
        } catch {
            disconnect()   // 清殭屍 session，讓下次連線是全新的
            throw error
        }
        // 不在連線時 addDisplay——接管鏡片會蓋掉眼鏡原生畫面（董事長 9/5：畫面要獨立分開）。
        // 顯示改成 showText 用時才掛、幾秒後自動釋放還原。
        let cfg = StreamConfiguration(videoCodec: .hvc1, resolution: .medium, frameRate: 24)
        if let c = try s.addCamera(config: cfg) {
            // 先訂狀態再 start（官方 sample）；拍照鐵則＝要等 .streaming
            tokens.append(c.stream.statePublisher.listen { [weak self] st in
                Task { @MainActor in
                    self?.streamState = st
                    RemoteLog.send("streamState → \(st)")
                }
            })
            tokens.append(c.stream.errorPublisher.listen { [weak self] err in
                Task { @MainActor in
                    self?.lastError = "\(err)"
                    RemoteLog.send("streamError → \(err)")
                }
            })
            c.stream.start()
            camera = c
        }
        connected = true
        RemoteLog.send("connect OK: \(statusText())")
    }

    func disconnect() {
        camera?.stop()
        display?.stop()
        session?.stop()
        camera = nil; display = nil; session = nil
        displayToken = nil; displayState = nil
        tokens.removeAll()
        streamState = .stopped
        connected = false
    }

    private var displayGen = 0   // 自動釋放用世代碼：新內容進來就取消舊的還原排程

    func showText(title: String, body: String) async throws {
        try await ensureConnected()
        defer { scheduleAutoDisconnect(after: 13) }   // 比顯示釋放（10秒）晚一點再斷線
        guard let s = session, s.state == .started else { throw GlassesError.notConnected }
        if display == nil {
            let d = try s.addDisplay()
            displayState = nil
            displayToken = d.statePublisher.listen { [weak self] st in
                Task { @MainActor in
                    self?.displayState = st
                    RemoteLog.send("displayState → \(st)")
                }
            }
            d.start()
            display = d
        }
        guard let display else { throw GlassesError.notConnected }
        // 官方鐵則：display.start() 後必等 DisplayState.started 才能 send（最多 8 秒）
        var dw = 0
        while displayState != .started && dw < 32 {
            try await Task.sleep(nanoseconds: 250_000_000)
            dw += 1
        }
        guard displayState == .started else {
            throw GlassesError.streamNotReady("display \(String(describing: displayState))")
        }
        try await display.send(
            FlexBox(direction: .column, spacing: 10) {
                Text(title, style: .heading)
                Text(body, style: .body, color: .secondary)
            }
            .padding(24)
            .background(.card)
        )
        RemoteLog.send("showText OK: \(title)")
        displayGen += 1
        let gen = displayGen
        Task { [weak self] in   // 10 秒後自動釋放顯示，把鏡片還給眼鏡原生畫面
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self, self.displayGen == gen else { return }
            self.display?.stop()
            self.display = nil
            self.displayToken = nil
            self.displayState = nil
            RemoteLog.send("display released (auto)")
        }
    }

    func capturePhoto() async throws -> Data {
        try await ensureConnected()
        defer { scheduleAutoDisconnect(after: 8) }
        guard let camera else { throw GlassesError.notConnected }
        // 等串流真正進 .streaming（最多 10 秒）——沒到就拍，SDK 直接回 false 沒回調
        var waited = 0
        while streamState != .streaming && waited < 40 {
            try await Task.sleep(nanoseconds: 250_000_000)
            waited += 1
        }
        guard streamState == .streaming else {
            RemoteLog.send("capturePhoto: stream not streaming (\(streamState))")
            throw GlassesError.streamNotReady("\(streamState)")
        }
        RemoteLog.send("capturePhoto: request…")
        let once = ResumeOnce()
        defer { photoToken = nil }
        let data: Data = try await withCheckedThrowingContinuation { cont in
            photoToken = camera.stream.photoDataPublisher.listen { photo in
                if once.claim() { cont.resume(returning: photo.data) }
            }
            let accepted = camera.stream.capturePhoto(format: .jpeg)
            RemoteLog.send("capturePhoto: accepted=\(accepted)")
            if !accepted {
                if once.claim() { cont.resume(throwing: GlassesError.photoRejected) }
                return
            }
            Task {   // 12 秒逾時保護：沒回調就丟錯，別讓 busy 卡死整排按鈕
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                if once.claim() { cont.resume(throwing: GlassesError.photoTimeout) }
            }
        }
        RemoteLog.send("capturePhoto: got \(data.count)B")
        return data
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

    /// 賈維斯 v3（2026-09-05 董事長「賈維斯本來就該自動把我講話變中文字」）：純聽寫版。
    /// 主業＝一開就自動聽你講話→即時轉繁中→(1)顯示在鏡片上 (2)傳給 COO→答案回鏡片。
    /// 只開一條連線給鏡片顯示，全程不拍照（連拍會反覆重連、把 session 搶走害畫面一直關）。
    /// 鏡片上有「結束」鈕；安全上限 15 分鐘。
    private func startJarvis() {
        guard !jarvisRunning else { return }
        jarvisRunning = true
        speech.keepAlive = true   // 背景保活：聽寫 session 全程不停用，配 audio 背景模式讓手機收口袋也能跑
        let relay = RelayClient(authKey: AppConfig.authKey)
        let started = Date()
        RemoteLog.send("jarvis v3 start（純聽寫・背景保活開）")
        Task { [weak self] in   // 唯一迴圈：連線＋鏡片畫面＋自動聽寫（無拍照，不搶 session）
            guard let self else { return }
            do {
                try await self.ensureConnected()
                await self.jarvisShow(status: "在聽了", you: "直接講話就好，我會把你的話變成字", ans: "")
            } catch {
                RemoteLog.send("jarvis connect fail: \(error)")
                self.jarvisRunning = false
                return
            }
            while self.jarvisRunning, Date().timeIntervalSince(started) < 900 {
                let heard = await self.listenOnce(maxSeconds: 10)
                guard self.jarvisRunning else { break }
                guard !heard.isEmpty else { continue }
                RemoteLog.send("jarvis heard: \(heard)")
                // 一聽到就立刻：鏡片顯示中文字 ＋ 把逐字稿傳給 COO
                await self.jarvisShow(status: "聽到了", you: heard, ans: "想中…")
                if let qid = try? await relay.askText("[賈維斯] " + heard),
                   let ans = await relay.pollAnswer(id: qid, timeout: 90), self.jarvisRunning {
                    let short = ans.count > 140 ? String(ans.prefix(140)) + "…" : ans
                    await self.jarvisShow(status: "答", you: heard, ans: short)
                }
            }
            self.jarvisRunning = false
            await self.jarvisCleanup()
        }
    }

    /// 賈維斯鏡片畫面（持續連線版：不排自動釋放；含結束鈕）
    private func jarvisShow(status: String, you: String, ans: String) async {
        do {
            guard let s = session, s.state == .started else { return }
            if display == nil {
                let d = try s.addDisplay()
                displayState = nil
                displayToken = d.statePublisher.listen { [weak self] st in
                    Task { @MainActor in self?.displayState = st }
                }
                d.start()
                display = d
            }
            var w = 0
            while displayState != .started && w < 32 {
                try await Task.sleep(nanoseconds: 250_000_000)
                w += 1
            }
            guard displayState == .started, let display else {
                RemoteLog.send("jarvisShow: display not ready (\(String(describing: displayState)))")
                return
            }
            try await display.send(
                FlexBox(direction: .column, spacing: 8) {
                    Text("✦ 賈維斯・" + status, style: .heading)
                    if !you.isEmpty { Text("你：" + you, style: .body, color: .secondary) }
                    if !ans.isEmpty { Text(ans, style: .body) }
                    ButtonGroup {
                        Button(label: "結束賈維斯", onClick: { [weak self] in
                            Task { @MainActor in self?.jarvisRunning = false }
                        })
                    }
                }
                .padding(20)
                .background(.card)
            )
        } catch { RemoteLog.send("jarvisShow fail: \(error)") }
    }

    /// 賈維斯收尾：鏡片顯示結束卡→釋放顯示＋斷線還原眼鏡畫面
    private func jarvisCleanup() async {
        speech.keepAlive = false
        speech.stop()   // 真正停用 audio session、釋放背景保活
        await jarvisShow(status: "已結束", you: "", ans: "畫面即將還原")
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        display?.stop()
        display = nil; displayToken = nil; displayState = nil
        disconnect()
        RemoteLog.send("jarvis v2 stopped，畫面已還原（背景保活關）")
    }

    /// 開機自動自測（董事長「你自己測」令）：綁定過就自動跑一次完整拍照鏈，
    /// 結果全走遙測回報 COO，不需要使用者按任何鍵。每次啟動只跑一次。
    private var selfTestDone = false
    func autoSelfTest() async {
        guard !selfTestDone, registered else { return }
        selfTestDone = true
        RemoteLog.send("selfTest: build=wifi-ent-v7 開始自動自測（等眼鏡在線）")
        var waited = 0
        while !hasDevice && waited < 60 {   // 最多等 30 秒眼鏡上線
            try? await Task.sleep(nanoseconds: 500_000_000); waited += 1
        }
        guard hasDevice else { RemoteLog.send("selfTest: 眼鏡 30 秒內沒上線，略過"); return }
        do {
            let data = try await capturePhoto()
            let id = try await RelayClient(authKey: AppConfig.authKey).uploadPhoto(data)
            RemoteLog.send("selfTest: ✅ 拍照成功 \(data.count)B photo:\(id)")
        } catch {
            RemoteLog.send("selfTest: ❌ \(error)")
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

/// continuation 只准 resume 一次（回調 vs 逾時賽跑）
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

enum GlassesError: LocalizedError {
    case notConnected
    case notRegistered
    case noDeviceOnline
    case sessionTimeout(String)
    case photoTimeout
    case streamNotReady(String)
    case photoRejected
    case cameraPermissionDenied

    var errorDescription: String? {
        switch self {
        case .notConnected: return "還沒連線眼鏡（先按②）"
        case .notRegistered: return "還沒綁定（先按①，跳 Meta AI 按同意）"
        case .noDeviceOnline: return "眼鏡不在線——確認眼鏡開機戴著、Meta AI app 顯示已連線，再按一次"
        case .sessionTimeout(let s): return "連線逾時（卡在 \(s)）——眼鏡收一下再展開重試"
        case .photoTimeout: return "拍照 12 秒沒回應——眼鏡戴著再按一次③；連兩次沒反應就按②重連"
        case .streamNotReady(let s): return "鏡頭串流還沒就緒（\(s)）——等幾秒再按③；一直不行就按②重連"
        case .photoRejected: return "眼鏡拒收拍照指令——按②重連後再試③"
        case .cameraPermissionDenied: return "相機權限沒開——按②會跳 Meta AI，請選「一律允許」再回來"
        }
    }
}
#endif
