import SwiftUI

// 子頁 C：商城／AI 認證設定／遠端連線

// MARK: - 商城
struct StorePage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @State private var tab = 0
    @State private var products: [StoreProduct] = []
    @State private var central: StoreCentral?
    @State private var centralOk: Bool?
    @State private var owned: [OwnedItem] = []
    @State private var buyer: BuyerAccount?
    @State private var email = ""
    @State private var pw = ""
    @State private var redeemFor: String?
    @State private var code = ""
    @State private var busy = false
    var ownedIds: Set<String> { Set(owned.map { $0.product_id }) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    PageTitle(L("商城"))
                    Spacer()
                    if centralOk == true { Chip(L("中央商城") + " ✓ · \(products.count) " + L("件") + " · " + L("已擁有") + " \(owned.count)", .success) }
                    else if centralOk == false { Chip(L("離線（顯示快取目錄）"), .warn) }
                    else { Chip(L("未連線中央商城"), .muted) }
                }
                Text(L("精選官方商品，直接購買、即時開通。")).font(WF.sans(13)).foregroundColor(Theme.text2)
                SegTabs(items: ["🛒 " + L("逛商城"), "✅ " + L("我的商品") + " (\(owned.count))"], selection: $tab)
                if tab == 0 {
                    if buyer?.logged_in != true { loginCard }
                    if products.isEmpty { EmptyState(icon: "🛒", title: L("目前沒有商品"), subtitle: "") }
                    ForEach(products) { p in productCard(p) }
                } else {
                    if owned.isEmpty { EmptyState(icon: "📦", title: L("尚未擁有任何商品"), subtitle: "") }
                    ForEach(owned) { o in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(o.ptype == "agent" ? "🤖" : "🧩")
                                Text(o.name ?? o.product_id).font(WF.sans(14, .bold)).foregroundColor(Theme.text)
                                Spacer()
                                Chip(L("可使用") + " ✓", .success)
                            }
                            Text(L("解鎖於") + " " + (o.unlocked_at.map { Fmt.isoShort($0) } ?? "—")).font(WF.sans(12)).foregroundColor(Theme.text2)
                            if o.ptype == "agent" {
                                Button("🚀 " + L("部署成員工")) { deploy(o) }.buttonStyle(WarmButtonStyle(padV: 10, full: true))
                            }
                        }.card()
                    }
                }
            }.pageBody()
        }
        .background(Theme.bg.ignoresSafeArea())
        .task { await load() }
    }
    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🔑 " + L("登入商城帳號")).font(WF.sans(14, .bold)).foregroundColor(Theme.text)
            TextField("email", text: $email).noAutoCap().keyboardType(.emailAddress).inputWarm(padV: 10, padH: 12, size: 14)
            SecureField(L("密碼"), text: $pw).inputWarm(padV: 10, padH: 12, size: 14)
            HStack(spacing: 8) {
                Button(L("登入")) { buyerLogin() }.buttonStyle(WarmButtonStyle(padV: 9, padH: 16, size: 13)).disabled(email.isEmpty || pw.isEmpty || busy)
                Button(L("註冊")) { if let u = URL(string: (central?.url ?? "") + "/register"), central?.url != nil { UIApplication.shared.open(u) } else { nav.show(L("未連線中央商城"), "error") } }.buttonStyle(SoftButtonStyle(padV: 9, padH: 16, size: 13))
            }
            Text(L("先以訪客逛逛（購買與同步需登入）")).font(WF.sans(11)).foregroundColor(Theme.text3)
        }.card()
    }
    private func productCard(_ p: StoreProduct) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(p.type == "agent" ? "🤖" : (p.type == "skill" ? "🧩" : "📦"))
                Text(p.name ?? p.id).font(WF.sans(14, .bold)).foregroundColor(Theme.text)
                Spacer()
            }
            HStack(spacing: 6) {
                if p.official == true { Chip(L("官方"), .info) }
                if let s = p.seller_name, p.official != true { Chip("🏪 " + s, .muted) }
                if p.drm == true { Chip("🔐 " + L("防拷保護"), .ai) }
                if ownedIds.contains(p.id) { Chip(L("已擁有") + " ✓", .success) }
                Chip(p.type ?? "—", .muted)
            }
            Text("\(Fmt.num(p.price ?? 0)) \(p.currency ?? "TWD")").font(WF.serif(20, .semibold)).foregroundColor(Theme.primary)
            if let d = p.description, !d.isEmpty { Text(d).font(WF.sans(12)).foregroundColor(Theme.text2).lineLimit(4) }
            if !ownedIds.contains(p.id) {
                HStack(spacing: 8) {
                    Button(L("購買")) { checkout(p) }.buttonStyle(WarmButtonStyle(padV: 9, padH: 16, size: 13)).disabled(busy)
                    Button(L("輸入解鎖碼")) { redeemFor = redeemFor == p.id ? nil : p.id }.buttonStyle(SoftButtonStyle(padV: 9, padH: 16, size: 13))
                }
                if redeemFor == p.id {
                    HStack(spacing: 8) {
                        TextField(L("貼上解鎖碼") + " AIFC-…", text: $code).noAutoCap().inputWarm(padV: 9, padH: 12, size: 13)
                        Button(L("解鎖")) { redeem() }.buttonStyle(WarmButtonStyle(padV: 9, padH: 14, size: 13)).disabled(code.isEmpty || busy)
                    }
                }
            }
        }.card()
    }
    private func load() async {
        if let r: StoreProducts = try? await state.api.request("/api/store/products", timeout: 60) { products = r.products ?? []; centralOk = r.central }
        if let c: StoreCentral = try? await state.api.request("/api/store/central") { central = c; if centralOk == nil { centralOk = c.reachable } }
        if let o: StoreOwned = try? await state.api.request("/api/store/owned") { owned = o.owned ?? [] }
        if let b: BuyerAccount = try? await state.api.request("/api/store/buyer/me") { buyer = b }
        else if let b: BuyerAccount = try? await state.api.request("/api/store/buyer/account") { buyer = b }
    }
    private func buyerLogin() {
        busy = true
        Task {
            do { let r: OkResponse = try await state.api.request("/api/store/buyer/login", method: "POST", body: ["email": email, "password": pw]); if r.ok == false { nav.show(r.error ?? L("登入失敗"), "error") } else { nav.show(L("已登入商城"), "success"); pw = "" } }
            catch { nav.show(error.localizedDescription, "error") }
            await load(); busy = false
        }
    }
    private func checkout(_ p: StoreProduct) {
        busy = true
        Task {
            do {
                let r: CheckoutResponse = try await state.api.request("/api/store/checkout", method: "POST", body: ["product_id": p.id], timeout: 60)
                if let u = r.checkout_url, let url = URL(string: u) { await UIApplication.shared.open(url) } else { nav.show(r.error ?? L("無法建立結帳"), "error") }
            } catch { nav.show(error.localizedDescription, "error") }
            busy = false
        }
    }
    private func redeem() {
        busy = true
        Task {
            do {
                let r: RedeemResponse = try await state.api.request("/api/store/redeem", method: "POST", body: ["code": code.trimmingCharacters(in: .whitespaces)], timeout: 60)
                if r.ok == false { nav.show(r.error ?? r.detail ?? L("解鎖失敗"), "error") } else { nav.show(L("已解鎖"), "success"); Haptic.success(); code = ""; redeemFor = nil }
            } catch { nav.show(error.localizedDescription, "error") }
            await load(); busy = false
        }
    }
    private func deploy(_ o: OwnedItem) {
        Task {
            do { let r: OkResponse = try await state.api.request("/api/store/deploy-agent", method: "POST", body: ["product_id": o.product_id], timeout: 120); if r.ok == false { nav.show(r.error ?? L("部署失敗"), "error") } else { nav.show(L("已部署成員工") + (r.name.map { "：" + $0 } ?? ""), "success"); await state.refreshState() } }
            catch { nav.show(error.localizedDescription, "error") }
        }
    }
}

// MARK: - AI 認證設定
struct ClaudeTokenPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    var internalMode: Bool { state.health?.isInternal ?? false }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(L("AI 認證設定"))
                Text(L("每位員工各自登入；改用 ChatGPT／Grok 額度")).font(WF.sans(13)).foregroundColor(Theme.text2)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("員工怎麼登入 Claude")).font(WF.sans(14, .bold)).foregroundColor(Theme.text)
                    Text(L("憑證是每位員工各自持有的：到那位員工的「終端機」分頁，照畫面提示登入一次即可。")).font(WF.sans(12)).foregroundColor(Theme.text2)
                }.frame(maxWidth: .infinity, alignment: .leading).card()
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Codex 員工（整個換成 OpenAI 的 AI）")).font(WF.sans(14, .bold)).foregroundColor(Theme.text)
                    CodexLoginView()
                }.frame(maxWidth: .infinity, alignment: .leading).card()
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Claude 員工改吃 ChatGPT 額度（免買 Claude 訂閱）")).font(WF.sans(14, .bold)).foregroundColor(Theme.text)
                    ConnectView(kind: .chatgpt)
                    EngineBinderView(internalMode: internalMode)
                }.frame(maxWidth: .infinity, alignment: .leading).card()
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("用 Grok 額度跑員工（免 Claude 訂閱）")).font(WF.sans(14, .bold)).foregroundColor(Theme.text)
                    ConnectView(kind: .grok)
                }.frame(maxWidth: .infinity, alignment: .leading).card()
            }.pageBody()
        }.background(Theme.bg.ignoresSafeArea())
    }
}
struct CodexLoginView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @State private var st: CodexStatus?
    @State private var loggingIn = false
    @State private var lines: [String] = []
    @State private var poll: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if st?.installed == true { Text("✅ " + L("Codex 引擎已安裝")).font(WF.sans(13)).foregroundColor(Theme.success) }
            else if st?.installing == true { HStack { ProgressView().tint(Theme.primary); Text(L("安裝中…") + " \(Int(st?.progress ?? 0))%").font(WF.sans(12)).foregroundColor(Theme.text2) } }
            else { Button("⬇️ " + L("安裝 Codex 引擎")) { post("/api/setup/codex-install") }.buttonStyle(SoftButtonStyle(padV: 9, padH: 14, size: 13)) }
            if st?.logged_in == true { Text("✅ " + L("已登入 Codex（ChatGPT）")).font(WF.sans(13)).foregroundColor(Theme.success) }
            else if st?.installed == true {
                if loggingIn {
                    Text(lines.suffix(8).joined(separator: "\n")).font(WF.mono(11)).foregroundColor(Theme.text).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 8))
                    Button(L("取消登入")) { post("/api/setup/codex-login-cancel"); loggingIn = false; poll?.cancel() }.buttonStyle(SoftButtonStyle(padV: 8, padH: 12, size: 12))
                } else {
                    Button("🔐 " + L("登入我的 ChatGPT（Codex）")) { startLogin() }.buttonStyle(WarmButtonStyle(padV: 9, padH: 14, size: 13))
                }
            }
            if let e = st?.error, !e.isEmpty { Text(e).font(WF.sans(12)).foregroundColor(Theme.danger) }
        }
        .task { await refresh() }
        .onDisappear { poll?.cancel() }
    }
    private func refresh() async { st = try? await state.api.request("/api/setup/codex-status") }
    private func post(_ p: String) { Task { _ = try? await state.api.request(p, method: "POST") as OkResponse; await refresh() } }
    private func startLogin() {
        loggingIn = true; lines = []
        Task {
            _ = try? await state.api.request("/api/setup/codex-login-start", method: "POST") as OkResponse
            poll?.cancel()
            poll = Task {
                struct LS: Decodable { var done: Bool?; var message: String? }
                while !Task.isCancelled {
                    if let b: TerminalBuffer = try? await state.api.request("/api/terminal/buffer/__codex_login__") { lines = (b.lines ?? []).map { ANSI.strip($0) } }
                    if let s: LS = try? await state.api.request("/api/setup/codex-login-status"), s.done == true { loggingIn = false; nav.show(s.message ?? L("完成"), "success"); await refresh(); break }
                    if let u = lines.compactMap({ l -> String? in guard let r = l.range(of: "https://") else { return nil }; return String(l[r.lowerBound...]).components(separatedBy: .whitespaces).first }).first, let url = URL(string: u), !UserDefaults.standard.bool(forKey: "codex_opened_\(u.hashValue)") {
                        UserDefaults.standard.set(true, forKey: "codex_opened_\(u.hashValue)"); await UIApplication.shared.open(url)
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }
}
struct ConnectView: View {
    enum Kind { case chatgpt, grok }
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    let kind: Kind
    @State private var st: ConnectStatus?
    @State private var busy = false
    var statusPath: String { kind == .chatgpt ? "/api/setup/chatgpt-connect-status" : "/api/setup/grok-connect-status" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if st?.connected == true {
                Text(connectedText).font(WF.sans(13)).foregroundColor(Theme.success)
            } else {
                Button(buttonText) { start() }.buttonStyle(WarmButtonStyle(padV: 9, padH: 14, size: 13)).disabled(busy)
                if let s = st?.state, !s.isEmpty, s != "idle" { Text(s).font(WF.sans(11)).foregroundColor(Theme.text3) }
            }
            if let e = st?.error, !e.isEmpty { Text(e).font(WF.sans(12)).foregroundColor(Theme.danger) }
        }
        .task { st = try? await state.api.request(statusPath) }
    }
    private var connectedText: String {
        if kind == .grok { return "✅ " + L("已連接 Grok，員工可用你的 Grok 訂閱額度運作。") }
        var s = "✅ " + L("已連接 ChatGPT")
        if let e = st?.email, !e.isEmpty { s += "（" + e + "）" }
        return s + "，" + L("員工可用你的 ChatGPT 額度運作。")
    }
    private var buttonText: String {
        if busy { return L("連線中…") }
        return "🔗 " + (kind == .chatgpt ? L("連接我的 ChatGPT 帳號") : L("連接我的 Grok 帳號"))
    }
    private func start() {
        busy = true
        Task {
            do {
                if kind == .grok { _ = try? await state.api.request("/api/setup/grok-start", method: "POST") as OkResponse }
                let r: ConnectStart = try await state.api.request(kind == .chatgpt ? "/api/setup/chatgpt-connect-start" : "/api/setup/grok-connect-start", method: "POST", body: ["mode": "browser"], timeout: 60)
                if let u = r.authorization_url, let url = URL(string: u) { await UIApplication.shared.open(url) } else if r.ok == false { nav.show(r.error ?? L("啟動失敗"), "error") }
                for _ in 0..<30 {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    st = try? await state.api.request(statusPath)
                    if st?.connected == true { nav.show(L("已連接"), "success"); break }
                }
            } catch { nav.show(error.localizedDescription, "error") }
            busy = false
        }
    }
}
struct EngineBinderView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    let internalMode: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(state.sortedAgents) { a in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(a.name + (a.steward == true ? "（" + L("管家") + "）" : "")).font(WF.sans(13, .semibold)).foregroundColor(Theme.text)
                        Text("— " + label(a)).font(WF.sans(12)).foregroundColor(Theme.text2)
                    }
                    if a.backend == "codex" {
                        Text("— " + L("Codex 員工（到他的「終端機」照畫面登入 ChatGPT，各自一份）")).font(WF.sans(11)).foregroundColor(Theme.text3)
                    } else {
                        HStack(spacing: 12) {
                            if a.engine != "claude-codex" { link(L("改用 ChatGPT"), a, "claude-codex") }
                            if a.engine != "claude-grok" { link(L("改用 Grok"), a, "claude-grok") }
                            if a.engine == "claude-codex" || a.engine == "claude-grok" { link(L("改回 Claude"), a, "claude") }
                            if !internalMode && (a.engine == nil || a.engine == "claude") {
                                Button(L("這位員工登入 Claude")) { aiLogin(a) }.font(WF.sans(12, .semibold)).foregroundColor(Theme.primary)
                            }
                        }
                    }
                }.padding(.vertical, 4)
                Divider().overlay(Theme.border)
            }
        }
    }
    private func label(_ a: Agent) -> String { a.engine == "claude-codex" ? L("ChatGPT 額度") : (a.engine == "claude-grok" ? L("Grok 額度") : "Claude") }
    private func link(_ t: String, _ a: Agent, _ engine: String) -> some View {
        Button(t) {
            Task {
                do { let _: OkResponse = try await state.api.request("/api/agents/\(a.name)/engine", method: "POST", body: ["engine": engine]); nav.show(L("已切換，重啟員工後生效"), "success"); await state.refreshState() }
                catch { nav.show(error.localizedDescription, "error") }
            }
        }.font(WF.sans(12, .semibold)).foregroundColor(Theme.primary)
    }
    private func aiLogin(_ a: Agent) {
        Task {
            do {
                let r: AiLoginStatus = try await state.api.request("/api/agents/\(a.name)/ai-login", method: "POST", body: ["mode": "browser"], timeout: 60)
                if r.already == true || r.connected == true { nav.show(L("已登入"), "success") }
                else if let u = r.authorization_url, let url = URL(string: u) { await UIApplication.shared.open(url) }
                else { nav.show(r.error ?? L("啟動失敗"), "error") }
            } catch { nav.show(error.localizedDescription, "error") }
        }
    }
}

// MARK: - 遠端連線
struct RemotePage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @State private var seg = 0
    @State private var tunnel: TunnelStatus?
    @State private var busy = false
    @State private var poll: Task<Void, Never>?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(L("遠端連線"))
                Text(L("讓手機掃 QR code 就能連上你的 Dashboard。")).font(WF.sans(13)).foregroundColor(Theme.text2)
                SegTabs(items: [L("快速連線"), L("固定網址")], selection: $seg)
                if tunnel?.installed == false {
                    Text(L("尚未安裝連線工具（cloudflared），請先在電腦端控制台完成安裝。")).font(WF.sans(12)).foregroundColor(Theme.warning).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0xc49a2c, alpha: 0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
                }
                if tunnel?.running == true { runningCard }
                else if seg == 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("快速連線（零設定）")).font(WF.sans(14, .bold)).foregroundColor(Theme.text)
                        Text(L("一鍵產生臨時網址，手機掃描即可連上。")).font(WF.sans(12)).foregroundColor(Theme.text2)
                        Button(busy ? L("啟動中…") : L("一鍵啟動遠端連線")) { start() }.buttonStyle(WarmButtonStyle(padV: 12, full: true)).disabled(busy)
                    }.frame(maxWidth: .infinity, alignment: .leading).card()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("固定網址（永遠不換）")).font(WF.sans(14, .bold)).foregroundColor(Theme.text)
                        Text(L("由管家幫你在 Cloudflare 開通一條固定網址，之後手機書籤永遠有效。")).font(WF.sans(12)).foregroundColor(Theme.text2)
                        Button(L("請管家幫我開通固定網址")) { askSteward() }.buttonStyle(WarmButtonStyle(padV: 12, full: true))
                    }.frame(maxWidth: .infinity, alignment: .leading).card()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("運作原理")).font(WF.sans(14, .bold)).foregroundColor(Theme.text)
                    Text(L("電腦端透過 Cloudflare Tunnel 把控制台安全地送到外網；手機用 HTTPS 連線，不用改路由器、不用固定 IP。")).font(WF.sans(12)).foregroundColor(Theme.text2)
                }.frame(maxWidth: .infinity, alignment: .leading).card()
                if let e = tunnel?.error, !e.isEmpty { Text(e).font(WF.sans(12)).foregroundColor(Theme.danger) }
            }.pageBody()
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            poll?.cancel()
            poll = Task { while !Task.isCancelled { tunnel = try? await state.api.request("/api/tunnel/status"); try? await Task.sleep(nanoseconds: 5_000_000_000) } }
        }
        .onDisappear { poll?.cancel() }
    }
    private var runningCard: some View {
        VStack(alignment: .center, spacing: 10) {
            Text(L("手機掃描連線")).font(WF.sans(14, .bold)).foregroundColor(Theme.text)
            if let q = tunnel?.qr, let img = dataImage(q) { Image(uiImage: img).resizable().interpolation(.none).frame(width: 200, height: 200) }
            Text(tunnel?.url ?? "").font(WF.mono(12)).foregroundColor(Theme.text).textSelection(.enabled).multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button(L("複製")) { UIPasteboard.general.string = tunnel?.url; nav.show(L("已複製"), "success") }.buttonStyle(SoftButtonStyle(padV: 8, padH: 14, size: 12))
                Chip(L("連線中"), .success)
                Chip(tunnel?.mode == "named" ? L("固定網址") : L("臨時網址（重啟會換）"), tunnel?.mode == "named" ? .info : .warn)
            }
            Button(L("停止連線")) { stop() }.buttonStyle(SoftButtonStyle(padV: 10, full: true, bg: Color(hex: 0xb5341a, alpha: 0.1), fg: Theme.tagError))
        }.frame(maxWidth: .infinity).card()
    }
    private func dataImage(_ s: String) -> UIImage? {
        guard let comma = s.firstIndex(of: ",") else { return nil }
        guard let d = Data(base64Encoded: String(s[s.index(after: comma)...])) else { return nil }
        return UIImage(data: d)
    }
    private func start() {
        busy = true
        Task {
            do { let r: OkResponse = try await state.api.request("/api/tunnel/start", method: "POST", body: ["mode": "quick"], timeout: 90); if r.ok == false { nav.show(r.error ?? L("啟動失敗"), "error") } }
            catch { nav.show(error.localizedDescription, "error") }
            tunnel = try? await state.api.request("/api/tunnel/status"); busy = false
        }
    }
    private func stop() {
        Task { _ = try? await state.api.request("/api/tunnel/stop", method: "POST") as OkResponse; tunnel = try? await state.api.request("/api/tunnel/status") }
    }
    private func askSteward() {
        Task {
            do {
                let r: MessageResp = try await state.api.request("/api/remote-access/ask-steward", method: "POST", timeout: 60)
                if r.ok == true { nav.show(L("已交給管家") + (r.who.map { "（\($0)）" } ?? "") + L("，完成後這裡會出現固定網址"), "success", ms: 4000) }
                else if r.pending == true { nav.show(r.message ?? L("管家處理中"), "info", ms: 4000) }
                else { nav.show(r.error ?? r.message ?? L("失敗"), "error") }
            } catch { nav.show(error.localizedDescription, "error") }
        }
    }
}
