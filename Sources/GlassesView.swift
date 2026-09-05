import SwiftUI
import UIKit

/// 眼鏡分頁（第二批，董事長 2026-09-03「全部做完」令）：
/// 綁定 Ray-Ban Display → 連線 → 實測「眼鏡拍照」「送字上鏡片」。
/// MWDAT 在編譯期存在才有實功能；不存在時顯示誠實說明（模擬器截圖批）。
struct GlassesView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        #if canImport(MWDATCore)
        GlassesLiveView()
        #else
        VStack(spacing: 14) {
            Spacer(minLength: 80)
            Image(systemName: "eyeglasses").font(.system(size: 52)).foregroundStyle(Theme.glasses)
            Text("此版未編入眼鏡 SDK").font(Theme.title(17)).foregroundStyle(Theme.ink(scheme))
            Text("正式簽署版才含 MWDAT；請安裝 /install 連結的正式版。")
                .font(Theme.body(13)).foregroundStyle(Theme.inkDim(scheme))
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.ground(scheme))
        #endif
    }
}

#if canImport(MWDATCore)
struct GlassesLiveView: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var gm = GlassesManager.shared
    @State private var busy = false
    @State private var log = "尚未綁定。步驟：①綁定（跳 Meta AI app 授權）→ ②連線 → ③實測。"
    @State private var photo: UIImage?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard
                actionButton("① 綁定眼鏡（Meta AI 授權）", icon: "link") {
                    try await GlassesManager.shared.register()
                    log = "已送出綁定請求——手機會跳 Meta AI app，按同意後回來。"
                    // 送出後盯 25 秒：等 Meta AI 回調把狀態翻成已綁定；沒翻＝老實報診斷
                    for _ in 0..<50 {
                        try await Task.sleep(nanoseconds: 500_000_000)
                        if GlassesManager.shared.registered { break }
                    }
                    if GlassesManager.shared.registered {
                        log = "綁定成功 ✅ 接著按②連線"
                    } else {
                        let err = GlassesManager.shared.lastError
                        log = "同意後仍未綁定。可能：Meta AI 沒回跳本 app／眼鏡未在 Meta AI 連線／授權被 Meta 端拒絕。"
                            + (err.isEmpty ? "" : "\n錯誤：\(err)")
                        RemoteLog.send("bind watchdog: still unregistered after 25s, lastError=\(err.isEmpty ? "-" : err)")
                    }
                }
                actionButton("② 連線眼鏡", icon: "antenna.radiowaves.left.and.right") {
                    try await GlassesManager.shared.connect()
                    log = "已連線 ✅ " + GlassesManager.shared.statusText()
                }
                actionButton("③ 眼鏡拍一張（鏡頭實測）", icon: "camera.fill") {
                    let data = try await GlassesManager.shared.capturePhoto()
                    photo = UIImage(data: data)
                    log = "眼鏡拍照成功 ✅ \(data.count) bytes"
                }
                actionButton("④ 送字上鏡片（顯示實測）", icon: "text.bubble.fill") {
                    try await GlassesManager.shared.showText(
                        title: "克拉扣 OS",
                        body: "鏡片顯示測試成功——" + Date().formatted(date: .omitted, time: .shortened))
                    log = "已送字上鏡片 ✅ 抬頭看一下"
                }
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(alignment: .bottomLeading) {
                            Text("↑ 這張是眼鏡鏡頭拍的").font(Theme.label(12))
                                .padding(6).background(.black.opacity(0.6))
                                .foregroundStyle(.white).clipShape(Capsule()).padding(8)
                        }
                }
                Text(log)
                    .font(Theme.body(13)).foregroundStyle(Theme.inkDim(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface(scheme)))
            }
            .padding(16)
        }
        .background(Theme.ground(scheme))
        .onAppear { GlassesManager.shared.watchState() }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "eyeglasses").font(.system(size: 30)).foregroundStyle(Theme.glasses)
            VStack(alignment: .leading, spacing: 3) {
                Text("Ray-Ban Display").font(Theme.title(16)).foregroundStyle(Theme.ink(scheme))
                Text(gm.connected ? "已連線・鏡頭與鏡片可用"
                     : gm.registered ? "已綁定・尚未連線" : "未綁定")
                    .font(Theme.body(12))
                    .foregroundStyle(gm.connected ? Theme.maps : Theme.inkDim(scheme))
            }
            Spacer()
            Circle().fill(gm.connected ? Theme.maps : gm.registered ? Theme.brand : Theme.inkDim(scheme))
                .frame(width: 10, height: 10)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface(scheme)))
    }

    private func actionButton(_ title: String, icon: String,
                              action: @escaping () async throws -> Void) -> some View {
        Button {
            guard !busy else { return }
            busy = true
            Task {
                do { try await action() }
                catch {
                    log = "失敗：\(error.localizedDescription)（\(error)）"
                    RemoteLog.send("GlassesView action FAIL: \(error)")
                }
                busy = false
            }
        } label: {
            HStack {
                Image(systemName: icon).frame(width: 26)
                Text(title).font(Theme.title(15))
                Spacer()
                if busy { ProgressView().controlSize(.small) }
            }
            .foregroundStyle(Theme.ink(scheme))
            .padding(.vertical, 13).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surfaceHi(scheme)))
        }
        .buttonStyle(.plain)
    }
}
#endif
