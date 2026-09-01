import SwiftUI
import Speech
import AVFoundation

/// 繁體中文（zh-TW）語音辨識。按麥克風→聽你講→即時轉成中文字。
/// 模擬器沒有麥克風時，按鈕/UI 照樣在（可截圖）；實機／眼鏡才真的收音。
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isListening = false
    @Published var authorized = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_TW"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    func requestPermission() async {
        let speech = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let mic = await withCheckedContinuation { c in
            AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) }
        }
        authorized = speech && mic
    }

    /// 開始聆聽；每辨識到新內容就更新 transcript，onFinal 在使用者停止時回最終字串。
    func start(onUpdate: @escaping (String) -> Void) {
        guard !isListening, let recognizer, recognizer.isAvailable else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
                self?.request?.append(buf)
            }
            engine.prepare()
            try engine.start()
            isListening = true

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.transcript = text
                    onUpdate(text)
                }
                if error != nil || (result?.isFinal ?? false) { self.stop() }
            }
        } catch {
            stop()
        }
    }

    func stop() {
        guard isListening else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// 三個功能共用的搜尋列：中文鍵盤文字框 ＋ 語音麥克風按鈕 ＋ 送出。
/// accent 帶入該功能的語意色。
struct SearchBar: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var speech = SpeechRecognizer()
    @Binding var text: String
    var accent: Color
    var placeholder: String
    var onSubmit: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkDim(scheme))
                .font(.system(size: 16, weight: .semibold))

            TextField(placeholder, text: $text)
                .font(Theme.body(17))
                .foregroundStyle(Theme.ink(scheme))
                .tint(accent)
                .submitLabel(.search)
                .onSubmit { submit() }

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkDim(scheme))
                }
            }

            Button { Task { await toggleMic() } } label: {
                Image(systemName: speech.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(speech.isListening ? .white : accent)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(speech.isListening ? accent : accent.opacity(0.14))
                    )
                    .symbolEffect(.pulse, isActive: speech.isListening)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surfaceHi(scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(speech.isListening ? accent : Theme.line(scheme), lineWidth: speech.isListening ? 2 : 1)
                )
        )
    }

    private func submit() {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        onSubmit(q)
    }

    private func toggleMic() async {
        if speech.isListening { speech.stop(); submit(); return }
        if !speech.authorized { await speech.requestPermission() }
        guard speech.authorized else { return }
        speech.start { newText in text = newText }
    }
}
