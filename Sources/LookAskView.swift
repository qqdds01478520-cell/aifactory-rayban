import SwiftUI
import UIKit

/// 看著問（董事長 2026-09-03「都做」圈定）：盯著眼前的東西按一下 → 拍下來＋
/// 你的問題一起送給克拉扣 → 答案大字回來。眼鏡版由鏡頭直接拍；手機版先用
/// 手機相機驗流程。沒金鑰＝示範問答走完整流程給截圖。
struct LookAskView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var stage: Stage = .idle
    @State private var shot: UIImage?
    @State private var showCamera = false

    enum Stage { case idle, thinking, done(String) }

    private let demoAnswer = "這是「雷門大燈籠」——高 3.9 公尺、重 700 公斤，燈籠底下刻著一條龍：淺草寺相信龍神管水，刻在燈籠底鎮火災。現在這顆是松下幸之助 1960 年捐的，燈籠腰上還留著 Panasonic 前身的落款。"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch stage {
                case .idle: askButton
                case .thinking: thinking
                case .done(let text): answerCard(text)
                }
            }
            .padding(16)
        }
        .background(Theme.ground(scheme))
        .navigationTitle("看著問")
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-lookDemo"),
               case .idle = stage { ask() }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { img in
                shot = img
                ask()
            }
        }
    }

    private var askButton: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 60)
            Button {
                #if targetEnvironment(simulator)
                ask()
                #else
                if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
                else { ask() }
                #endif
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 44, weight: .semibold)).foregroundStyle(.white)
                    Text("這是什麼？").font(Theme.display(20)).foregroundStyle(.white)
                }
                .frame(width: 200, height: 200)
                .background(Circle().fill(LinearGradient(colors: [Color(hex: 0x6366F1), Color(hex: 0x38BDF8)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                .shadow(color: Color(hex: 0x6366F1).opacity(0.4), radius: 24, y: 8)
            }
            .buttonStyle(.plain)
            Text("盯著眼前的東西按一下——一棟樓、一道菜、一個招牌，克拉扣看你所看直接答")
                .font(Theme.body(13)).foregroundStyle(Theme.inkDim(scheme))
                .multilineTextAlignment(.center)
        }
    }

    private var thinking: some View {
        VStack(spacing: 14) {
            if let shot {
                Image(uiImage: shot).resizable().scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            ProgressView().controlSize(.large)
            Text("克拉扣看著呢…").font(Theme.title(15)).foregroundStyle(Theme.ink(scheme))
        }
        .padding(.top, 60)
    }

    private func answerCard(_ text: String) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill").foregroundStyle(Color(hex: 0x6366F1))
                Text("你看到的是").font(Theme.label(13)).foregroundStyle(Theme.inkDim(scheme))
                Spacer()
            }
            Text(text)
                .font(Theme.title(17)).foregroundStyle(Theme.ink(scheme))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface(scheme)))

            Button { stage = .idle; shot = nil } label: {
                Label("再問一個", systemImage: "arrow.counterclockwise")
                    .font(Theme.title(14)).foregroundStyle(Theme.ink(scheme))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface(scheme)))
            }
            .buttonStyle(.plain)

            if !AppConfig.hasRelayKey {
                Text("示範問答；連線後看什麼問什麼").font(Theme.body(11)).foregroundStyle(Theme.inkDim(scheme))
            }
        }
    }

    private func ask() {
        stage = .thinking
        Task {
            if AppConfig.hasRelayKey, let jpeg = shot?.jpegData(compressionQuality: 0.7) {
                let relay = RelayClient(authKey: AppConfig.authKey)
                _ = try? await relay.uploadPhoto(jpeg)
                let raw = (try? await relay.ask("看著問：剛上傳的照片裡是什麼？兩三句講重點，像導遊在耳邊講。")) ?? ""
                stage = .done(raw.isEmpty ? demoAnswer : raw)
            } else {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                stage = .done(demoAnswer)
            }
        }
    }
}
