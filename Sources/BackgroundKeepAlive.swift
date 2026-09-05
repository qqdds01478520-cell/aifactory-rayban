import AVFoundation

/// 背景常駐保活（董事長 2026-09-05：「我一次裝以後你自己遠端搞」）。
/// iOS 會凍結退到背景的第三方 app，害遠端指令橋收不到單。解法＝跟音樂/語音助理一樣，
/// app 一啟動就開一條「無聲循環音訊」佔住 audio 背景模式，系統就不會凍結我們。
/// 手機收口袋、鎖屏、切到別的 app，克拉扣照樣活著領遠端指令。
/// 平時用 .playback（不開麥克風＝不亮橘點）；賈維斯要收音時 SpeechRecognizer 自己切 .playAndRecord。
@MainActor
final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var started = false

    func start() {
        guard !started else { return }
        do {
            let s = AVAudioSession.sharedInstance()
            // .mixWithOthers＝不搶佔別的 app 音訊（保活但不打擾）；不停用＝背景常駐
            try s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try s.setActive(true, options: [])

            let fmt = engine.outputNode.outputFormat(forBus: 0)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: fmt)

            // 1 秒全零（靜音）buffer，無限循環播——持續有音訊輸出才會被系統當「正在播放」而不凍結
            let frames = AVAudioFrameCount(max(fmt.sampleRate, 1))
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else {
                RemoteLog.send("keepAlive: buffer 建立失敗"); return
            }
            buf.frameLength = frames   // 內容全 0 = 靜音

            engine.prepare()
            try engine.start()
            player.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
            player.play()
            started = true
            RemoteLog.send("keepAlive: 背景音訊保活啟動（app 永不凍結，可全程遠端）")

            // 被電話/鬧鐘等中斷後自動復活
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let self,
                      let info = note.userInfo,
                      let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
                Task { @MainActor in self.resume() }
            }
        } catch {
            RemoteLog.send("keepAlive 啟動失敗: \(error)")
        }
    }

    /// 被中斷後把 session 與播放拉回來
    private func resume() {
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            if !engine.isRunning { try engine.start() }
            if !player.isPlaying { player.play() }
            RemoteLog.send("keepAlive: 中斷後已復活")
        } catch {
            RemoteLog.send("keepAlive resume 失敗: \(error)")
        }
    }
}
