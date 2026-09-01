import SwiftUI

/// iPhone 端主畫面：連眼鏡、開語音、看狀態。眼鏡本身的顯示走 GlassesManager。
struct ContentView: View {
    @StateObject private var voice = VoiceAssistant()
    @State private var status = "尚未連線"
    @State private var bridge: RemoteDebugBridge?

    var body: some View {
        VStack(spacing: 20) {
            Text("克拉扣 · 眼鏡版").font(.title.bold())
            Text(status).font(.footnote).foregroundStyle(.secondary)

            Button("連上眼鏡") { Task { await connect() } }
                .buttonStyle(.borderedProminent)

            Button(voice.listening ? "停止聆聽" : "開始講話") {
                Task { await toggleVoice() }
            }
            .buttonStyle(.bordered)

            if !voice.lastQuestion.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("問：\(voice.lastQuestion)").font(.body)
                    Text(voice.lastAnswer).font(.body).foregroundStyle(.blue)
                }.padding()
            }
            Spacer()
        }
        .padding()
    }

    private func connect() async {
        do {
            try await GlassesManager.shared.register()
            try await GlassesManager.shared.connect()
            status = "已連線 · " + GlassesManager.shared.statusText()
            // 啟動遠端除錯橋：COO 可從工廠機下指令自我驗收
            let b = RemoteDebugBridge(authKey: AppConfig.authKey,
                                      executor: GlassesManager.shared)
            bridge = b
            Task { await b.start() }
        } catch {
            status = "連線失敗：\(error)"
        }
    }

    private func toggleVoice() async {
        if voice.listening { voice.stopListening(); return }
        guard await voice.requestPermissions() else { status = "需要麥克風/語音權限"; return }
        do { try voice.startListening() } catch { status = "收音失敗：\(error)" }
    }
}
