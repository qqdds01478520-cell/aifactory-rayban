// 第二批「隨時中文語音對話」用（會把答案上鏡，依賴 GlassesManager）。
// 第一批純手機 UI 不編譯它——搜尋列的語音輸入已由 SpeechInput.swift 提供。
#if canImport(MWDATCore)
import Foundation
import AVFoundation
import Speech

/// 中文語音問答迴圈：眼鏡麥克風(藍牙HFP路由) → 語音辨識(zh-TW) →
/// RelayClient.ask(送 COO) → 回答朗讀(AVSpeechSynthesizer) + 上鏡(GlassesManager)。
///
/// 註：DAT SDK 無麥克風/喇叭 API，這裡走 iOS 原生 AVAudioEngine + Speech。
/// 眼鏡連上後系統會把它當藍牙輸入/輸出裝置（與藍牙耳機同理，非 SDK 保證）。
@MainActor
final class VoiceAssistant: ObservableObject {
    @Published var lastQuestion = ""
    @Published var lastAnswer = ""
    @Published var listening = false

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_TW"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let synth = AVSpeechSynthesizer()
    private let relay = RelayClient(authKey: AppConfig.authKey)

    func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micOK = await withCheckedContinuation { c in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        return speechOK && micOK
    }

    /// 開始收音辨識；偵測到一句完整的話就送出問答。
    func startListening() throws {
        let sess = AVAudioSession.sharedInstance()
        try sess.setCategory(.playAndRecord, mode: .videoRecording,
                             options: [.allowBluetooth, .defaultToSpeaker])
        try sess.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in
            req.append(buf)
        }
        engine.prepare()
        try engine.start()
        listening = true

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result, result.isFinal {
                let text = result.bestTranscription.formattedString
                Task { await self.handleQuestion(text) }
            }
            if error != nil { Task { @MainActor in self.stopListening() } }
        }
    }

    func stopListening() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
        listening = false
    }

    /// 一句話 → 送 COO → 朗讀 + 上鏡。
    func handleQuestion(_ text: String) async {
        guard !text.isEmpty else { return }
        lastQuestion = text
        stopListening()
        let answer = (try? await relay.ask(text)) ?? "連線出了點問題，等一下再問一次。"
        lastAnswer = answer
        speak(answer)
        try? await GlassesManager.shared.showText(title: "問：\(text)", body: answer)
    }

    private func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-TW")
        synth.speak(u)
    }
}
#endif
