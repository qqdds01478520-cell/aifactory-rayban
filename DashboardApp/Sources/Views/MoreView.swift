import SwiftUI
import AVKit

struct MoreView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var l10n: L10n
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if state.health?.isInternal ?? true {
                        NavigationLink { ProductsView() } label: { Label(L("more.products"), systemImage: "film.stack") }
                    }
                    NavigationLink { BoardView() } label: { Label(L("more.board"), systemImage: "rectangle.split.3x1") }
                    NavigationLink { DiscordView() } label: { Label(L("more.discord"), systemImage: "message") }
                    NavigationLink { KnowledgeView() } label: { Label(L("more.knowledge"), systemImage: "books.vertical") }
                }.listRowBackground(Theme.surface)
                if state.isAdmin {
                    Section {
                        NavigationLink { BackupView() } label: { Label(L("more.backup"), systemImage: "externaldrive.badge.timemachine") }
                        NavigationLink { AuditView() } label: { Label(L("more.audit"), systemImage: "doc.text.magnifyingglass") }
                        NavigationLink { UsersView() } label: { Label(L("more.users"), systemImage: "person.badge.key") }
                        NavigationLink { StoreAdminView() } label: { Label(L("more.store"), systemImage: "storefront") }
                    }.listRowBackground(Theme.surface)
                }
                Section {
                    NavigationLink { SettingsView() } label: { Label(L("more.settings"), systemImage: "gearshape") }
                }.listRowBackground(Theme.surface)
                Section {
                    HStack { Text(L("more.account")); Spacer(); Text("\(state.username) · \(state.role)").foregroundColor(Theme.muted) }
                    Button(role: .destructive) { state.logout() } label: { Label(L("more.logout"), systemImage: "rectangle.portrait.and.arrow.right") }
                }.listRowBackground(Theme.surface)
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).screenBackground()
            .navigationTitle(L("tab.more"))
        }
    }
}

// MARK: - 通用載入器
struct Loader<T: Decodable, Content: View>: View {
    @EnvironmentObject var state: AppState
    let path: String
    var cacheKey: String? = nil
    var timeout: TimeInterval = 25
    @ViewBuilder var content: (T, @escaping () async -> Void) -> Content
    @State private var value: T?
    @State private var err: String?

    var body: some View {
        Group {
            if let v = value { content(v, load) }
            else if let err {
                VStack(spacing: 10) {
                    Text(err).font(.footnote).foregroundColor(Theme.danger).multilineTextAlignment(.center)
                    Button(L("common.retry")) { Task { await load() } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task { await load() }
    }
    private func load() async {
        do {
            let v: T = try await state.api.request(path, timeout: timeout)
            value = v; err = nil
        } catch { if value == nil { err = error.localizedDescription } }
    }
}

// MARK: - 影片成品區（站→日期→影片；AVPlayer 滿版，播完不再有任何蓋版）
struct ProductsView: View {
    var body: some View {
        Loader(path: "/api/products/tree") { (tree: ProductsTree, reload) in
            List {
                ForEach(tree.stations) { st in
                    NavigationLink { StationView(station: st, base: tree.media_base ?? "/products-media/") } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(st.name).font(.body.weight(.medium)).foregroundColor(Theme.text)
                                Text("\(st.video_count ?? 0) \(L("prod.videos")) · \(st.date_count ?? 0) \(L("prod.dates"))").font(.caption).foregroundColor(Theme.muted)
                            }
                            Spacer()
                            Text(st.latest ?? "").font(.caption2).foregroundColor(Theme.muted)
                        }
                    }.listRowBackground(Theme.surface)
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).screenBackground()
            .refreshable { await reload() }
        }
        .navigationTitle(L("more.products"))
    }
}
struct StationView: View {
    @EnvironmentObject var state: AppState
    let station: ProductStation
    let base: String
    var body: some View {
        List {
            ForEach(station.dates) { d in
                Section {
                    ForEach(d.videos) { v in
                        if let url = state.api.mediaURL(v.rel, base: base) {
                            NavigationLink { VideoScreen(url: url, title: d.title ?? v.name) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: v.name.contains("short") ? "rectangle.portrait" : "play.rectangle").foregroundColor(Theme.primary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(v.name).font(.footnote).foregroundColor(Theme.text).lineLimit(1)
                                        Text(Fmt.bytes(v.size ?? 0)).font(.caption2).foregroundColor(Theme.muted)
                                    }
                                }
                            }
                        }
                    }
                    if !d.images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(d.images) { im in
                                    if let url = state.api.mediaURL(im.rel, base: base) {
                                        NavigationLink { ImageScreen(url: url) } label: {
                                            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Theme.surface2 }
                                                .frame(width: 128, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                }
                            }
                        }.listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.date)
                        if let t = d.title, !t.isEmpty { Text(t).font(.caption).foregroundColor(Theme.text).textCase(nil) }
                    }
                }.listRowBackground(Theme.surface)
            }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden).screenBackground()
        .navigationTitle(station.name).navigationBarTitleDisplayMode(.inline)
    }
}
struct VideoScreen: View {
    let url: URL
    let title: String
    @State private var player: AVPlayer?
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            let p = AVPlayer(url: url)
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            player = p; p.play()
        }
        .onDisappear { player?.pause(); player = nil }
    }
}
struct ImageScreen: View {
    let url: URL
    @State private var scale: CGFloat = 1
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                .scaleEffect(scale)
                .gesture(MagnificationGesture().onChanged { scale = max(1, $0) }.onEnded { _ in withAnimation { scale = 1 } })
        }
        .ignoresSafeArea()
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

// MARK: - 看板
struct BoardView: View {
    var body: some View {
        Loader(path: "/api/board/projects") { (p: BoardProjects, reload) in
            List {
                ForEach(p.projects ?? []) { pr in
                    NavigationLink { BoardTasksView(project: pr) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(pr.name ?? pr.id).font(.body.weight(.medium)).foregroundColor(Theme.text); Spacer(); Pill(text: pr.status ?? "") }
                            if let d = pr.description, !d.isEmpty { Text(d).font(.caption).foregroundColor(Theme.muted).lineLimit(2) }
                            ProgressView(value: min(1, (pr.progress ?? 0) / 100)).tint(Theme.primary)
                            if let c = pr.task_counts {
                                Text(["todo", "doing", "blocked", "review", "done"].compactMap { k in c[k].map { "\(k) \($0)" } }.joined(separator: " · ")).font(.caption2).foregroundColor(Theme.muted)
                            }
                        }
                    }.listRowBackground(Theme.surface)
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).screenBackground()
            .overlay { if (p.projects ?? []).isEmpty { EmptyHint(text: L("common.none")) } }
            .refreshable { await reload() }
        }.navigationTitle(L("more.board"))
    }
}
struct BoardTasksView: View {
    let project: BoardProject
    var body: some View {
        Loader(path: "/api/board/tasks?project_id=\(project.id)") { (t: BoardTasks, reload) in
            List {
                ForEach(t.tasks ?? []) { task in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(task.title ?? "").font(.subheadline.weight(.medium)).foregroundColor(Theme.text); Spacer(); Pill(text: task.status ?? "", color: task.status == "done" ? Theme.success : (task.status == "blocked" ? Theme.danger : Theme.accent)) }
                        HStack { Text(task.assignee ?? "").font(.caption).foregroundColor(Theme.muted); Spacer(); Text("\(Int(task.percent ?? 0))%").font(.caption).foregroundColor(Theme.muted) }
                        if let u = task.last_update { Text("\(u.author ?? ""): \(u.content ?? "")").font(.caption2).foregroundColor(Theme.muted).lineLimit(2) }
                    }.listRowBackground(Theme.surface)
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).screenBackground()
            .refreshable { await reload() }
        }.navigationTitle(project.name ?? L("board.tasks")).navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Discord
struct DiscordView: View {
    var body: some View {
        Loader(path: "/api/discord/channels") { (c: DiscordChannels, _) in
            List {
                ForEach(c.channels ?? []) { ch in
                    NavigationLink { DiscordChannelView(channel: ch) } label: { Label(ch.name ?? ch.id, systemImage: "number") }.listRowBackground(Theme.surface)
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).screenBackground()
            .overlay { if (c.channels ?? []).isEmpty { EmptyHint(text: L("common.none")) } }
        }.navigationTitle(L("more.discord"))
    }
}
struct DiscordChannelView: View {
    @EnvironmentObject var state: AppState
    let channel: DiscordChannel
    @State private var text = ""
    @State private var err: String?
    var body: some View {
        Loader(path: "/api/discord/messages/\(channel.id)?limit=50") { (m: DiscordMessages, reload) in
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(m.messages ?? []) { msg in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Text(msg.author?.global_name ?? msg.author?.username ?? "").font(.caption.weight(.semibold)).foregroundColor(Theme.accent); Spacer(); Text(Fmt.iso(msg.timestamp ?? "")).font(.caption2).foregroundColor(Theme.muted) }
                                Text(msg.content ?? "").font(.subheadline).foregroundColor(Theme.text).textSelection(.enabled)
                            }.card(pad: 10)
                        }
                    }.padding(12)
                }.refreshable { await reload() }
                HStack {
                    TextField(L("dc.send"), text: $text, axis: .vertical).lineLimit(1...4).padding(10).background(Theme.surface2).cornerRadius(12).foregroundColor(Theme.text)
                    Button {
                        let t = text; text = ""
                        Task {
                            do { let _: OkResponse = try await state.api.request("/api/discord/send", method: "POST", body: ["channel_id": channel.id, "content": t]); Haptic.success(); await reload() }
                            catch { err = error.localizedDescription }
                        }
                    } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 28)) }.disabled(text.isEmpty)
                }.padding(10).background(Theme.bg)
                if let err { Text(err).font(.caption2).foregroundColor(Theme.danger) }
            }.screenBackground()
        }.navigationTitle(channel.name ?? "").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 知識庫
struct KnowledgeView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    var body: some View {
        Loader(path: "/api/knowledge/files") { (k: KnowledgeFiles, reload) in
            let files = (k.files ?? []).filter { $0.type != "folder" && !$0.name.hasPrefix("_") && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
            List {
                ForEach(files) { f in
                    NavigationLink { KnowledgeReadView(file: f) } label: {
                        HStack { Text(f.name).font(.footnote).foregroundColor(Theme.text).lineLimit(1); Spacer(); Text(f.agent ?? "").font(.caption2).foregroundColor(Theme.muted); Text(Fmt.bytes(f.size ?? 0)).font(.caption2).foregroundColor(Theme.muted) }
                    }.listRowBackground(Theme.surface)
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).screenBackground()
            .searchable(text: $query)
            .refreshable { await reload() }
        }.navigationTitle(L("more.knowledge"))
    }
}
struct KnowledgeReadView: View {
    @EnvironmentObject var state: AppState
    let file: KnowledgeFile
    @State private var text = ""
    var body: some View {
        ScrollView { Text(text).font(.system(.footnote, design: .monospaced)).foregroundColor(Theme.text).frame(maxWidth: .infinity, alignment: .leading).padding(14).textSelection(.enabled) }
            .screenBackground().navigationTitle(file.name).navigationBarTitleDisplayMode(.inline)
            .task {
                let q = "agent=\(file.agent ?? "")&path=\((file.path ?? file.name).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
                if let d = try? await state.api.requestData("/api/knowledge/read?\(q)") {
                    if let r = try? JSONDecoder().decode(KnowledgeRead.self, from: d), let c = r.content { text = c }
                    else { text = String(data: d, encoding: .utf8) ?? "" }
                } else { text = L("common.error") }
            }
    }
}

// MARK: - 備份
struct BackupView: View {
    @EnvironmentObject var state: AppState
    @State private var status: BackupStatus?
    @State private var msg: String?
    @State private var confirm: (String, () -> Void)?
    @State private var showConfirm = false
    var body: some View {
        Loader(path: "/api/backup/list") { (b: BackupList, reload) in
            List {
                Section {
                    HStack { Text(L("bk.status")); Spacer(); Text(status.map { "\(($0.running ?? false) ? "ON" : "OFF") · \(L("bk.every")) \(Int($0.interval_hours ?? 0))\(L("bk.hours")) · \($0.total_backups ?? 0) \(L("bk.total"))" } ?? "…").font(.caption).foregroundColor(Theme.muted) }
                    Button { Task { do { let _: OkResponse = try await state.api.request("/api/backup/create", method: "POST", body: ["label": "iphone"], timeout: 300); Haptic.success(); await reload() } catch { msg = error.localizedDescription } } } label: { Label(L("bk.create"), systemImage: "plus") }
                    if let msg { Text(msg).font(.caption).foregroundColor(Theme.danger) }
                }.listRowBackground(Theme.surface)
                Section {
                    ForEach(b.backups ?? []) { bk in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(bk.label ?? "").font(.subheadline.weight(.medium)).foregroundColor(Theme.text); Spacer(); Text(bk.timestamp ?? "").font(.caption).foregroundColor(Theme.muted) }
                            Text("\(bk.agents ?? 0) agents · \(bk.files ?? 0) files · \(String(format: "%.0f", bk.size_mb ?? 0)) MB").font(.caption2).foregroundColor(Theme.muted)
                        }
                        .swipeActions {
                            Button(role: .destructive) { confirm = (L("bk.confirmdelete"), { Task { do { let _: OkResponse = try await state.api.request("/api/backup/delete", method: "POST", body: ["timestamp": bk.timestamp ?? ""]); await reload() } catch { msg = error.localizedDescription } } }); showConfirm = true } label: { Label(L("bk.delete"), systemImage: "trash") }
                            Button { confirm = (L("bk.confirmrestore"), { Task { do { let _: OkResponse = try await state.api.request("/api/backup/restore", method: "POST", body: ["timestamp": bk.timestamp ?? ""], timeout: 300); Haptic.success() } catch { msg = error.localizedDescription } } }); showConfirm = true } label: { Label(L("bk.restore"), systemImage: "arrow.counterclockwise") }.tint(Theme.warning)
                        }
                        .listRowBackground(Theme.surface)
                    }
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).screenBackground()
            .refreshable { await reload() }
        }
        .navigationTitle(L("more.backup"))
        .task { status = try? await state.api.request("/api/backup/status") }
        .confirmationDialog(confirm?.0 ?? "", isPresented: $showConfirm, titleVisibility: .visible) {
            Button(L("common.confirm"), role: .destructive) { confirm?.1() }
        }
    }
}

// MARK: - 審計
struct AuditView: View {
    @State private var filter = ""
    var body: some View {
        Loader(path: "/api/audit/list?limit=300") { (a: AuditList, reload) in
            let evs = (a.events ?? []).filter { filter.isEmpty || ($0.actor ?? "").localizedCaseInsensitiveContains(filter) || ($0.action ?? "").localizedCaseInsensitiveContains(filter) }
            List {
                ForEach(evs) { e in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(e.action ?? "").font(.footnote.weight(.semibold)).foregroundColor(Theme.text); Spacer(); Pill(text: e.result ?? "", color: e.result == "ok" ? Theme.success : Theme.danger) }
                        HStack { Text(e.actor ?? "").font(.caption).foregroundColor(Theme.accent); Text(e.target ?? "").font(.caption).foregroundColor(Theme.muted).lineLimit(1); Spacer(); Text(Fmt.iso(e.ts ?? "")).font(.caption2).foregroundColor(Theme.muted) }
                    }.listRowBackground(Theme.surface)
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).screenBackground()
            .searchable(text: $filter, prompt: L("au.filter"))
            .refreshable { await reload() }
        }.navigationTitle(L("more.audit"))
    }
}

// MARK: - 管理員設定（用戶）
struct UsersView: View {
    @EnvironmentObject var state: AppState
    @State private var showCreate = false
    @State private var nu = ""; @State private var np = ""; @State private var nr = "user"
    @State private var msg: String?
    @State private var resetTarget: DashUser?
    @State private var resetPass = ""
    var body: some View {
        Loader(path: "/api/users/list") { (u: UsersList, reload) in
            List {
                if let msg { Text(msg).font(.caption).foregroundColor(Theme.danger) }
                ForEach(u.users ?? []) { user in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(user.username).font(.subheadline.weight(.medium)).foregroundColor(Theme.text); Pill(text: user.role ?? "", color: user.role == "admin" ? Theme.primary : Theme.accent); Spacer(); if user.status == "suspended" { Pill(text: L("us.suspend"), color: Theme.danger) } }
                        Text("last: \(Fmt.iso(user.last_login ?? ""))").font(.caption2).foregroundColor(Theme.muted)
                    }
                    .swipeActions {
                        if user.username != state.username {
                            Button(role: .destructive) { Task { do { let _: OkResponse = try await state.api.request("/api/users/\(user.username)", method: "DELETE"); await reload() } catch { msg = error.localizedDescription } } } label: { Label("Del", systemImage: "trash") }
                            Button { Task { do { let _: OkResponse = try await state.api.request("/api/users/\(user.username)/status", method: "POST", body: ["status": user.status == "suspended" ? "active" : "suspended"]); await reload() } catch { msg = error.localizedDescription } } } label: { Label(user.status == "suspended" ? L("us.activate") : L("us.suspend"), systemImage: "hand.raised") }.tint(Theme.warning)
                        }
                        Button { resetTarget = user } label: { Label(L("us.reset"), systemImage: "key") }.tint(Theme.accent)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).screenBackground()
            .refreshable { await reload() }
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button { showCreate = true } label: { Image(systemName: "person.badge.plus") } } }
            .alert(L("us.create"), isPresented: $showCreate) {
                TextField(L("login.user"), text: $nu).textInputAutocapitalization(.never)
                SecureField(L("login.pass"), text: $np)
                Button(L("common.cancel"), role: .cancel) {}
                Button(L("chat.create")) { Task { do { let _: OkResponse = try await state.api.request("/api/users/create", method: "POST", body: ["username": nu, "password": np, "role": nr]); nu = ""; np = ""; await reload() } catch { msg = error.localizedDescription } } }
            }
            .alert(L("us.reset"), isPresented: Binding(get: { resetTarget != nil }, set: { if !$0 { resetTarget = nil } })) {
                SecureField(L("us.newpass"), text: $resetPass)
                Button(L("common.cancel"), role: .cancel) {}
                Button(L("common.ok")) { if let t = resetTarget { Task { do { let _: OkResponse = try await state.api.request("/api/users/\(t.username)/reset-password", method: "POST", body: ["new_password": resetPass]); resetPass = ""; Haptic.success() } catch { msg = error.localizedDescription } } } }
            }
        }.navigationTitle(L("more.users"))
    }
}

// MARK: - 市集授權後台（訂單＋買家）
struct StoreAdminView: View {
    var body: some View {
        List {
            Section("Orders") {
                Loader(path: "/api/store/orders") { (o: StoreOrders, _) in
                    ForEach(o.orders ?? [], id: \.identity) { od in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text(od.product ?? od.identity).font(.footnote.weight(.medium)).foregroundColor(Theme.text); Spacer(); Pill(text: od.status ?? "") }
                            Text("\(od.buyer ?? "") · \(Fmt.iso(od.created_at ?? ""))").font(.caption2).foregroundColor(Theme.muted)
                        }
                    }
                    if (o.orders ?? []).isEmpty { Text(L("common.none")).font(.caption).foregroundColor(Theme.muted) }
                }
            }.listRowBackground(Theme.surface)
            Section("Buyers") {
                Loader(path: "/api/store/op/buyers") { (b: StoreBuyers, _) in
                    ForEach(b.buyers ?? []) { by in
                        HStack { Text(by.email ?? by.id).font(.footnote).foregroundColor(Theme.text); Spacer(); Pill(text: by.status ?? "") }
                    }
                    if (b.buyers ?? []).isEmpty { Text(L("common.none")).font(.caption).foregroundColor(Theme.muted) }
                }
            }.listRowBackground(Theme.surface)
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden).screenBackground()
        .navigationTitle(L("more.store"))
    }
}

// MARK: - 設定
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var l10n: L10n
    @State private var cacheSize = DiskCache.sizeBytes
    var body: some View {
        List {
            Section {
                Picker(L("more.lang"), selection: $l10n.lang) { Text("繁體中文").tag("zh"); Text("English").tag("en") }
                Toggle(L("more.faceid"), isOn: $state.faceIDEnabled)
                Toggle(L("more.haptics"), isOn: $state.hapticsEnabled)
                Toggle(L("more.bgrefresh"), isOn: $state.bgRefreshEnabled).onChange(of: state.bgRefreshEnabled) { on in if on { state.scheduleBackgroundRefresh() } }
                Picker(L("more.dispatch"), selection: $state.dispatchAgent) { ForEach(state.sortedAgents) { a in Text(a.name).tag(a.name) } }
            }.listRowBackground(Theme.surface)
            Section {
                HStack { Text(L("more.push")); Spacer(); Text(state.pushStatus).foregroundColor(Theme.muted) }
                HStack { Text(L("more.server")); Spacer(); Text(state.baseString).font(.caption).foregroundColor(Theme.muted).lineLimit(1) }
                HStack { Text(L("more.version")); Spacer(); Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))").foregroundColor(Theme.muted) }
                HStack { Text(L("more.cache")); Spacer(); Text(Fmt.bytes(cacheSize)).foregroundColor(Theme.muted) }
                if state.lastBackgroundRefresh > 0 { HStack { Text(L("more.bgrefresh")); Spacer(); Text(Fmt.when(state.lastBackgroundRefresh)).foregroundColor(Theme.muted) } }
                Button(L("more.cache.clear")) { DiskCache.clear(); cacheSize = 0; Haptic.medium() }
            }.listRowBackground(Theme.surface)
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden).screenBackground()
        .navigationTitle(L("more.settings"))
    }
}
