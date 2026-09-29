import SwiftUI

// 子頁 B：授權管理／使用者管理／管理後台／公司

// MARK: - 授權管理（internal）
struct LicensePage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @State private var list: [LicenseItem] = []
    @State private var hwid = ""
    @State private var showIssue = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { PageTitle(L("授權管理")); Spacer(); Button("+ " + L("發行")) { showIssue = true }.buttonStyle(WarmButtonStyle(padV: 8, padH: 14, size: 13)) }
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel(L("本機 HWID"))
                    Text(hwid.isEmpty ? "—" : hwid).font(WF.mono(12)).foregroundColor(Theme.text).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading).card()
                if list.isEmpty { EmptyState(icon: "🔑", title: L("尚無授權碼"), subtitle: "") }
                ForEach(list) { l in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text(l.key).font(WF.mono(11)).foregroundColor(Theme.text).textSelection(.enabled)
                            Spacer()
                            Chip(statusText(l), statusKind(l))
                        }
                        Text(licenseMeta(l)).font(WF.sans(12)).foregroundColor(Theme.text2)
                        HStack(spacing: 8) {
                            if l.status != "active" && l.status != "revoked" { Button(L("啟用")) { post("/api/license/activate", ["key": l.key, "hwid": hwid]) }.buttonStyle(SoftButtonStyle(padV: 7, padH: 12, size: 12, bg: Color(hex: 0x4a8c5c, alpha: 0.12), fg: Theme.success)) }
                            if l.status != "revoked" { Button(L("撤銷")) { post("/api/license/revoke", ["key": l.key]) }.buttonStyle(SoftButtonStyle(padV: 7, padH: 12, size: 12, bg: Color(hex: 0xb5341a, alpha: 0.1), fg: Theme.tagError)) }
                        }
                    }.card()
                }
            }.pageBody()
        }
        .background(Theme.bg.ignoresSafeArea())
        .task { await load() }
        .sheet(isPresented: $showIssue) { IssueLicenseSheet { await load() } }
    }
    private func statusText(_ l: LicenseItem) -> String { l.status == "active" ? L("啟用中") : (l.status == "revoked" ? L("已撤銷") : L("待啟用")) }
    private func statusKind(_ l: LicenseItem) -> ChipKind { l.status == "active" ? .success : (l.status == "revoked" ? .danger : .warn) }
    private func licenseMeta(_ l: LicenseItem) -> String {
        var s = L("租戶:") + " " + (l.tenant_id ?? "—") + "  " + L("方案:") + " " + (l.tier ?? "—")
        if let e = l.expires_at { s += "  ⏳ " + Fmt.isoShort(e) }
        return s
    }
    private func load() async {
        if let r: LicenseList = try? await state.api.request("/api/license/list") { list = r.licenses ?? [] }
        if let h: HwidResponse = try? await state.api.request("/api/license/hwid") { hwid = h.hwid ?? "" }
    }
    private func post(_ p: String, _ b: [String: Any]) {
        Task {
            do { let r: OkResponse = try await state.api.request(p, method: "POST", body: b); if r.ok == false { nav.show(r.error ?? L("失敗"), "error") } else { nav.show(L("完成"), "success") } }
            catch { nav.show(error.localizedDescription, "error") }
            await load()
        }
    }
}
struct IssueLicenseSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @Environment(\.dismiss) var dismiss
    let reload: () async -> Void
    @State private var tenant = "tenant_001"
    @State private var tier = "pro"
    @State private var days = "30"
    @State private var issued: String?
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("發行授權")) { dismiss() }
            VStack(alignment: .leading, spacing: 10) {
                Text(L("租戶 ID")).font(WF.sans(12, .semibold)).foregroundColor(Theme.text2)
                TextField("tenant_001", text: $tenant).noAutoCap().inputWarm()
                Text(L("方案")).font(WF.sans(12, .semibold)).foregroundColor(Theme.text2)
                Picker("", selection: $tier) { Text("free").tag("free"); Text("pro").tag("pro"); Text("enterprise").tag("enterprise") }.pickerStyle(.segmented)
                Text(L("天數")).font(WF.sans(12, .semibold)).foregroundColor(Theme.text2)
                TextField("30", text: $days).keyboardType(.numberPad).inputWarm()
                Button(L("發行授權碼")) { issue() }.buttonStyle(WarmButtonStyle(padV: 12, full: true))
                if let issued {
                    Text(issued).font(WF.mono(12)).foregroundColor(Theme.text).textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }.padding(20)
            Spacer()
        }.background(Theme.surface.ignoresSafeArea()).presentationDetents([.medium, .large])
    }
    private func issue() {
        Task {
            do {
                let r: IssueResponse = try await state.api.request("/api/license/issue", method: "POST", body: ["tenant_id": tenant, "tier": tier, "duration_days": Int(days) ?? 30])
                if let k = r.key { issued = k; nav.show(L("已發行"), "success"); await reload() } else { nav.show(r.error ?? r.detail ?? L("失敗"), "error") }
            } catch { nav.show(error.localizedDescription, "error") }
        }
    }
}

// MARK: - 使用者管理（admin/owner）
struct UsersPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @State private var users: [DashUser] = []
    @State private var showAdd = false
    @State private var resetFor: DashUser?
    @State private var deleteFor: DashUser?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { PageTitle(L("使用者管理")); Spacer(); Button("+ " + L("新增")) { showAdd = true }.buttonStyle(WarmButtonStyle(padV: 8, padH: 14, size: 13)) }
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach([L("帳號"), "Email", L("角色"), L("狀態"), L("註冊時間"), L("最後登入"), L("操作")], id: \.self) { h in
                                Text(h).font(WF.sans(11, .bold)).foregroundColor(Theme.text2).frame(width: h == L("操作") ? 250 : (h == "Email" ? 160 : 110), alignment: .leading)
                            }
                        }.padding(.horizontal, 12).padding(.vertical, 10).background(Theme.surface2)
                        ForEach(users) { u in
                            HStack(spacing: 0) {
                                Text(u.username).font(WF.sans(13, .semibold)).foregroundColor(Theme.text).frame(width: 110, alignment: .leading).lineLimit(1)
                                Text((u.email ?? "—") + (u.email_verified == true ? " ✓" : "")).font(WF.sans(12)).foregroundColor(Theme.text2).frame(width: 160, alignment: .leading).lineLimit(1)
                                Menu {
                                    ForEach(["admin", "operator", "viewer"], id: \.self) { r in Button(r) { patch(u, "/role", ["role": r]) } }
                                } label: { Text(u.role ?? "—").font(WF.sans(12)).foregroundColor(Theme.primary) }.frame(width: 110, alignment: .leading)
                                Text(u.status == "suspended" ? L("已停權") : L("正常")).font(WF.sans(12)).foregroundColor(u.status == "suspended" ? Theme.tagError : Theme.success).frame(width: 110, alignment: .leading)
                                Text(u.created_at.map { Fmt.isoShort($0) } ?? "—").font(WF.mono(11)).foregroundColor(Theme.text2).frame(width: 110, alignment: .leading)
                                Text(u.last_login.map { Fmt.isoShort($0) } ?? "—").font(WF.mono(11)).foregroundColor(Theme.text2).frame(width: 110, alignment: .leading)
                                HStack(spacing: 6) {
                                    Button(u.status == "suspended" ? L("復權") : L("停權")) { patch(u, "/status", ["status": u.status == "suspended" ? "active" : "suspended"]) }.buttonStyle(SoftButtonStyle(padV: 5, padH: 8, size: 11))
                                    Button(L("重設密碼")) { resetFor = u }.buttonStyle(SoftButtonStyle(padV: 5, padH: 8, size: 11))
                                    Button(L("刪除")) { deleteFor = u }.buttonStyle(SoftButtonStyle(padV: 5, padH: 8, size: 11, bg: Color(hex: 0xb5341a, alpha: 0.1), fg: Theme.tagError))
                                }.frame(width: 250, alignment: .leading)
                            }.padding(.horizontal, 12).padding(.vertical, 10)
                            Divider().overlay(Theme.border)
                        }
                    }
                }.card(pad: 0)
                if users.isEmpty { EmptyState(icon: "👥", title: L("尚無使用者"), subtitle: "") }
            }.pageBody()
        }
        .background(Theme.bg.ignoresSafeArea())
        .task { await load() }
        .sheet(isPresented: $showAdd) { AddUserSheet { await load() } }
        .sheet(item: $resetFor) { u in ResetPasswordSheet(user: u) }
        .confirmationDialog(L("確定要刪除此使用者？"), isPresented: Binding(get: { deleteFor != nil }, set: { if !$0 { deleteFor = nil } }), titleVisibility: .visible) {
            Button(L("刪除"), role: .destructive) {
                if let u = deleteFor { Task { do { let _: OkResponse = try await state.api.request("/api/users/\(u.username)", method: "DELETE"); nav.show(L("已刪除"), "success") } catch { nav.show(error.localizedDescription, "error") }; await load() } }
                deleteFor = nil
            }
        }
    }
    private func load() async { if let r: UsersList = try? await state.api.request("/api/users/list") { users = r.users ?? [] } }
    private func patch(_ u: DashUser, _ suffix: String, _ b: [String: Any]) {
        Task {
            do { let _: OkResponse = try await state.api.request("/api/users/\(u.username)\(suffix)", method: "POST", body: b); nav.show(L("已更新"), "success") }
            catch { nav.show(error.localizedDescription, "error") }
            await load()
        }
    }
}
struct AddUserSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @Environment(\.dismiss) var dismiss
    let reload: () async -> Void
    @State private var name = ""
    @State private var pw = ""
    @State private var role = "operator"
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("新增使用者")) { dismiss() }
            VStack(alignment: .leading, spacing: 10) {
                Text(L("使用者名稱")).font(WF.sans(12, .semibold)).foregroundColor(Theme.text2)
                TextField(L("使用者名稱"), text: $name).noAutoCap().inputWarm()
                Text(L("密碼")).font(WF.sans(12, .semibold)).foregroundColor(Theme.text2)
                SecureField(L("密碼"), text: $pw).inputWarm()
                Text(L("角色")).font(WF.sans(12, .semibold)).foregroundColor(Theme.text2)
                Picker("", selection: $role) { Text("admin").tag("admin"); Text("operator").tag("operator"); Text("viewer").tag("viewer") }.pickerStyle(.segmented)
                Button(L("新增")) {
                    Task {
                        do { let _: OkResponse = try await state.api.request("/api/users/create", method: "POST", body: ["username": name, "password": pw, "role": role]); nav.show(L("已新增"), "success"); await reload(); dismiss() }
                        catch { nav.show(error.localizedDescription, "error") }
                    }
                }.buttonStyle(WarmButtonStyle(padV: 12, full: true)).disabled(name.isEmpty || pw.isEmpty)
            }.padding(20)
            Spacer()
        }.background(Theme.surface.ignoresSafeArea()).presentationDetents([.medium])
    }
}
struct ResetPasswordSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @Environment(\.dismiss) var dismiss
    let user: DashUser
    @State private var pw = ""
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("重設密碼") + " · " + user.username) { dismiss() }
            VStack(alignment: .leading, spacing: 10) {
                Text(L("新密碼") + "（≥8）").font(WF.sans(12, .semibold)).foregroundColor(Theme.text2)
                SecureField(L("至少 8 碼"), text: $pw).inputWarm()
                Button(L("確認重設")) {
                    Task {
                        do { let _: OkResponse = try await state.api.request("/api/users/\(user.username)/reset-password", method: "POST", body: ["new_password": pw]); nav.show(L("密碼已重設"), "success"); dismiss() }
                        catch { nav.show(error.localizedDescription, "error") }
                    }
                }.buttonStyle(WarmButtonStyle(padV: 12, full: true)).disabled(pw.count < 8)
            }.padding(20)
            Spacer()
        }.background(Theme.surface.ignoresSafeArea()).presentationDetents([.medium])
    }
}

// MARK: - 管理後台（internal）
struct AdminPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @State private var tab = 0
    @State private var stats: AdminStats?
    @State private var listings: [AdminListing] = []
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle("🔧 " + L("管理後台"))
                HStack(spacing: 8) {
                    FilterPill(label: "📊 " + L("平台總覽"), active: tab == 0) { tab = 0 }
                    FilterPill(label: "📋 " + L("內容審核"), active: tab == 1) { tab = 1 }
                }
                if tab == 0 {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        stat(L("總用戶"), "\(stats?.total_users ?? 0)", Theme.text)
                        stat(L("商品數"), "\(stats?.total_listings ?? 0)", Theme.primary)
                        stat(L("訂單數"), "\(stats?.total_orders ?? 0)", Color(hex: 0x6b8e5a))
                        stat(L("總營收"), "$" + Fmt.num(stats?.total_revenue ?? 0), Color(hex: 0xb89968))
                        stat(L("授權數"), "\(stats?.total_licenses ?? 0)", Theme.primaryHover)
                    }
                } else {
                    if listings.isEmpty { EmptyState(icon: "📋", title: L("尚無待審商品"), subtitle: "") }
                    ForEach(listings) { l in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(l.type == "agent" ? "🤖" : "📋")
                                Text(l.name ?? "").font(WF.sans(14, .bold)).foregroundColor(Theme.text)
                                Spacer()
                                Chip(l.status == "approved" ? L("已核准") : (l.status == "rejected" ? L("已駁回") : L("待審核")), l.status == "approved" ? .success : (l.status == "rejected" ? .danger : .warn))
                            }
                            if let d = l.description, !d.isEmpty { Text(d).font(WF.sans(12)).foregroundColor(Theme.text2).lineLimit(3) }
                            HStack {
                                Text(price(l)).font(WF.sans(12, .semibold)).foregroundColor(Theme.text2)
                                if let s = l.seller_name { Text("🏪 " + s).font(WF.sans(11)).foregroundColor(Theme.text3) }
                                Spacer()
                                Button("✓") { setStatus(l, "approved") }.buttonStyle(SoftButtonStyle(padV: 6, padH: 14, size: 14, bg: Color(hex: 0x6b8e5a), fg: .white))
                                Button("✗") { setStatus(l, "rejected") }.buttonStyle(SoftButtonStyle(padV: 6, padH: 14, size: 14, bg: Color(hex: 0xc45b4a), fg: .white))
                            }
                        }.card()
                    }
                }
            }.pageBody()
        }
        .background(Theme.bg.ignoresSafeArea())
        .task { await load() }
    }
    private func price(_ l: AdminListing) -> String {
        if let m = l.pricing?.per_month, m > 0 { return "$\(Fmt.num(m))/" + L("月") }
        if let o = l.pricing?.one_time, o > 0 { return "$\(Fmt.num(o))" }
        return L("免費")
    }
    private func stat(_ label: String, _ v: String, _ c: Color) -> some View {
        VStack(spacing: 6) {
            Text(v).font(WF.serif(32, .bold)).foregroundColor(c).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(WF.sans(12)).foregroundColor(Theme.text2)
        }.frame(maxWidth: .infinity).card()
    }
    private func load() async {
        if let s: AdminStats = try? await state.api.request("/api/admin/stats") { stats = s }
        if let l: AdminListings = try? await state.api.request("/api/admin/listings") { listings = l.listings ?? [] }
    }
    private func setStatus(_ l: AdminListing, _ s: String) {
        Task {
            do { let _: OkResponse = try await state.api.request("/api/admin/listings/status", method: "POST", body: ["listing_id": l.id, "status": s]); nav.show(L("已更新"), "success") }
            catch { nav.show(error.localizedDescription, "error") }
            await load()
        }
    }
}

// MARK: - 公司（網頁 CompanyPage；此版以公司基本資訊＋員工名單呈現）
struct CompanyPage: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageTitle(L("公司"))
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel(L("租戶"))
                    Text(state.tenant.isEmpty ? "—" : state.tenant).font(WF.sans(14, .semibold)).foregroundColor(Theme.text)
                    MonoLabel(L("環境")).padding(.top, 6)
                    Text(state.env.isEmpty ? "—" : state.env).font(WF.sans(14)).foregroundColor(Theme.text)
                }.frame(maxWidth: .infinity, alignment: .leading).card()
                MonoLabel(L("員工"))
                VStack(spacing: 0) {
                    ForEach(Array(state.sortedAgents.enumerated()), id: \.element.id) { i, a in
                        AgentRowView(agent: a, showButtons: false)
                        if i < state.sortedAgents.count - 1 { Divider().overlay(Theme.border) }
                    }
                }.card(pad: 0)
            }.pageBody()
        }.background(Theme.bg.ignoresSafeArea())
    }
}
