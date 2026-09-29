import SwiftUI
import AVFoundation
import UIKit

// 連線設定（董事長 2026-09-29 驗收：新客戶不得看到我們自己的網址；要先裝電腦版、掃精靈上的 QR）
// 出現時機：① RootView 在 hasBase == false 時全畫面顯示（首開／從未設定）
//          ② App 設定 → 伺服器列、連不上控制台頁「掃描 QR 重新連線」→ 以 sheet 開（asSheet: true）
@MainActor
struct ConnectSetupView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var asSheet: Bool = false

    @State private var showScanner = false
    @State private var manual = ""
    @State private var err: String?

    var body: some View {
        VStack(spacing: 0) {
            if asSheet { SheetHeader(title: L("連線設定")) { dismiss() } }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !asSheet { Spacer(minLength: 40) }
                    Text("🖥️").font(.system(size: 44))
                    Text(L("先在電腦上安裝 AI Factory")).font(WF.sans(24, .bold)).foregroundColor(Theme.text)
                    Text(L("電腦版設定精靈的「手機遠端連線」會顯示一個 QR，用下面的按鈕掃它就會自動連上。"))
                        .font(WF.sans(15)).foregroundColor(Theme.text2).fixedSize(horizontal: false, vertical: true)

                    Button {
                        Haptic.tap(); err = nil; showScanner = true
                    } label: {
                        HStack(spacing: 8) { Image(systemName: "qrcode.viewfinder").font(.system(size: 20, weight: .semibold)); Text(L("掃描 QR")) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("或手動輸入網址")).font(WF.sans(13, .semibold)).foregroundColor(Theme.text3)
                        TextField("https://…", text: $manual)
                            .keyboardType(.URL).noAutoCap()
                            .inputWarm(padV: 12, padH: 12, size: 14)
                            .onSubmit { connectManual() }
                        Button(L("連線")) { connectManual() }
                            .buttonStyle(PrimaryButtonStyle())
                            .opacity(manual.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                            .disabled(manual.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.top, 10)

                    if let err {
                        Text(err).font(WF.sans(13)).foregroundColor(Theme.danger).fixedSize(horizontal: false, vertical: true)
                    }
                    if asSheet && !state.baseString.isEmpty {
                        Text(L("目前伺服器：") + state.baseString).font(WF.sans(12)).foregroundColor(Theme.text3).lineLimit(2)
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { if manual.isEmpty && asSheet { manual = state.baseString } }
        .sheet(isPresented: $showScanner) {
            QRScanSheet { code in
                // 回傳 true＝已接受（掃描器停止）；false＝不是連線 QR，繼續掃
                guard let b = AppState.baseFromScan(code) else { return false }
                apply(b)
                return true
            }
        }
    }

    private func connectManual() {
        if !apply(manual) { err = L("網址格式不對，需以 http:// 或 https:// 開頭") }
    }
    @discardableResult
    private func apply(_ raw: String) -> Bool {
        guard state.setBase(raw) else { Haptic.error(); return false }
        Haptic.success(); err = nil
        showScanner = false
        // sheet 模式：等掃描器 sheet 收完再收自己（同時收兩層 sheet 會被 SwiftUI 吃掉）；
        // 全畫面模式：RootView 看到 hasBase 變 true 自動切到 ShellView
        if asSheet { Task { @MainActor in try? await Task.sleep(nanoseconds: 450_000_000); dismiss() } }
        return true
    }
}

// 掃描 QR 的 sheet：管相機權限（未決→詢問；拒絕→說明＋開設定），有權限才放 AVFoundation 掃描器
@MainActor
struct QRScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// 掃到字串 → 回 true 表示接受（掃描停止），false 表示忽略、繼續掃
    let onCode: (String) -> Bool
    @State private var status: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var hint: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("掃描連線 QR")) { dismiss() }
            ZStack {
                Color.black
                switch status {
                case .authorized:
                    QRScannerView { code in
                        let ok = onCode(code)
                        if ok { dismiss() } else { hint = L("這不是連線 QR，請對準電腦畫面上「手機遠端連線」的 QR") }
                        return ok
                    }
                    .ignoresSafeArea(edges: .bottom)
                    VStack {
                        Spacer()
                        Text(hint ?? L("對準電腦畫面上的 QR")).font(WF.sans(14, .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.black.opacity(0.55)).clipShape(Capsule())
                            .padding(.bottom, 32)
                    }
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 230, height: 230)
                case .notDetermined:
                    VStack(spacing: 12) { ProgressView().tint(.white); Text(L("正在請求相機權限…")).foregroundColor(.white).font(WF.sans(14)) }
                default:
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill").font(.system(size: 40)).foregroundColor(.white.opacity(0.8))
                        Text(L("沒有相機權限，無法掃描 QR")).font(WF.sans(16, .semibold)).foregroundColor(.white)
                        Text(L("請到「設定」允許 AI工廠 使用相機，再回來掃描。")).font(WF.sans(13)).foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                        Button(L("開啟設定")) {
                            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                        }
                        .buttonStyle(PrimaryButtonStyle()).frame(width: 200)
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    Task { @MainActor in status = AVCaptureDevice.authorizationStatus(for: .video) }
                }
            }
        }
    }
}

// AVFoundation QR 掃描器（AVCaptureMetadataOutput .qr）包成 SwiftUI
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Bool
    func makeUIViewController(context: Context) -> QRScannerController {
        let vc = QRScannerController()
        vc.onCode = onCode
        return vc
    }
    func updateUIViewController(_ vc: QRScannerController, context: Context) { vc.onCode = onCode }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Bool)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var configured = false
    private var accepted = false
    private var lastIgnored = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.beginConfiguration()
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { session.commitConfiguration(); return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]          // 必須在 addOutput 之後設定
        session.commitConfiguration()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
        configured = true
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        accepted = false
        guard configured, !session.isRunning else { return }
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }   // startRunning 會阻塞，不能在主執行緒
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard session.isRunning else { return }
        let s = session
        DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
    }
    // 協定需求本身非 MainActor：先在 nonisolated 取出字串，再跳主執行緒處理（Swift 6 相容）
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              obj.type == .qr, let text = obj.stringValue, !text.isEmpty else { return }
        Task { @MainActor in self.handleScanned(text) }
    }
    private func handleScanned(_ text: String) {
        guard !accepted, text != lastIgnored else { return }   // 已接受／同一張非連線 QR 不重複回報
        if onCode?(text) == true {
            accepted = true
            Haptic.success()
        } else {
            lastIgnored = text
        }
    }
}
