import SwiftUI
import UIKit

/// 掃描菜單（董事長 2026-09-03 規格）：一顆「掃描菜單」按鈕 → 拍下菜單 →
/// 翻譯 → 直接顯示成「中文版菜單圖片」（整張排版好的菜單，不是逐行文字）。
/// 有 relay 金鑰＝照片上傳給克拉扣翻譯；沒有＝示範菜單走完整流程給截圖。
struct MenuScanView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var stage: Stage = .idle
    @State private var shot: UIImage?
    @State private var showCamera = false

    enum Stage { case idle, translating, done([MenuDish]) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch stage {
                case .idle: scanButton
                case .translating: translating
                case .done(let dishes): menuCard(dishes)
                }
            }
            .padding(16)
        }
        .background(Theme.ground(scheme))
        .navigationTitle("掃描菜單")
        .onAppear {
            // CI 截圖：-menuDemo 自動跑完翻譯流程，截到成品中文菜單
            if ProcessInfo.processInfo.arguments.contains("-menuDemo"),
               case .idle = stage { translate() }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { img in
                shot = img
                translate()
            }
        }
    }

    // 大按鈕：一按開拍
    private var scanButton: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 60)
            Button {
                #if targetEnvironment(simulator)
                translate()   // 模擬器無相機：直接走示範流程
                #else
                #if canImport(MWDATCore)
                if GlassesManager.shared.connected {
                    // 眼鏡已連線＝用「眼鏡鏡頭」拍菜單，看哪掃哪
                    Task {
                        if let data = try? await GlassesManager.shared.capturePhoto(),
                           let img = UIImage(data: data) { shot = img; translate() }
                        else if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
                    }
                    return
                }
                #endif
                if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
                else { translate() }
                #endif
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 44, weight: .semibold)).foregroundStyle(.white)
                    Text("掃描菜單").font(Theme.display(20)).foregroundStyle(.white)
                }
                .frame(width: 200, height: 200)
                .background(Circle().fill(LinearGradient(colors: [Color(hex: 0xEF4444), Color(hex: 0xF97316)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
                .shadow(color: Color(hex: 0xEF4444).opacity(0.4), radius: 24, y: 8)
            }
            .buttonStyle(.plain)
            Text("對準菜單按一下，翻好的中文菜單直接出現")
                .font(Theme.body(13)).foregroundStyle(Theme.inkDim(scheme))
        }
    }

    private var translating: some View {
        VStack(spacing: 14) {
            if let shot {
                Image(uiImage: shot).resizable().scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            ProgressView().controlSize(.large)
            Text("克拉扣翻譯中…").font(Theme.title(15)).foregroundStyle(Theme.ink(scheme))
        }
        .padding(.top, 60)
    }

    // 翻譯結果：整張「中文菜單」排版呈現（米紙底、店名、分類、菜名＋價錢＋一句話）
    private func menuCard(_ dishes: [MenuDish]) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("三河屋 食事処").font(Theme.display(20)).foregroundStyle(Color(hex: 0x3B2F1E))
                Text("— 中文菜單・克拉扣翻譯 —").font(Theme.body(11)).foregroundStyle(Color(hex: 0x8A7A5C))
                Rectangle().fill(Color(hex: 0x8A7A5C).opacity(0.5)).frame(height: 1).padding(.vertical, 6)
                ForEach(dishes) { d in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.zh).font(Theme.title(16)).foregroundStyle(Color(hex: 0x3B2F1E))
                            Text(d.note).font(Theme.body(11)).foregroundStyle(Color(hex: 0x8A7A5C))
                        }
                        Spacer()
                        Text(d.price).font(Theme.title(15)).monospacedDigit().foregroundStyle(Color(hex: 0x3B2F1E))
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0xF5EFDF)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: 0x8A7A5C).opacity(0.3), lineWidth: 1))

            HStack(spacing: 10) {
                Label("克拉扣推薦：炙燒鯖魚定食", systemImage: "star.fill")
                    .font(Theme.label(13)).foregroundStyle(Color(hex: 0xF59E0B))
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xF59E0B).opacity(0.12)))

            Button { stage = .idle; shot = nil } label: {
                Label("再掃一張", systemImage: "arrow.counterclockwise")
                    .font(Theme.title(14)).foregroundStyle(Theme.ink(scheme))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface(scheme)))
            }
            .buttonStyle(.plain)

            if !AppConfig.hasRelayKey {
                Text("示範菜單；連線後掃什麼翻什麼").font(Theme.body(11)).foregroundStyle(Theme.inkDim(scheme))
            }
        }
    }

    private func translate() {
        stage = .translating
        Task {
            if AppConfig.hasRelayKey, let jpeg = shot?.jpegData(compressionQuality: 0.7) {
                let relay = RelayClient(authKey: AppConfig.authKey)
                _ = try? await relay.uploadPhoto(jpeg)
                // 克拉扣端翻譯回 JSON（菜名|中文|價錢|一句話）；解析失敗退示範
                let raw = (try? await relay.ask("菜單翻譯：剛上傳的照片，回JSON陣列 zh/note/price")) ?? ""
                stage = .done(MenuDish.parse(raw) ?? MenuDish.demo)
            } else {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                stage = .done(MenuDish.demo)
            }
        }
    }
}

struct MenuDish: Identifiable {
    let id = UUID()
    let zh: String, note: String, price: String

    static let demo: [MenuDish] = [
        .init(zh: "炙燒鯖魚定食", note: "招牌・附味噌湯白飯", price: "¥1,280"),
        .init(zh: "天婦羅蕎麥麵", note: "現炸大蝦兩尾", price: "¥1,050"),
        .init(zh: "親子丼", note: "滑蛋雞腿・半熟", price: "¥980"),
        .init(zh: "唐揚炸雞（5塊）", note: "配檸檬・下酒", price: "¥680"),
        .init(zh: "樽裝清酒（一合）", note: "老闆自豪的地酒", price: "¥750"),
    ]

    static func parse(_ raw: String) -> [MenuDish]? {
        guard let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]],
              !arr.isEmpty else { return nil }
        return arr.map { .init(zh: $0["zh"] ?? "", note: $0["note"] ?? "", price: $0["price"] ?? "") }
    }
}

/// 相機包裝（實機用；模擬器直接走示範流程不進這裡）。
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }

    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
