import SwiftUI
import UIKit
#if canImport(MWDATCore)
import MWDATCore
import MWDATCamera
#endif

/// 眼鏡分頁（2026-09-22 重做：董事長「別在歪地基上補，從新做一個app、照別人真的做出來的做」）。
/// 整段**照抄 Meta 官方範例 facebook/meta-wearables-dat-ios/samples/CameraAccess 的 CameraViewModel**
/// ——最簡三步：Start Session（createSession→start→聽 state）→ Preview（addCamera→stream.start）。
/// 刻意**不啟動 AudioHub／指令橋／任何背景麥**（omi 產品原碼註明：背景 HFP 麥會害 DAT 相機 session 開不起來）。
/// MWDAT 編譯期存在才有實功能。
struct GlassesView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        #if canImport(MWDATCore)
        DATLabView()
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

/// 乾淨版 DAT 相機生命週期——**逐段對照 Meta 官方 CameraViewModel**，用 Wearables.shared 直呼，
/// 不碰舊 GlassesManager 的任何 cruft。每個 state 轉換都 RemoteLog，方便遠端讀董手機判斷卡在哪一步。
@MainActor
final class DATLab: ObservableObject {
    @Published var regText = "-"
    @Published var sessionText = "idle"
    @Published var streamText = "stopped"
    @Published var hasActiveDevice = false
    @Published var note = "照 Meta 官方範例最簡三步：①連線(註冊) → ②Start Session → ③Preview 開相機。每步的眼鏡回應我都會遠端收到。"

    private var session: DeviceSession?
    private var camera: Camera?
    private var sessionTokens: [Any] = []
    private var streamTokens: [Any] = []
    private var deviceMonitorTask: Task<Void, Never>?
    private let selector = AutoDeviceSelector(wearables: Wearables.shared)

    init() {
        regText = "\(Wearables.shared.registrationState)"
        // 只監看裝置在不在（抄 Meta startDeviceMonitoring），不自動建 session。
        deviceMonitorTask = Task { [weak self] in
            guard let self else { return }
            for await dev in self.selector.activeDeviceStream() {
                self.hasActiveDevice = (dev != nil)
                RemoteLog.send("DATLab activeDevice → \(dev == nil ? "nil" : "online")")
            }
        }
        // 註冊狀態流
        Task { [weak self] in
            for await st in Wearables.shared.registrationStateStream() {
                self?.regText = "\(st)"
                RemoteLog.send("DATLab reg → \(st)")
            }
        }
    }

    // ① 連線＝註冊（抄 Meta connectGlasses：只叫 startRegistration，其餘走 Meta AI app）
    func connect() async {
        do {
            if Wearables.shared.registrationState == .registered {
                note = "已註冊 ✅ 直接按②Start Session"
                RemoteLog.send("DATLab connect(): already registered")
                return
            }
            RemoteLog.send("DATLab startRegistration…")
            try await Wearables.shared.startRegistration()
            note = "已送出註冊——手機會跳 Meta AI，按同意後回來，再按②"
        } catch {
            note = "註冊失敗：\(error.localizedDescription)"
            RemoteLog.send("DATLab register FAIL: \(error)")
        }
    }

    // ② Start Session＝**逐字抄 Meta CameraViewModel.startSession**：createSession→observe→.starting→start()
    //    Meta 這裡不等 linkState、不先要相機權限，就是這麼簡單。
    func startSession() {
        guard session == nil else { note = "session 已存在"; return }
        do {
            let s = try Wearables.shared.createSession(deviceSelector: selector)
            session = s
            observe(s)                    // 訂閱先於 start，才不漏第一個狀態
            sessionText = "starting"
            RemoteLog.send("DATLab session.start()…")
            try s.start()
        } catch {
            note = "開 session 失敗：\(error.localizedDescription)"
            RemoteLog.send("DATLab startSession catch: \(error)")
            cleanupSession()
        }
    }

    func endSession() {
        guard let s = session else { return }
        sessionText = "stopping"
        s.stop()
    }

    // ③ Preview＝抄 Meta startStreaming/beginStream：session 要在 .started；相機權限查→(沒有就要)→addCamera→start
    func startPreview() async {
        guard let s = session, s.state == .started else {
            note = "先讓 session 到 started 再開相機（現在：\(sessionText)）"; return
        }
        guard camera == nil else { return }
        do {
            let status = try await Wearables.shared.checkPermissionStatus(.camera)
            RemoteLog.send("DATLab camera perm = \(status)")
            if status != .granted {
                let res = try await Wearables.shared.requestPermission(.camera)
                RemoteLog.send("DATLab camera perm after request = \(res)")
                guard res == .granted else { note = "相機權限被拒"; return }
            }
            beginStream(on: s)
        } catch {
            note = "相機權限查詢失敗：\(error.localizedDescription)"
            RemoteLog.send("DATLab perm catch: \(error)")
        }
    }

    private func beginStream(on s: DeviceSession) {
        guard camera == nil else { return }
        let cfg = StreamConfiguration(videoCodec: .hvc1, resolution: .low, frameRate: 24)
        do {
            guard let c = try s.addCamera(config: cfg) else {
                note = "addCamera 回 nil（相機建不起來）"; RemoteLog.send("DATLab addCamera nil"); return
            }
            camera = c
            setupStream(c.stream)
            streamText = "starting"
            RemoteLog.send("DATLab stream.start()…")
            c.stream.start()
        } catch {
            camera = nil
            note = "addCamera 失敗：\(error.localizedDescription)"
            RemoteLog.send("DATLab beginStream catch: \(error)")
        }
    }

    private func observe(_ s: DeviceSession) {
        sessionTokens.append(s.statePublisher.listen { [weak self] st in
            RemoteLog.send("DATLab session state → \(st)")
            Task { @MainActor in
                self?.sessionText = "\(st)"
                if st == .started { self?.note = "✅ session 起來了！按③Preview 開相機" }
                if st == .stopped { self?.cleanupSession() }
            }
        })
        sessionTokens.append(s.errorPublisher.listen { [weak self] err in
            RemoteLog.send("DATLab session ERROR → \(err)")
            Task { @MainActor in self?.note = "session 錯誤：\(err.localizedDescription)（\(err)）" }
        })
    }

    private func setupStream(_ stream: MWDATCamera.Stream) {
        streamTokens.append(stream.statePublisher.listen { [weak self] st in
            RemoteLog.send("DATLab stream state → \(st)")
            Task { @MainActor in
                self?.streamText = "\(st)"
                if st == .streaming { self?.note = "🎥 相機串流成功！這條路通了。" }
            }
        })
        streamTokens.append(stream.errorPublisher.listen { err in
            RemoteLog.send("DATLab stream ERROR → \(err)")
        })
    }

    private func cleanupSession() {
        sessionTokens.removeAll()
        streamTokens.removeAll()
        camera = nil
        session = nil
        streamText = "stopped"
    }
}

struct DATLabView: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var lab = DATLab()
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("DAT 原生實驗室")
                    .font(Theme.display(20)).foregroundStyle(Theme.ink(scheme))
                Text("2026-09-22 重做・照 Meta 官方 CameraAccess 範例・已拿掉背景搶麥")
                    .font(Theme.body(11)).foregroundStyle(Theme.inkDim(scheme))

                stateGrid

                btn("① 連線（Meta AI 註冊）", "link") { await lab.connect() }
                btn("② Start Session", "antenna.radiowaves.left.and.right") { lab.startSession() }
                btn("③ Preview（開相機）", "camera.fill") { await lab.startPreview() }
                btn("停止 Session", "stop.circle") { lab.endSession() }

                Text(lab.note)
                    .font(Theme.body(13)).foregroundStyle(Theme.inkDim(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface(scheme)))
            }
            .padding(16)
        }
        .background(Theme.ground(scheme))
    }

    private var stateGrid: some View {
        VStack(spacing: 6) {
            row("裝置在線", lab.hasActiveDevice ? "是" : "否")
            row("註冊", lab.regText)
            row("Session", lab.sessionText)
            row("Stream", lab.streamText)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface(scheme)))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Theme.body(13)).foregroundStyle(Theme.inkDim(scheme))
            Spacer()
            Text(v).font(Theme.title(14)).monospaced().foregroundStyle(Theme.ink(scheme))
        }
    }

    private func btn(_ title: String, _ icon: String, _ action: @escaping () async -> Void) -> some View {
        Button {
            guard !busy else { return }
            busy = true
            Task { await action(); busy = false }
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
