import SwiftUI

// 更多＝網頁 MorePage：系統狀態卡、🧭 重看新手教學、錯誤導覽教學開關、管理／內容／監控分區、我的插件、登出、刪除帳號
struct MoreView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @EnvironmentObject var l10n: L10n
    @State private var errorTour = false
    @State private var plugins: [UserPlugin] = []
    @State private var pluginsLoaded = false
    @State private var adding = false
    @State private var newName = ""
    @State private var newUrl = ""
    @State private var showDelete = false
    @State private var showSettings = false
    @State private var pendingRemove: Int?
    var internalMode: Bool { state.health?.isInternal ?? false }
    static let defaultPlugins: [UserPlugin] = [
        UserPlugin(name: "GPU 排程器", url: "/plugin-proxy/scheduler/", page: nil, proxied: true),
        UserPlugin(name: "影片成品區", url: nil, page: "products", proxied: nil),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageTitle(L("更多"))
                healthCard
                tutorialCard
                errorTourCard
                MoreSection(title: L("管理"), rows: manageRows)
                MoreSection(title: L("內容"), rows: [MoreRow(icon: "🛒", label: L("商城"), desc: L("購買並用解鎖碼解鎖員工/技能"), action: { nav.open(.store) })])
                MoreSection(title: L("監控"), rows: [MoreRow(icon: "📊", label: L("Token 用量"), desc: L("7 天用量統計"), action: { nav.open(.usage) })])
                MoreSection(title: "App", rows: [MoreRow(icon: "📲", label: L("App 設定"), desc: L("Face ID、觸覺、背景更新、推播、快取、版本"), action: { showSettings = true })])
                pluginsSection
                Button(L("登出")) { state.logout() }
                    .buttonStyle(SoftButtonStyle(padV: 14, size: 14, full: true, bg: Theme.surface, fg: Theme.text2, border: true))
                Button(L("刪除帳號")) { showDelete = true }
                    .font(WF.sans(13, .semibold)).foregroundColor(Theme.danger).frame(maxWidth: .infinity).padding(.top, 4)
            }
            .pageBody()
        }
        .background(Theme.bg.ignoresSafeArea())
        .task {
            if let r: ErrorTour = try? await state.api.request("/api/error-tour") { errorTour = r.enabled ?? false }
            await loadPlugins()
        }
        .sheet(isPresented: $showDelete) { DeleteAccountSheet() }
        .sheet(isPresented: $showSettings) { AppSettingsSheet() }
        .confirmationDialog(L("移除這個插件？"), isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }), titleVisibility: .visible) {
            Button(L("移除"), role: .destructive) {
                if let i = pendingRemove, i < plugins.count { plugins.remove(at: i); Task { await savePlugins() } }
                pendingRemove = nil
            }
        }
    }

    private var healthOk: Bool { let s = state.health?.status ?? ""; return s == "ok" || s == "healthy" }
    private var healthCard: some View {
        HStack(spacing: 10) {
            Circle().fill(state.health == nil ? Theme.text3 : (healthOk ? Theme.success : Theme.danger)).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("系統狀態：") + (state.health == nil ? L("連線中") : (healthOk ? L("正常") : L("異常")))).font(WF.sans(14, .semibold)).foregroundColor(Theme.text)
                Text("v\(state.health?.version ?? "—") | " + L("運行") + " " + Fmt.uptime(state.health?.uptime_seconds ?? 0)).font(WF.sans(12)).foregroundColor(Theme.text2)
            }
            Spacer()
        }.card()
    }
    private var tutorialCard: some View {
        Button {
            Task {
                _ = try? await state.api.request("/api/tutorial/progress", method: "POST", body: ["done": false, "step": 0]) as OkResponse
                _ = try? await state.api.request("/api/onboarding/complete", method: "POST", body: ["done": false]) as OkResponse
                nav.show(L("已重設新手教學：下次在電腦或手機瀏覽器開控制台會從頭帶你走一遍"), "success", ms: 4000)
            }
        } label: {
            HStack(spacing: 12) {
                Text("🧭").font(.system(size: 20)).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("重看新手教學")).font(WF.sans(14, .medium)).foregroundColor(Theme.text)
                    Text(L("手機遠端連線、AI 認證、建立第一個員工")).font(WF.sans(12)).foregroundColor(Theme.text2)
                }
                Spacer()
                Text("›").foregroundColor(Theme.text3)
            }.card()
        }.buttonStyle(.plain)
    }
    private var errorTourCard: some View {
        Button {
            let next = !errorTour
            Task {
                do { let _: OkResponse = try await state.api.request("/api/error-tour", method: "POST", body: ["enabled": next]); errorTour = next }
                catch { nav.show(error.localizedDescription, "error") }
            }
        } label: {
            HStack(spacing: 12) {
                Text("🧭").font(.system(size: 20)).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("錯誤導覽教學")).font(WF.sans(14, .medium)).foregroundColor(Theme.text)
                    Text(L("跳出錯誤訊息時，問你要不要一步步帶你解決")).font(WF.sans(12)).foregroundColor(Theme.text2)
                }
                Spacer()
                WebSwitch(on: errorTour)
            }.card()
        }.buttonStyle(.plain)
    }

    private var manageRows: [MoreRow] {
        var rows: [MoreRow] = []
        if internalMode { rows.append(MoreRow(icon: "🔧", label: L("管理後台"), desc: L("平台總覽、內容審核"), action: { nav.open(.admin) })) }
        rows.append(MoreRow(icon: "📱", label: L("遠端連線"), desc: L("手機掃 QR code 連線（固定網址）"), action: { nav.open(.remote) }))
        rows.append(MoreRow(icon: "🔐", label: L("AI 認證設定"), desc: L("每位員工各自登入；改用 ChatGPT／Grok 額度"), action: { nav.open(.claudeToken) }))
        rows.append(MoreRow(icon: "💾", label: L("備份管理"), desc: L("建立、還原、刪除備份"), action: { nav.open(.backup) }))
        if state.isAdmin { rows.append(MoreRow(icon: "👥", label: L("用戶管理"), desc: L("新增、停權、重設密碼、刪除用戶"), action: { nav.open(.users) })) }
        if internalMode { rows.append(MoreRow(icon: "🔑", label: L("授權管理"), desc: L("發行、啟用、撤銷授權碼"), action: { nav.open(.license) })) }
        rows.append(MoreRow(icon: "📚", label: L("知識庫"), desc: L("員工的知識／設定檔"), action: { nav.open(.knowledge) }))
        rows.append(MoreRow(icon: "🔍", label: L("搜尋"), desc: L("可搜尋 Discord 訊息及 Agent 工作階段紀錄"), action: { nav.open(.search) }))
        return rows
    }

    // MARK: 我的插件
    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("我的插件")).font(WF.sans(12, .bold)).foregroundColor(Theme.text2)
                Spacer()
                Button(adding ? L("取消") : "＋ " + L("新增")) { withAnimation { adding.toggle() } }
                    .font(WF.sans(12, .semibold)).foregroundColor(Theme.primary)
            }
            if adding { addForm }
            VStack(spacing: 0) {
                if !pluginsLoaded { ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding() }
                ForEach(Array(plugins.enumerated()), id: \.element.id) { i, p in
                    PluginRow(plugin: p, open: { nav.openPlugin(p) }, remove: { pendingRemove = i })
                    if i < plugins.count - 1 { Divider().overlay(Theme.border).padding(.leading, 60) }
                }
                if pluginsLoaded && plugins.isEmpty { Text(L("尚無插件")).font(WF.sans(13)).foregroundColor(Theme.text3).frame(maxWidth: .infinity).padding() }
            }.card(pad: 0)
        }
    }
    private var addForm: some View {
        VStack(spacing: 8) {
            TextField(L("名稱（例：GPU 排程器）"), text: $newName).formField()
            TextField(L("網址（例：http://localhost:8930/）"), text: $newUrl).noAutoCap().keyboardType(.URL).formField()
            Button(L("儲存")) {
                let n = newName.trimmingCharacters(in: .whitespaces), u = newUrl.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty, !u.isEmpty else { return }
                plugins.append(UserPlugin(name: n, url: u, page: nil, proxied: nil))
                newName = ""; newUrl = ""; adding = false
                Task { await savePlugins() }
            }.buttonStyle(WarmButtonStyle(padV: 10, full: true))
        }.card()
    }
    private func loadPlugins() async {
        // 同網頁：伺服器有存就照存的顯示；沒存才用預設兩顆（GPU 排程器＋影片成品區）
        if let r: UserPluginsResponse = try? await state.api.request("/api/user-plugins"), let p = r.plugins, !p.isEmpty { plugins = p }
        else { plugins = Self.defaultPlugins }
        pluginsLoaded = true
    }
    private func savePlugins() async {
        let arr: [[String: Any]] = plugins.map { p in
            var d: [String: Any] = ["name": p.name]
            if let u = p.url { d["url"] = u }
            if let pg = p.page { d["page"] = pg }
            if let pr = p.proxied { d["proxied"] = pr }
            return d
        }
        do { let _: OkResponse = try await state.api.request("/api/user-plugins", method: "POST", body: ["plugins": arr]) }
        catch { nav.show(error.localizedDescription, "error") }
    }
}

struct MoreRow: Identifiable { let icon: String; let label: String; let desc: String; let action: () -> Void; var id: String { label } }
// 分區：h2 12px text-2 粗體大寫 ＋ 卡片列（icon 20 w32 / label 14 / desc 12 / ›）
struct MoreSection: View {
    let title: String
    let rows: [MoreRow]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(WF.sans(12, .bold)).foregroundColor(Theme.text2).tracking(0.5)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    Button(action: r.action) {
                        HStack(spacing: 12) {
                            Text(r.icon).font(.system(size: 20)).frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.label).font(WF.sans(14, .medium)).foregroundColor(Theme.text)
                                Text(r.desc).font(WF.sans(12)).foregroundColor(Theme.text2).lineLimit(1)
                            }
                            Spacer()
                            Text("›").foregroundColor(Theme.text3)
                        }.padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if i < rows.count - 1 { Divider().overlay(Theme.border).padding(.leading, 60) }
                }
            }.card(pad: 0)
        }
    }
}
struct PluginRow: View {
    let plugin: UserPlugin
    let open: () -> Void
    let remove: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Text(plugin.page == "products" ? "🎞️" : "🧩").font(.system(size: 20)).frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plugin.name).font(WF.sans(14, .medium)).foregroundColor(Theme.text)
                        Text(plugin.page == "products" ? L("控制台內建頁") : (plugin.url ?? "")).font(WF.sans(12)).foregroundColor(Theme.text2).lineLimit(1)
                    }
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(action: remove) { Text("✕").font(WF.sans(13)).foregroundColor(Theme.text3).frame(width: 28, height: 28) }
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// 刪除帳號（ModalSheet：警語、密碼、確認輸入「刪除」、永久刪除我的帳號）
struct DeleteAccountSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @Environment(\.dismiss) var dismiss
    @State private var pw = ""
    @State private var confirm = ""
    @State private var busy = false
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("刪除帳號")) { dismiss() }
            VStack(alignment: .leading, spacing: 12) {
                Text(L("這會永久刪除你的帳號與登入資料，無法復原。員工與資料檔仍留在這台電腦上。")).font(WF.sans(13)).foregroundColor(Theme.danger)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0xb5341a, alpha: 0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
                Text(L("密碼")).font(WF.sans(12, .semibold)).foregroundColor(Theme.text2)
                SecureField(L("請輸入密碼"), text: $pw).inputWarm()
                Text(L("確認（請輸入「刪除」二字）")).font(WF.sans(12, .semibold)).foregroundColor(Theme.text2)
                TextField(L("刪除"), text: $confirm).inputWarm()
                Button(busy ? "…" : L("永久刪除我的帳號")) { doDelete() }
                    .buttonStyle(WarmButtonStyle(padV: 12, full: true, bg: Theme.danger))
                    .disabled(busy || pw.isEmpty || (confirm != "刪除" && confirm.lowercased() != "delete"))
            }.padding(20)
            Spacer()
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
    private func doDelete() {
        busy = true
        Task {
            do {
                let _: OkResponse = try await state.api.request("/api/auth/account", method: "DELETE", body: ["password": pw])
                dismiss(); state.logout()
            } catch { nav.show(error.localizedDescription, "error") }
            busy = false
        }
    }
}

// 原生 app 專屬設定（Face ID／觸覺／背景更新／派工目標／推播／伺服器／版本／快取）
struct AppSettingsSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var l10n: L10n
    @Environment(\.dismiss) var dismiss
    @State private var cacheSize = DiskCache.sizeBytes
    var version: String {
        let d = Bundle.main.infoDictionary
        return "\(d?["CFBundleShortVersionString"] as? String ?? "") (\(d?["CFBundleVersion"] as? String ?? ""))"
    }
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("App 設定")) { dismiss() }
            List {
                Section {
                    Toggle(L("Face ID 鎖定"), isOn: $state.faceIDEnabled)
                    Toggle(L("觸覺回饋"), isOn: $state.hapticsEnabled)
                    Toggle(L("背景更新"), isOn: $state.bgRefreshEnabled)
                    Picker(L("分享派工目標員工"), selection: $state.dispatchAgent) { ForEach(state.sortedAgents) { a in Text(a.name).tag(a.name) } }
                }.listRowBackground(Theme.surface)
                Section {
                    Button {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    } label: {
                        HStack { Text(L("推播通知")).foregroundColor(Theme.text); Spacer(); Text(state.pushStatus).foregroundColor(Theme.text2); Text("›").foregroundColor(Theme.text3) }
                    }
                    HStack { Text(L("伺服器")); Spacer(); Text(state.baseString).font(WF.sans(12)).foregroundColor(Theme.text2).lineLimit(1) }
                    HStack { Text(L("App 版本")); Spacer(); Text(version).foregroundColor(Theme.text2) }
                    HStack { Text(L("離線快取")); Spacer(); Text(Fmt.bytes(cacheSize)).foregroundColor(Theme.text2) }
                    Button(L("清除快取")) { DiskCache.clear(); cacheSize = 0; Haptic.medium() }
                }.listRowBackground(Theme.surface)
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .onChange(of: state.bgRefreshEnabled) { on in if on { state.scheduleBackgroundRefresh() } }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
