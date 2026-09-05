import AVFoundation
import Speech

/// 麥克風收音中樞。董事長 2026-09-05：「點開 app 手機就背景錄音」要拿掉——
/// 改成不常駐、不自動錄音：只有 listenOnce 要聽的當下才 startAlwaysOn 開麥、
/// 聽完 stopEngine 立刻關（橘色麥克風點只在聽的那幾秒亮，平常完全不錄）。
/// 收音來源：眼鏡藍牙 HFP 麥優先（眼鏡連上時），否則退手機內建麥。聽寫走 zh-TW。
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

    /// 開麥克風收音（只在 listenOnce 要聽的當下呼叫；聽完 stopEngine 關掉）。
    /// 不再開機常駐——董事長 2026-09-05 要求平常不錄音。
    func startAlwaysOn() {
        guard !running else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            // 董事長要「眼鏡聽」。Meta 官方：眼鏡 5 麥直接串流留給 Meta AI，第三方拿眼鏡收音
            //   官方指定走「iOS 藍牙 profile」＝眼鏡當藍牙耳麥、mic 走 Bluetooth HFP 進手機。
            //   所以要 .allowBluetoothHFP，並把 preferredInput 明確鎖到 bluetoothHFP 埠（眼鏡）。
            // mode 用 .videoRecording（照官方 CameraAccess 範例，眼鏡收音走這個 mode）。
            try s.setCategory(.playAndRecord, mode: .videoRecording,
                              options: [.allowBluetoothHFP, .mixWithOthers, .defaultToSpeaker])
            try s.setActive(true, options: [])
            // 優先鎖眼鏡藍牙麥；眼鏡沒接上才退回手機內建麥（並在遙測講明用哪支）。
            if let ins = s.availableInputs {
                if let hfp = ins.first(where: { $0.portType == .bluetoothHFP }) {
                    try? s.setPreferredInput(hfp)
                    RemoteLog.send("audioHub: 鎖眼鏡藍牙麥 \(hfp.portName)")
                } else if let builtIn = ins.first(where: { $0.portType == .builtInMic }) {
                    try? s.setPreferredInput(builtIn)
                    RemoteLog.send("audioHub: ⚠眼鏡藍牙麥沒接上，暫用手機麥（戴上眼鏡+藍牙連上再試）")
                }
            }

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
            RemoteLog.send("audioHub: 開麥克風收音（聽的當下才開）")

            guard !observersInstalled else { return }
            observersInstalled = true
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let self, let info = note.userInfo,
                      let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
                Task { @MainActor in self.resume() }
            }
            // 路由變（眼鏡連上/斷開）就重挑輸入麥，讓眼鏡一連上就自動切成眼鏡麥。
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.preferGlassesMic() }
            }
        } catch {
            RemoteLog.send("audioHub 啟動失敗: \(error)")
        }
    }

    /// 有眼鏡藍牙麥就鎖眼鏡、沒有退手機麥（路由變時呼叫）。閒置不錄音時不動。
    private func preferGlassesMic() {
        guard running else { return }
        let s = AVAudioSession.sharedInstance()
        guard let ins = s.availableInputs else { return }
        if let hfp = ins.first(where: { $0.portType == .bluetoothHFP }) {
            try? s.setPreferredInput(hfp)
            RemoteLog.send("audioHub: 路由變→切眼鏡藍牙麥 \(hfp.portName)")
        } else if let builtIn = ins.first(where: { $0.portType == .builtInMic }) {
            try? s.setPreferredInput(builtIn)
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

    /// 聽一句話：當下才開麥（startAlwaysOn）→最多 maxSeconds 秒、自然停頓(isFinal)就提早收
    /// →回最終繁中文字→stopEngine 關麥。⚠背景中呼叫會開麥＝iOS 可能掐死 app，要前景/眼鏡觸發。
    func listenOnce(maxSeconds: Int = 10) async -> String {
        if !authorized { await requestPermission() }
        guard authorized else { return "" }
        if !running { startAlwaysOn() }
        guard running, let recognizer, recognizer.isAvailable else { return "" }

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
        stopEngine()   // 聽完立刻關麥（董事長要：平常不錄音，橘點只在聽的當下亮）
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
