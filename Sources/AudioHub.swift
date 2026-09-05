import AVFoundation
import Speech

/// 麥克風收音中樞。董事長 2026-09-05 定調：手機常駐錄音＝不要；眼鏡常駐背景聽＝可以。
/// 所以：**只用眼鏡藍牙 HFP 麥**——眼鏡連著就把麥一直開著、背景持續聽（跟連續轉錄助手一樣）；
/// 眼鏡一斷開就立刻關麥，**絕不掉回用手機內建麥錄音**。聽寫走 zh-TW。
/// 眼鏡連上/斷開靠 routeChange 監看自動開關（syncToGlasses）。
@MainActor
final class AudioHub {
    static let shared = AudioHub()

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_TW"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var running = false
    private var finished = false
    private var observersInstalled = false
    private var metering = false
    private var peakLevel: Float = 0   // 聽寫期間麥克風實際收到的最大音量（診斷用）

    var transcript = ""
    var authorized = false

    func requestPermission() async {
        let sp = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let mic = await withCheckedContinuation { c in
            AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) }
        }
        authorized = sp && mic
    }

    /// 啟用（app 一開就呼叫一次）：設好 audio session＋掛路由/中斷監看，
    /// 然後 syncToGlasses——眼鏡藍牙連著就開麥常駐、沒連就完全不錄。
    func startAlwaysOn() {
        let s = AVAudioSession.sharedInstance()
        do {
            // 眼鏡收音走 Bluetooth HFP：.allowBluetoothHFP＋mode .videoRecording（照官方範例）。
            try s.setCategory(.playAndRecord, mode: .videoRecording,
                              options: [.allowBluetoothHFP, .mixWithOthers, .defaultToSpeaker])
        } catch { RemoteLog.send("audioHub 設定 session 失敗: \(error)") }

        if !observersInstalled {
            observersInstalled = true
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let self, let info = note.userInfo,
                      let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
                Task { @MainActor in self.resume() }
            }
            // 路由變（眼鏡連上/斷開）→ 重新對齊：連上就開眼鏡麥、斷開就關麥。
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.syncToGlasses() }
            }
        }
        syncToGlasses()
    }

    /// 眼鏡藍牙麥連著→開麥常駐（背景持續聽）；沒連著→關麥、絕不掉回手機麥錄音。
    /// 董事長 2026-09-05：手機常駐錄音不要，眼鏡常駐背景聽可以。
    private func syncToGlasses() {
        let s = AVAudioSession.sharedInstance()
        let hfp = s.availableInputs?.first(where: { $0.portType == .bluetoothHFP })
        if let hfp {
            if !running { beginCapture(preferred: hfp) }
        } else {
            if running {
                stopEngine()
                RemoteLog.send("audioHub: 眼鏡斷開→關麥（不掉回手機麥）")
            }
        }
    }

    /// 真正開麥收音（只在偵測到眼鏡藍牙麥時呼叫）。
    private func beginCapture(preferred: AVAudioSessionPortDescription) {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setActive(true, options: [])
            try? s.setPreferredInput(preferred)
            let input = engine.inputNode
            let fmt = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
                guard let self else { return }
                self.request?.append(buf)   // 有辨識請求就餵給辨識器
                if self.metering, let ch = buf.floatChannelData?[0] {
                    var mx: Float = 0
                    let n = Int(buf.frameLength)
                    for i in 0..<n { let v = abs(ch[i]); if v > mx { mx = v } }
                    if mx > self.peakLevel { self.peakLevel = mx }
                }
            }
            engine.prepare()
            try engine.start()
            running = true
            RemoteLog.send("audioHub: 眼鏡藍牙麥常駐開啟 \(preferred.portName)（背景持續聽）")
        } catch {
            RemoteLog.send("audioHub 開眼鏡麥失敗: \(error)")
        }
    }

    private func resume() {
        guard running else { return }   // 閒置（沒在聽）就不自動復活麥克風
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            if !engine.isRunning { try engine.start() }
            running = engine.isRunning
            RemoteLog.send("audioHub: 中斷後已復活")
        } catch { RemoteLog.send("audioHub resume 失敗: \(error)") }
    }

    /// 聽一句話：掛一條辨識請求到「眼鏡麥已在流動的 buffer」上，最多 maxSeconds 秒、
    /// 自然停頓(isFinal)就提早收，回最終繁中文字。眼鏡沒連＝不開麥、直接回空（不掉回手機麥）。
    func listenOnce(maxSeconds: Int = 10) async -> String {
        if !authorized { await requestPermission() }
        guard authorized else { return "" }
        if !running { syncToGlasses() }   // 眼鏡連著會開起來；沒連仍是 false
        guard running, let recognizer, recognizer.isAvailable else {
            RemoteLog.send("listenOnce: 眼鏡沒連上藍牙→沒開麥（戴上眼鏡+藍牙連線再試）")
            return ""
        }

        transcript = ""
        finished = false
        peakLevel = 0
        metering = true
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result { self.transcript = result.bestTranscription.formattedString }
            if error != nil || (result?.isFinal ?? false) { self.finished = true }
        }
        for _ in 0..<(maxSeconds * 4) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if finished { break }
        }
        req.endAudio()
        task?.cancel()
        task = nil
        request = nil
        metering = false
        let inPort = AVAudioSession.sharedInstance().currentRoute.inputs.first
        let route = inPort?.portName ?? "無"
        let which = inPort?.portType == .bluetoothHFP ? "眼鏡麥" : (inPort?.portType == .builtInMic ? "手機麥" : "其他")
        let out = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // 診斷：麥克風實收峰值音量＋當前用哪支麥＋辨識到的字，一次打回遙測
        RemoteLog.send("listenOnce 用\(which)(\(route)) 峰值=\(String(format: "%.3f", peakLevel)) 字=「\(out)」")
        // 不關麥——眼鏡常駐背景聽（董事長要）。眼鏡斷開時 syncToGlasses 才會關。
        return out
    }

    /// 關掉麥克風引擎＋放掉 audio session，回到「完全不錄音」狀態。
    private func stopEngine() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        RemoteLog.send("audioHub: 已關麥克風（回到不錄音）")
    }
}
