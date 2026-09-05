import AVFoundation
import Speech

/// 麥克風常駐中樞（董事長 2026-09-05：「一開就常駐把麥克風開著」）。
/// 前一版錯在「app 退背景後才開麥克風」＝iOS 直接把 app 掐死。
/// 正解：app 一啟動（前景）就開一條 AVAudioEngine 常駐錄音——
///   ① 持續有麥克風輸入＝佔住 audio 背景模式，app 永不凍結
///   ② 麥克風「常暖」，要辨識時只是掛一條辨識請求到「已經在流動的 buffer」上，
///      不是在背景重新開麥克風，所以背景也聽得到、不會被掐死。
/// 聽寫走 zh-TW；沒在辨識時 buffer 直接丟掉（麥克風照樣開著）。
@MainActor
final class AudioHub {
    static let shared = AudioHub()

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_TW"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var running = false
    private var finished = false
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

    /// 啟動時（前景）呼叫一次：常駐開麥克風。
    func startAlwaysOn() {
        guard !running else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            // .playAndRecord＋.mixWithOthers＝背景可持續收音又不搶佔別的 app 音訊。
            // ⚠絕不加 .allowBluetooth：眼鏡是藍牙裝置，iOS 會把「麥克風輸入」路由到眼鏡
            //   的 HFP 麥（MWDAT 顯示模式/離線時只給靜音）＝害我們聽到一片空白。強制手機內建麥。
            // mode 用 .default（非 .measurement——.measurement 關掉 AGC，人聲會更小聲難辨識）。
            try s.setCategory(.playAndRecord, mode: .default,
                              options: [.mixWithOthers, .defaultToSpeaker])
            try s.setActive(true, options: [])
            if let ins = s.availableInputs,
               let builtIn = ins.first(where: { $0.portType == .builtInMic }) {
                try? s.setPreferredInput(builtIn)   // 鎖手機內建麥，不吃眼鏡藍牙麥
            }

            let input = engine.inputNode
            let fmt = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
                guard let self else { return }
                self.request?.append(buf)   // 有辨識請求就餵、沒有就丟；麥克風一路開著
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
            RemoteLog.send("audioHub: 麥克風常駐開啟（前景啟動，背景延續聽得到）")

            NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let self, let info = note.userInfo,
                      let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
                Task { @MainActor in self.resume() }
            }
        } catch {
            RemoteLog.send("audioHub 啟動失敗: \(error)")
        }
    }

    private func resume() {
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            if !engine.isRunning { try engine.start() }
            running = engine.isRunning
            RemoteLog.send("audioHub: 中斷後已復活")
        } catch { RemoteLog.send("audioHub resume 失敗: \(error)") }
    }

    /// 聽一句話：最多 maxSeconds 秒，自然停頓（isFinal）就提早收，回最終繁中文字。
    /// 引擎早在前景開好、不重開——所以背景呼叫也 OK，不會被 iOS 掐死。
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
        request = nil   // 停止餵 buffer（麥克風＋引擎仍常駐）
        metering = false
        let route = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "無"
        let out = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // 診斷：麥克風實收峰值音量＋當前輸入路由＋辨識到的字，一次打回遙測
        RemoteLog.send("listenOnce 峰值=\(String(format: "%.3f", peakLevel)) 路由=\(route) 字=「\(out)」")
        return out
    }
}
