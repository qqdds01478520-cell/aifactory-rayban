import SwiftUI

// 登入頁＝網頁 LoginPage：Af 標誌卡片、歡迎回來、帳號/密碼 input-warm、記住帳密、忘記密碼／註冊、首次建管理員、重設密碼
struct LoginView: View {
    enum Mode { case login, setup, register, reset }
    @EnvironmentObject var state: AppState
    @EnvironmentObject var l10n: L10n
    @State private var mode: Mode = .login
    @State private var user = Keychain.get("saved_user") ?? ""
    @State private var pass = Keychain.get("saved_pass") ?? ""
    @State private var confirmPw = ""
    @State private var regEmail = ""
    @State private var resetCode = ""
    @State private var newPw = ""
    @State private var resetStep = 0
    @State private var remember = true
    @State private var server = ""
    @State private var showServer = false
    @State private var busy = false
    @State private var err = ""
    @State private var info = ""
    @FocusState private var focus: Int?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            // 極光光暈
            Circle().fill(Theme.primary.opacity(0.10)).frame(width: 360, height: 360).blur(radius: 60).offset(x: -140, y: -300)
            Circle().fill(Theme.accent.opacity(0.12)).frame(width: 320, height: 320).blur(radius: 60).offset(x: 160, y: 300)
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 70)
                    card.padding(.horizontal, 16)
                    Text("AI Factory " + L("控制台") + " · " + L("商用版")).font(WF.sans(11)).foregroundColor(Theme.text3).padding(.top, 18)
                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            VStack { HStack { Spacer(); LanguagePill().padding(.top, 8).padding(.trailing, 16) }; Spacer() }
        }
        .onAppear { server = state.baseString; Task { await checkSetup() } }
    }

    // MARK: card
    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Spacer(); logo; Spacer() }.padding(.bottom, 14)
            HStack { Spacer(); Text(title).font(WF.serif(26, .semibold)).foregroundColor(Theme.text); Spacer() }
            HStack { Spacer(); Text(subtitle).font(WF.sans(13)).foregroundColor(Theme.text2).multilineTextAlignment(.center); Spacer() }.padding(.top, 4).padding(.bottom, 22)
            fields
            if !err.isEmpty {
                Text(err).font(WF.sans(13)).foregroundColor(Theme.danger).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(Color(hex: 0xb5341a, alpha: 0.1)).clipShape(RoundedRectangle(cornerRadius: 10)).padding(.top, 12)
            }
            if !info.isEmpty {
                Text(info).font(WF.sans(13)).foregroundColor(Theme.success).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10).background(Color(hex: 0x4a8c5c, alpha: 0.1)).clipShape(RoundedRectangle(cornerRadius: 10)).padding(.top, 12)
            }
            Button(busy ? L("驗證中…") : primaryLabel) { submit() }
                .buttonStyle(PrimaryButtonStyle()).disabled(busy || !canSubmit).opacity(canSubmit ? 1 : 0.6)
                .padding(.top, 16)
            links.padding(.top, 14)
            serverRow.padding(.top, 10)
        }
        .padding(.top, 34).padding(.horizontal, 30).padding(.bottom, 28)
        .frame(maxWidth: 380)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow(color: Color(hex: 0x2c1810, alpha: 0.1), radius: 24, x: 0, y: 12)
    }
    private var logo: some View {
        Text("Af").font(WF.serif(26, .semibold)).foregroundColor(.white)
            .frame(width: 60, height: 60)
            .background(LinearGradient(colors: [Theme.primary, Theme.primaryHover], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Theme.primary.opacity(0.3), radius: 10, y: 5)
    }
    private var title: String {
        switch mode { case .login: return L("歡迎回來"); case .setup: return L("建立管理員帳號"); case .register: return L("建立新帳號"); case .reset: return L("重設密碼") }
    }
    private var subtitle: String {
        switch mode {
        case .login: return L("登入 AI Factory 控制台")
        case .setup: return L("首次啟動，請設定您的管理員帳號")
        case .register: return L("填寫資料即可建立帳號並登入")
        case .reset: return resetStep == 0 ? L("輸入帳號，我們會產生重設碼") : L("輸入重設碼與新密碼")
        }
    }
    private var primaryLabel: String {
        switch mode { case .login: return L("登入"); case .setup: return L("建立並登入"); case .register: return L("註冊"); case .reset: return resetStep == 0 ? L("取得重設碼") : L("確認重設") }
    }
    private var canSubmit: Bool {
        switch mode {
        case .login: return !user.isEmpty && !pass.isEmpty
        case .setup: return !user.isEmpty && pass.count >= 1 && pass == confirmPw
        case .register: return !user.isEmpty && !pass.isEmpty && pass == confirmPw
        case .reset: return resetStep == 0 ? !user.isEmpty : (!resetCode.isEmpty && !newPw.isEmpty)
        }
    }

    @ViewBuilder private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            field(L("帳號"), L("請輸入帳號"), text: $user, secure: false, tag: 0)
            if mode == .register { field("Email", L("用來找回密碼（選填）"), text: $regEmail, secure: false, tag: 3).keyboardType(.emailAddress) }
            if mode == .login || mode == .setup || mode == .register {
                field(L("密碼"), L("請輸入密碼"), text: $pass, secure: true, tag: 1)
            }
            if mode == .setup || mode == .register { field(L("確認密碼"), L("再輸入一次密碼"), text: $confirmPw, secure: true, tag: 2) }
            if mode == .reset && resetStep == 1 {
                field(L("重設碼"), L("貼上重設碼"), text: $resetCode, secure: false, tag: 4)
                field(L("新密碼"), L("至少 8 碼"), text: $newPw, secure: true, tag: 5)
            }
            if mode == .login {
                Button { remember.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: remember ? "checkmark.square.fill" : "square").foregroundColor(remember ? Theme.primary : Theme.text3)
                        Text(L("記住帳密（下次自動登入）")).font(WF.sans(13)).foregroundColor(Theme.text2)
                    }
                }.padding(.top, 2)
            }
        }
    }
    private func field(_ label: String, _ placeholder: String, text: Binding<String>, secure: Bool, tag: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(WF.sans(12, .semibold)).foregroundColor(Theme.text2)
            Group {
                if secure { SecureField(placeholder, text: text) } else { TextField(placeholder, text: text) }
            }
            .noAutoCap()
            .focused($focus, equals: tag)
            .submitLabel(.go)
            .onSubmit { submit() }
            .inputWarm()
        }
    }
    @ViewBuilder private var links: some View {
        HStack {
            switch mode {
            case .login:
                Button(L("忘記密碼？")) { switchMode(.reset) }.font(WF.sans(13)).foregroundColor(Theme.text2).underline()
                Spacer()
                Button(L("還沒有帳號？註冊")) { switchMode(.register) }.font(WF.sans(13)).foregroundColor(Theme.primary).underline()
            case .setup:
                Spacer()
            case .register, .reset:
                Button(L("已有帳號？登入")) { switchMode(.login) }.font(WF.sans(13)).foregroundColor(Theme.primary).underline()
                Spacer()
            }
        }
    }
    private var serverRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation { showServer.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "server.rack").font(.system(size: 11))
                    Text(server.isEmpty ? DEFAULT_BASE : server).font(WF.sans(11)).lineLimit(1)
                }.foregroundColor(Theme.text3)
            }
            if showServer {
                TextField(L("伺服器網址"), text: $server).noAutoCap().keyboardType(.URL).inputWarm(padV: 10, padH: 12, size: 13)
            }
        }
    }

    private func switchMode(_ m: Mode) { withAnimation { mode = m; err = ""; info = ""; resetStep = 0 } }

    // 首次啟動 → 建管理員（GET /api/auth/needs-setup）
    private func checkSetup() async {
        do {
            try state.applyServer(server.isEmpty ? DEFAULT_BASE : server)
            struct NS: Decodable { var needs_setup: Bool? }
            let r: NS = try await state.api.request("/api/auth/needs-setup", auth: false, retry: false, timeout: 10)
            if r.needs_setup == true { mode = .setup }
        } catch { }
    }

    private func submit() {
        guard !busy, canSubmit else { return }
        busy = true; err = ""; info = ""
        Task {
            do {
                let srv = server.isEmpty ? DEFAULT_BASE : server
                try state.applyServer(srv)
                switch mode {
                case .login:
                    try await state.login(user: user, pass: pass, server: srv)
                    if remember { Keychain.set(user, for: "saved_user"); Keychain.set(pass, for: "saved_pass") }
                    else { Keychain.delete("saved_user"); Keychain.delete("saved_pass") }
                case .setup:
                    let r: LoginResponse = try await state.api.request("/api/auth/setup", method: "POST",
                        body: ["username": user, "password": pass, "error_tour": true], auth: false, retry: false)
                    await state.finishLogin(r, user: user)
                case .register:
                    let r: LoginResponse = try await state.api.request("/api/auth/register", method: "POST",
                        body: ["username": user, "password": pass, "email": regEmail, "error_tour": true], auth: false, retry: false)
                    await state.finishLogin(r, user: user)
                case .reset:
                    if resetStep == 0 {
                        let r: MessageResp = try await state.api.request("/api/auth/reset/request", method: "POST",
                            body: ["username": user], auth: false, retry: false)
                        if r.ok == false { err = r.error ?? r.message ?? L("無法產生重設碼") }
                        else { info = r.message ?? L("重設碼已產生，請向管理員或信箱取得"); withAnimation { resetStep = 1 } }
                    } else {
                        let r: MessageResp = try await state.api.request("/api/auth/reset/confirm", method: "POST",
                            body: ["username": user, "code": resetCode, "new_password": newPw], auth: false, retry: false)
                        if r.ok == false { err = r.error ?? r.message ?? L("重設失敗") }
                        else { info = L("密碼已重設，請用新密碼登入"); pass = ""; withAnimation { mode = .login; resetStep = 0 } }
                    }
                }
            } catch { err = error.localizedDescription; Haptic.error() }
            busy = false
        }
    }
}
