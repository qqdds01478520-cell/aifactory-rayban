import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVKit

// 群聊＝網頁 GroupChatPage（LINE 兩層）：列表（聊天▾／👤／＋／🔍搜尋／混排列）→ 聊天室（‹ 名稱 n人／修改群組成員／訊息／輸入列）
// ＋ 群組資訊（改名／成員編輯／刪除）＋ 新建群聊 ＋ 個人（DM）選擇器
enum ChatPal {
    static let brand = Color(hex: 0xc6552f)
    static let red = Color(hex: 0xe53935)
    static let redbg = Theme.dyn(0xfbe4e4, 0x3a201e)
    static let pendingRow = Theme.dyn(0xf9eee9, 0x2c211c)
    static let roombg = Theme.dyn(0xece3d5, 0x1c1814)
    static let field = Theme.dyn(0xeae1d3, 0x2a251d)
    static let card = Theme.surface
    static let mut = Color(hex: 0x8c8478)
    static let line = Theme.dyn(0xeae1d4, 0x2a251d)
    static let palette: [UInt32] = [0xe7854a, 0x7c5cff, 0xe0a106, 0x3ba55d, 0x4a90d9, 0x9b59b6, 0xe07040, 0x3d8ec4]
    static func color(_ name: String) -> Color {
        if name == "COO" { return Color(hex: 0x8b5cf6) }
        if name == "DemoUser" { return Color(hex: 0xe91e63) }
        if name == "Chairman" || name == "admin" { return brand }
        let h = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hex: palette[h % palette.count])
    }
}
struct ChatCircle: View {
    let name: String
    var size: CGFloat = 48
    var dot: Bool = false
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle().fill(ChatPal.color(name)).frame(width: size, height: size)
                .overlay(Text(String((name.isEmpty ? "?" : name).prefix(1)).uppercased()).font(WF.sans((size * 0.38).rounded(), .heavy)).foregroundColor(.white))
            if dot { Circle().fill(ChatPal.red).frame(width: 14, height: 14).overlay(Circle().stroke(Theme.bg, lineWidth: 2.5)).offset(x: 1, y: -1) }
        }.frame(width: size, height: size)
    }
}
func isDM(_ g: ChatGroup) -> Bool { g.name.hasPrefix("DM: ") }
func dispName(_ g: ChatGroup) -> String { isDM(g) ? String(g.name.dropFirst(4)) : g.name }

struct ChatView: View {
    enum Screen { case list, room, info, create }
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @EnvironmentObject var l10n: L10n
    @State private var screen: Screen = .list
    @State private var selected: ChatGroup?
    @State private var search = ""
    @State private var mode = 0   // 0 全部 1 群組 2 個人
    @State private var showDm = false
    @State private var poller: Task<Void, Never>?

    var list: [ChatGroup] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return state.groups.filter { g in
            (q.isEmpty || dispName(g).lowercased().contains(q)) && (mode == 0 || (mode == 1 && !isDM(g)) || (mode == 2 && isDM(g)))
        }.sorted { ($0.last_ts ?? 0, $0.last_msg_id ?? 0) > ($1.last_ts ?? 0, $1.last_msg_id ?? 0) }
    }
    var current: ChatGroup? { selected.flatMap { s in state.groups.first { $0.id == s.id } } ?? selected }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch screen {
            case .list: listPage
            case .room:
                if let g = current { ChatRoomView(group: g, onBack: { go(.list) }, onInfo: { go(.info) }).transition(.move(edge: .trailing)) }
            case .info:
                if let g = current { GroupInfoView(group: g, onBack: { go(.room) }, onDeleted: { selected = nil; go(.list) }).transition(.move(edge: .trailing)) }
            case .create:
                CreateGroupView(onBack: { go(.list) }, onCreated: { g in selected = g; go(.room) }).transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: screen)
        .sheet(isPresented: $showDm) { DmPickerSheet { name in showDm = false; openDm(name) } }
        .onAppear {
            nav.chatRoom = screen != .list
            poller?.cancel()
            poller = Task { while !Task.isCancelled { try? await Task.sleep(nanoseconds: 8_000_000_000); await state.refreshGroups() } }
        }
        .onDisappear { poller?.cancel(); nav.chatRoom = false }
    }
    private func go(_ s: Screen) { screen = s; nav.chatRoom = s != .list }

    // MARK: 第一頁：列表
    private var listPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Menu {
                    Button(L("全部")) { mode = 0 }; Button(L("群組")) { mode = 1 }; Button(L("個人")) { mode = 2 }
                } label: {
                    Text((mode == 0 ? L("聊天") : mode == 1 ? L("群組") : L("個人")) + " ▾").font(WF.sans(14, .heavy)).foregroundColor(.white)
                        .padding(.vertical, 7).padding(.horizontal, 14).background(ChatPal.brand).clipShape(Capsule())
                }
                Spacer()
                Button { showDm = true } label: { Text("👤").font(.system(size: 22)) }
                Button { go(.create) } label: { Text("＋").font(WF.sans(24, .medium)).foregroundColor(ChatPal.brand) }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            HStack(spacing: 8) {
                Text("🔍").font(.system(size: 14))
                TextField(L("搜尋對話、成員"), text: $search).font(WF.sans(14)).foregroundColor(Theme.text).noAutoCap()
            }
            .padding(.vertical, 9).padding(.horizontal, 14).background(ChatPal.field).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16).padding(.bottom, 6)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if list.isEmpty { EmptyState(icon: "🗨️", title: L("還沒有對話"), subtitle: L("按右上「＋」建群，或「👤」找員工單聊")) }
                    ForEach(list) { g in
                        Button { selected = g; go(.room) } label: { row(g) }.buttonStyle(.plain)
                    }
                }.padding(.bottom, 110)
            }
            .refreshable { await state.refreshGroups() }
        }
    }
    private func row(_ g: ChatGroup) -> some View {
        let dm = isDM(g)
        let pending = (g.pending_decisions ?? 0) > 0
        let unread = (g.last_msg_id ?? 0) > (state.readMarks[g.id] ?? 0)
        return HStack(spacing: 12) {
            ChatCircle(name: dispName(g), size: 48, dot: pending)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(dispName(g)).font(WF.sans(15.5, .heavy)).foregroundColor(Theme.text).lineLimit(1)
                    Text(dm ? "· " + L("個人") : "(\(g.member_count ?? g.members?.count ?? 0))").font(WF.sans(11, .semibold)).foregroundColor(ChatPal.mut)
                    Spacer()
                    Text(Fmt.hhmm(g.last_ts)).font(WF.sans(11.5)).foregroundColor(ChatPal.mut)
                }
                HStack(spacing: 6) {
                    Text(pending ? "🔴 " + L("待你決策") : ((g.last_sender.map { $0 + ": " } ?? "") + (g.last_preview ?? "")))
                        .font(WF.sans(13.5, pending ? .bold : .regular)).foregroundColor(pending ? ChatPal.red : ChatPal.mut).lineLimit(1)
                    Spacer()
                    if pending {
                        Text(L("待決策")).font(WF.sans(11, .heavy)).foregroundColor(.white).padding(.vertical, 3).padding(.horizontal, 8).background(ChatPal.red).clipShape(Capsule())
                    } else if unread { Circle().fill(ChatPal.brand).frame(width: 12, height: 12) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(pending ? ChatPal.pendingRow : Color.clear)
        .overlay(Rectangle().fill(ChatPal.line).frame(height: 1), alignment: .bottom)
        .contentShape(Rectangle())
    }

    private func openDm(_ agentName: String) {
        let dmName = "DM: " + agentName
        if let g = state.groups.first(where: { $0.name == dmName }) { selected = g; go(.room); return }
        Task {
            do {
                let r: OkResponse = try await state.api.request("/api/group-chat/groups", method: "POST",
                    body: ["name": dmName, "members": [agentName, state.username.isEmpty ? "Chairman" : state.username]])
                await state.refreshGroups()
                if let gid = r.group_id, let g = state.groups.first(where: { $0.id == gid }) { selected = g; go(.room); nav.show(L("已開啟與") + " \(agentName) " + L("的對話"), "success") }
                else if let g = state.groups.first(where: { $0.name == dmName }) { selected = g; go(.room) }
            } catch { nav.show(L("開啟對話失敗"), "error") }
        }
    }
}

// 個人（DM）選擇器
struct DmPickerSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    let pick: (String) -> Void
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("選擇要對話的 Agent")) { dismiss() }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(state.sortedAgents) { a in
                        Button { pick(a.name) } label: {
                            HStack(spacing: 12) {
                                ChatCircle(name: a.name, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.name).font(WF.sans(15, .bold)).foregroundColor(Theme.text)
                                    Text(a.isRunning ? L("運行中") : L("已停止")).font(WF.sans(11)).foregroundColor(a.isRunning ? Theme.success : Theme.text3)
                                }
                                Spacer()
                                Text("›").foregroundColor(Theme.text3)
                            }.padding(.horizontal, 20).padding(.vertical, 10)
                        }.buttonStyle(.plain)
                        Divider().overlay(ChatPal.line).padding(.leading, 72)
                    }
                }.padding(.bottom, 30)
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 聊天室
struct ChatRoomView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    let group: ChatGroup
    let onBack: () -> Void
    let onInfo: () -> Void
    @State private var messages: [ChatMessage] = []
    @State private var members: [String] = []
    @State private var text = ""
    @State private var sending = false
    @State private var uploading = false
    @State private var replyTo: ChatMessage?
    @State private var photo: PhotosPickerItem?
    @State private var stream: Task<Void, Never>?
    @State private var lastTs: Double = 0
    @State private var expanded: Set<Int> = []
    @State private var typing = false
    @State private var typingTask: Task<Void, Never>?
    @FocusState private var focused: Bool
    private var cacheKey: String { "msgs_\(group.id)" }
    private var dm: Bool { isDM(group) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty { Text(L("還沒有訊息，說點什麼吧")).font(WF.sans(13)).foregroundColor(ChatPal.mut).padding(.top, 40) }
                        ForEach(messages) { m in bubble(m).id(m.id) }
                        if typing {
                            HStack { Text(L("已輸入 Agent 終端機，請稍後…")).font(WF.sans(12)).foregroundColor(ChatPal.mut); Spacer() }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(.horizontal, 12).padding(.vertical, 10)
                }
                .background(ChatPal.roombg)
                .onChange(of: messages.count) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                .onTapGesture { focused = false }
            }
            composer
        }
        .background(Theme.bg.ignoresSafeArea())
        .task {
            if let c = DiskCache.load([ChatMessage].self, key: cacheKey) { messages = c; lastTs = c.last?.ts ?? 0 }
            await load(initial: true)
            await loadMembers()
            startStream()
        }
        .onDisappear { stream?.cancel(); state.markRead(group) }
        .onChange(of: photo) { item in if let item { upload(item) } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) { Text("‹").font(WF.sans(30, .medium)).foregroundColor(Theme.text).frame(width: 36, height: 36) }
            ChatCircle(name: dispName(group), size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(dispName(group)).font(WF.sans(16, .heavy)).foregroundColor(Theme.text).lineLimit(1)
                Text(dm ? L("個人") : "\(members.isEmpty ? (group.member_count ?? 0) : members.count) " + L("人")).font(WF.sans(11)).foregroundColor(ChatPal.mut)
            }
            Spacer()
            Button(action: onInfo) {
                Text(dm ? L("資訊") : L("修改群組成員")).font(WF.sans(12, .bold)).foregroundColor(Theme.text)
                    .padding(.vertical, 6).padding(.horizontal, 12).background(Theme.surface).clipShape(Capsule())
                    .overlay(Capsule().stroke(ChatPal.line, lineWidth: 1))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.bg)
        .overlay(Rectangle().fill(ChatPal.line).frame(height: 1), alignment: .bottom)
    }

    private func isMe(_ m: ChatMessage) -> Bool { m.sender == state.username || m.sender == "Chairman" || m.isHuman }

    // MARK: 氣泡
    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        if m.isPending { pendingCard(m) }
        else if (m.decision ?? 0) == 1, let st = m.decision_status, st != "pending" { resolvedCard(m, approved: st == "approved") }
        else if isMe(m) {
            HStack(alignment: .bottom) {
                Spacer(minLength: 50)
                VStack(alignment: .trailing, spacing: 4) {
                    replyStrip(m)
                    mediaView(m)
                    if let c = textOf(m) {
                        Text(c).font(WF.sans(14.5)).foregroundColor(.white).padding(.vertical, 9).padding(.horizontal, 13)
                            .background(ChatPal.brand)
                            .clipShape(BubbleShape(tl: 14, tr: 3, bl: 14, br: 14))
                            .textSelection(.enabled)
                    }
                    Text(L("老闆") + " · " + Fmt.hhmm(m.ts)).font(WF.sans(10.5)).foregroundColor(ChatPal.mut)
                }
            }.contextMenu { ctx(m) }
        } else {
            HStack(alignment: .top, spacing: 8) {
                ChatCircle(name: m.sender ?? "?", size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text((m.sender ?? "") + (m.msg_type == "agent" ? " · AI" : "")).font(WF.sans(12, .bold)).foregroundColor(ChatPal.mut)
                    replyStrip(m)
                    mediaView(m)
                    if let c = textOf(m) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.count > 180 && !expanded.contains(m.id) ? String(c.prefix(180)) + "…" : c)
                                .font(WF.sans(14.5)).foregroundColor(Theme.text).textSelection(.enabled)
                            if c.count > 180 {
                                Button(expanded.contains(m.id) ? L("收合") : L("展開")) { if expanded.contains(m.id) { expanded.remove(m.id) } else { expanded.insert(m.id) } }
                                    .font(WF.sans(12, .bold)).foregroundColor(ChatPal.brand)
                            }
                        }
                        .padding(.vertical, 9).padding(.horizontal, 13).background(ChatPal.card)
                        .clipShape(BubbleShape(tl: 3, tr: 14, bl: 14, br: 14))
                    }
                    Text(Fmt.hhmm(m.ts)).font(WF.sans(10.5)).foregroundColor(ChatPal.mut)
                }
                Spacer(minLength: 40)
            }.contextMenu { ctx(m) }
        }
    }
    private func textOf(_ m: ChatMessage) -> String? {
        guard let c = m.content, !c.isEmpty else { return nil }
        if m.media_url != nil && c.hasPrefix("[") && c.hasSuffix("]") { return nil }
        return c
    }
    @ViewBuilder private func replyStrip(_ m: ChatMessage) -> some View {
        if let r = m.reply_to, let orig = messages.first(where: { $0.id == r }) {
            Text("↩ \(orig.sender ?? ""): \((orig.content ?? "").prefix(40))").font(WF.sans(11)).foregroundColor(ChatPal.mut).lineLimit(1)
        }
    }
    @ViewBuilder private func mediaView(_ m: ChatMessage) -> some View {
        if let mu = m.media_url, let url = state.api.mediaURL(mu) {
            let low = mu.lowercased()
            if low.hasSuffix(".mp4") || low.hasSuffix(".mov") || low.hasSuffix(".webm") {
                InlineVideo(url: url).frame(width: 240, height: 160).clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .frame(maxWidth: 240, maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    @ViewBuilder private func ctx(_ m: ChatMessage) -> some View {
        Button { replyTo = m; focused = true } label: { Label(L("回覆"), systemImage: "arrowshape.turn.up.left") }
        Button { UIPasteboard.general.string = m.content } label: { Label(L("複製"), systemImage: "doc.on.doc") }
    }

    // 🔴 待你決策 卡（紅框 2px；⋯ → ✅ 標為已核可 / ✖ 標為已駁回）
    private func pendingCard(_ m: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🔴 " + L("待你決策")).font(WF.sans(11, .heavy)).foregroundColor(.white).padding(.vertical, 3).padding(.horizontal, 8).background(ChatPal.red).clipShape(Capsule())
                Text(m.sender ?? "").font(WF.sans(12, .bold)).foregroundColor(ChatPal.mut)
                Spacer()
                Menu {
                    Button { resolve(m, "approved") } label: { Text("✅ " + L("標為已核可")) }
                    Button { resolve(m, "rejected") } label: { Text("✖ " + L("標為已駁回")) }
                } label: { Text("⋯").font(WF.sans(18, .bold)).foregroundColor(Theme.text).frame(width: 30, height: 24) }
            }
            mediaView(m)
            Text(m.content ?? "").font(WF.sans(14.5)).foregroundColor(Theme.text).textSelection(.enabled)
            Text("↓ " + L("在下面直接回覆即可（可准、可駁回、可追問）")).font(WF.sans(11)).foregroundColor(ChatPal.mut)
            Text(Fmt.hhmm(m.ts)).font(WF.sans(10.5)).foregroundColor(ChatPal.mut)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(ChatPal.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ChatPal.red, lineWidth: 2))
        .onTapGesture { replyTo = m; focused = true }
    }
    private func resolvedCard(_ m: ChatMessage, approved: Bool) -> some View {
        let bg = approved ? Theme.dyn(0xe8f5e9, 0x1f2f22) : Theme.dyn(0xece7df, 0x2a251d)
        let bd = approved ? Color(hex: 0x3ba55d) : Color(hex: 0xc9c2b6)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(approved ? "✅ " + L("已核可") : "✖ " + L("已駁回")).font(WF.sans(11, .heavy)).foregroundColor(bd)
                Text(m.sender ?? "").font(WF.sans(12, .bold)).foregroundColor(ChatPal.mut)
                Spacer()
                Text(Fmt.hhmm(m.ts)).font(WF.sans(10.5)).foregroundColor(ChatPal.mut)
            }
            Text(m.content ?? "").font(WF.sans(14)).foregroundColor(Theme.text).textSelection(.enabled)
            if let by = m.resolved_by {
                Text("\(by) \(Fmt.hhmm(m.resolved_ts)) " + L("回覆") + "『\(m.verdict_text ?? "")』→ " + (approved ? L("已核准") : L("已駁回")))
                    .font(WF.sans(11)).foregroundColor(ChatPal.mut)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(bg).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(bd, lineWidth: 1))
    }

    // 輸入列：＋ 38 圓 ／ 輸入訊息…（可直接貼上照片） ／ 送 52×38
    private var composer: some View {
        VStack(spacing: 4) {
            if let r = replyTo {
                HStack {
                    Text(L("回覆決策：") + " \((r.content ?? "").prefix(50))").font(WF.sans(12)).foregroundColor(ChatPal.mut).lineLimit(1)
                    Spacer()
                    Button { replyTo = nil } label: { Text("✕").font(WF.sans(14)).foregroundColor(ChatPal.mut) }
                }.padding(.horizontal, 14).padding(.top, 6)
            }
            HStack(spacing: 8) {
                PhotosPicker(selection: $photo, matching: .any(of: [.images, .videos])) {
                    Text(uploading ? "⏳" : "＋").font(WF.sans(22, .medium)).foregroundColor(Theme.text)
                        .frame(width: 38, height: 38).background(ChatPal.field).clipShape(Circle())
                }.disabled(uploading)
                TextField(L("輸入訊息…（可直接貼上照片）"), text: $text, axis: .vertical).lineLimit(1...5)
                    .font(WF.sans(14.5)).foregroundColor(Theme.text).focused($focused)
                    .padding(.vertical, 9).padding(.horizontal, 14).background(ChatPal.field).clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                Button { send() } label: {
                    Text(L("送")).font(WF.sans(14, .heavy)).foregroundColor(.white).frame(width: 52, height: 38)
                        .background(text.trimmingCharacters(in: .whitespaces).isEmpty || sending ? ChatPal.brand.opacity(0.4) : ChatPal.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Theme.bg)
        .padding(.bottom, 20)
    }

    // MARK: data
    private func load(initial: Bool) async {
        do {
            let since = initial ? 0 : lastTs
            let r: MessagesResponse = try await state.api.request("/api/group-chat/groups/\(group.id)/messages?limit=\(initial ? 100 : 200)&since=\(since)")
            merge(r.messages)
            state.markRead(group)
        } catch { }
    }
    private func loadMembers() async {
        if let r: MembersResponse = try? await state.api.request("/api/group-chat/groups/\(group.id)/members") { members = r.members }
    }
    private func merge(_ new: [ChatMessage]) {
        var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for m in new { byId[m.id] = m }
        let sorted = byId.values.sorted { ($0.ts ?? 0, $0.id) < ($1.ts ?? 0, $1.id) }
        let oldIds = Set(messages.map { $0.id })
        if new.contains(where: { $0.msg_type == "agent" && !oldIds.contains($0.id) }) { typing = false; typingTask?.cancel() }
        messages = sorted
        lastTs = messages.last?.ts ?? lastTs
        DiskCache.save(Array(messages.suffix(100)), key: cacheKey)
    }
    private func startStream() {
        stream?.cancel()
        stream = Task {
            while !Task.isCancelled {
                do {
                    try await state.api.sse("/api/group-chat/groups/\(group.id)/stream") { data in
                        guard let ev = try? JSONDecoder().decode(SSEEvent.self, from: data) else { return }
                        Task { @MainActor in
                            if ev.type == "decision_update", let id = ev.id, let i = messages.firstIndex(where: { $0.id == id }) {
                                messages[i].decision = ev.decision; messages[i].decision_status = ev.decision_status
                                messages[i].resolved_by = ev.resolved_by; messages[i].verdict_text = ev.verdict_text; messages[i].resolved_ts = ev.resolved_ts
                            } else if let id = ev.id, ev.content != nil, !messages.contains(where: { $0.id == id }) {
                                let m = ChatMessage(id: id, group_id: group.id, sender: ev.sender, content: ev.content,
                                                    ts: Date().timeIntervalSince1970, msg_type: ev.msg_type, media_url: ev.media_url,
                                                    decision: ev.decision, decision_status: ev.decision_status, reply_to: ev.reply_to)
                                merge([m])
                                if !(m.isHuman) && state.hapticsEnabled { Haptic.tap() }
                            }
                        }
                    }
                } catch { }
                if Task.isCancelled { break }
                await load(initial: false)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
    private func send() {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        text = ""; sending = true; Haptic.tap()
        let rt = replyTo?.id
        replyTo = nil
        Task {
            do {
                var body: [String: Any] = ["sender": state.senderName, "content": content, "msg_type": "human", "decision": false]
                if let rt { body["reply_to"] = rt }
                let _: OkResponse = try await state.api.request("/api/group-chat/groups/\(group.id)/messages", method: "POST", body: body)
                await load(initial: false)
                typing = true
                typingTask?.cancel()
                typingTask = Task { try? await Task.sleep(nanoseconds: 20_000_000_000); if !Task.isCancelled { typing = false } }
            } catch { nav.show(error.localizedDescription, "error"); Haptic.error(); text = content }
            sending = false
        }
    }
    private func resolve(_ m: ChatMessage, _ status: String) {
        Haptic.medium()
        Task {
            do {
                let _: OkResponse = try await state.api.request("/api/group-chat/decisions/\(m.id)/resolve", method: "POST", body: ["status": status])
                nav.show(status == "approved" ? L("已標為已核可") : L("已標為已駁回"), "success")
                await load(initial: false)
            } catch { nav.show(error.localizedDescription, "error") }
        }
    }
    private func upload(_ item: PhotosPickerItem) {
        uploading = true
        Task {
            defer { uploading = false; photo = nil }
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            let ext = isVideo ? "mp4" : "jpg"
            let mime = isVideo ? "video/mp4" : "image/jpeg"
            var payload = data
            if !isVideo, let ui = UIImage(data: data), let jpg = ui.jpegData(compressionQuality: 0.85) { payload = jpg }
            do {
                let r = try await state.api.upload("/api/group-chat/upload", fileData: payload, filename: "iphone.\(ext)", mime: mime)
                guard let mu = r.media_url else { nav.show(r.error ?? L("上傳失敗"), "error"); return }
                let _: OkResponse = try await state.api.request("/api/group-chat/groups/\(group.id)/messages", method: "POST",
                    body: ["sender": state.senderName, "content": text.isEmpty ? "[\(r.filename ?? "photo")]" : text, "msg_type": "human", "media_url": mu, "decision": false])
                text = ""; Haptic.success()
                await load(initial: false)
            } catch { nav.show(error.localizedDescription, "error"); Haptic.error() }
        }
    }
}

struct InlineVideo: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        ZStack {
            Color.black
            if let player { VideoPlayer(player: player) }
        }
        .onAppear { player = AVPlayer(url: url) }
        .onDisappear { player?.pause(); player = nil }
    }
}

// MARK: - 群組資訊（← 名稱 ✏改名 / 成員（n）編輯 / 刪除群組）
struct GroupInfoView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    let group: ChatGroup
    let onBack: () -> Void
    let onDeleted: () -> Void
    @State private var members: [String] = []
    @State private var editing = false
    @State private var selectedMembers: [String] = []
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    var candidates: [String] { Array(NSOrderedSet(array: ["Chairman"] + (state.username.isEmpty ? [] : [state.username]) + state.sortedAgents.map { $0.name })) as? [String] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) { Text("←").font(WF.sans(20)).foregroundColor(Theme.text).frame(width: 36, height: 36) }
                if renaming {
                    TextField(L("群組名稱"), text: $newName).formField()
                    Button(L("確定")) { rename() }.buttonStyle(WarmButtonStyle(padV: 8, padH: 12, size: 12))
                } else {
                    Text(dispName(group)).font(WF.sans(18, .heavy)).foregroundColor(Theme.text).lineLimit(1)
                    if !isDM(group) {
                        Button { newName = group.name; renaming = true } label: {
                            Text("✏ " + L("改名")).font(WF.sans(11)).foregroundColor(Theme.text2).padding(.vertical, 2).padding(.horizontal, 8).background(Theme.surface).clipShape(Capsule())
                        }
                    }
                }
                Spacer()
            }.padding(.horizontal, 10).padding(.vertical, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L("成員") + "（\(members.count)）").font(WF.sans(14, .bold)).foregroundColor(Theme.text)
                            Spacer()
                            if !isDM(group) {
                                Button(editing ? L("取消") : L("編輯")) { selectedMembers = members; editing.toggle() }
                                    .font(WF.sans(12, .semibold)).foregroundColor(Theme.primary)
                            }
                        }
                        if editing {
                            ForEach(candidates, id: \.self) { m in
                                Button { toggleMember(m) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedMembers.contains(m) ? "checkmark.square.fill" : "square").foregroundColor(selectedMembers.contains(m) ? Theme.primary : Theme.text3)
                                        ChatCircle(name: m, size: 28)
                                        Text(m).font(WF.sans(14)).foregroundColor(Theme.text)
                                        Spacer()
                                    }.padding(.vertical, 4)
                                }.buttonStyle(.plain)
                            }
                            Button(L("儲存成員")) { saveMembers(selectedMembers) }.buttonStyle(WarmButtonStyle(padV: 10, full: true))
                        } else {
                            ForEach(members, id: \.self) { m in
                                HStack(spacing: 12) {
                                    ChatCircle(name: m, size: 28)
                                    Text(m).font(WF.sans(14)).foregroundColor(Theme.text)
                                    Spacer()
                                    Text(m == "Chairman" || m == "admin" || m == state.username ? L("老闆") : "Agent").font(WF.sans(11))
                                        .foregroundColor(ChatPal.color(m)).padding(.vertical, 2).padding(.horizontal, 8).background(ChatPal.color(m).opacity(0.13)).clipShape(Capsule())
                                    if !isDM(group) {
                                        Button { saveMembers(members.filter { $0 != m }) } label: { Text("✕").font(WF.sans(12)).foregroundColor(Color(hex: 0xdc2626)).padding(.horizontal, 8) }
                                    }
                                }.padding(.vertical, 4)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).card()
                    Button(L("刪除群組")) { confirmDelete = true }
                        .buttonStyle(WarmButtonStyle(padV: 12, full: true, bg: Color(hex: 0xdc2626)))
                }.padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .task { if let r: MembersResponse = try? await state.api.request("/api/group-chat/groups/\(group.id)/members") { members = r.members } }
        .confirmationDialog(L("確定要刪除此群組？"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L("刪除"), role: .destructive) { deleteGroup() }
        }
    }
    private func toggleMember(_ m: String) { if let i = selectedMembers.firstIndex(of: m) { selectedMembers.remove(at: i) } else { selectedMembers.append(m) } }
    private func saveMembers(_ list: [String]) {
        Task {
            do {
                let _: OkResponse = try await state.api.request("/api/group-chat/groups/\(group.id)/members", method: "POST", body: ["members": list])
                nav.show(L("成員已更新"), "success"); editing = false
                if let r: MembersResponse = try? await state.api.request("/api/group-chat/groups/\(group.id)/members") { members = r.members }
                await state.refreshGroups()
            } catch { nav.show(L("更新失敗"), "error") }
        }
    }
    private func rename() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Task {
            do {
                let _: OkResponse = try await state.api.request("/api/group-chat/groups/\(group.id)", method: "PATCH", body: ["name": n])
                nav.show(L("群組已重新命名"), "success"); renaming = false
                await state.refreshGroups()
            } catch { nav.show(L("重新命名失敗"), "error") }
        }
    }
    private func deleteGroup() {
        Task {
            do {
                let _: OkResponse = try await state.api.request("/api/group-chat/groups/\(group.id)", method: "DELETE")
                nav.show(L("群組已刪除"), "success")
                await state.refreshGroups()
                onDeleted()
            } catch { nav.show(L("刪除失敗"), "error") }
        }
    }
}

// MARK: - 新建群聊（← 新建群聊 / 群組名稱 / 選擇成員（n 已選））
struct CreateGroupView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    let onBack: () -> Void
    let onCreated: (ChatGroup) -> Void
    @State private var name = ""
    @State private var members: [String] = ["Chairman"]
    @State private var busy = false
    var candidates: [String] { ["Chairman"] + state.sortedAgents.map { $0.name } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) { Text("←").font(WF.sans(20)).foregroundColor(Theme.text).frame(width: 36, height: 36) }
                Text(L("新建群聊")).font(WF.sans(18, .heavy)).foregroundColor(Theme.text)
                Spacer()
            }.padding(.horizontal, 10).padding(.vertical, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("群組名稱")).font(WF.sans(12, .semibold)).foregroundColor(Theme.text2)
                    TextField(L("例：產品討論群"), text: $name).formField()
                    Text(L("選擇成員") + "（\(members.count) " + L("已選") + "）").font(WF.sans(12, .semibold)).foregroundColor(Theme.text2).padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(candidates, id: \.self) { m in
                            Button { if let i = members.firstIndex(of: m) { members.remove(at: i) } else { members.append(m) } } label: {
                                HStack(spacing: 12) {
                                    ChatCircle(name: m, size: 34)
                                    Text(m).font(WF.sans(14, .semibold)).foregroundColor(Theme.text)
                                    Spacer()
                                    Image(systemName: members.contains(m) ? "checkmark.circle.fill" : "circle").foregroundColor(members.contains(m) ? Theme.primary : Theme.text3)
                                }.padding(.vertical, 10).padding(.horizontal, 14)
                            }.buttonStyle(.plain)
                            Divider().overlay(ChatPal.line)
                        }
                    }.card(pad: 0)
                    Button(busy ? L("建立中…") : L("建立群組")) { create() }
                        .buttonStyle(WarmButtonStyle(padV: 12, full: true)).disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty || members.isEmpty)
                }.padding(16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
    private func create() {
        busy = true
        Task {
            do {
                let r: OkResponse = try await state.api.request("/api/group-chat/groups", method: "POST", body: ["name": name.trimmingCharacters(in: .whitespaces), "members": members])
                await state.refreshGroups(); Haptic.success()
                if let gid = r.group_id, let g = state.groups.first(where: { $0.id == gid }) { onCreated(g) }
                else if let g = state.groups.first(where: { $0.name == name.trimmingCharacters(in: .whitespaces) }) { onCreated(g) }
                else { onBack() }
            } catch { nav.show(L("建立失敗") + "：" + error.localizedDescription, "error") }
            busy = false
        }
    }
}

// iOS 16 相容的不等角圓角（LINE 氣泡 14/3）
struct BubbleShape: Shape {
    var tl: CGFloat, tr: CGFloat, bl: CGFloat, br: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        p.addArc(center: CGPoint(x: r.maxX - tr, y: r.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        p.addArc(center: CGPoint(x: r.maxX - br, y: r.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
        p.addArc(center: CGPoint(x: r.minX + bl, y: r.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
        p.addArc(center: CGPoint(x: r.minX + tl, y: r.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}
