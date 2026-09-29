import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var l10n: L10n
    @State private var showNew = false
    @State private var poller: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                ForEach(state.groups) { g in
                    NavigationLink { ConversationView(group: g) } label: { row(g) }
                        .listRowBackground(Theme.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .screenBackground()
            .overlay { if state.groups.isEmpty { EmptyHint(text: L("chat.empty")) } }
            .refreshable { await state.refreshGroups() }
            .navigationTitle(L("tab.chat"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus.circle") }
                }
            }
            .sheet(isPresented: $showNew) { NewGroupSheet() }
        }
        .onAppear {
            poller?.cancel()
            poller = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    await state.refreshGroups()
                }
            }
        }
        .onDisappear { poller?.cancel() }
    }

    private func row(_ g: ChatGroup) -> some View {
        let unread = (g.last_msg_id ?? 0) > (state.readMarks[g.id] ?? 0)
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(g.name.hasPrefix("DM:") ? Theme.accent.opacity(0.2) : Theme.primary.opacity(0.18)).frame(width: 42, height: 42)
                Text(String(g.name.replacingOccurrences(of: "DM: ", with: "").prefix(1))).font(.headline).foregroundColor(g.name.hasPrefix("DM:") ? Theme.accent : Theme.primary)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(g.name).font(.body.weight(unread ? .bold : .medium)).foregroundColor(Theme.text).lineLimit(1)
                    if (g.pending_decisions ?? 0) > 0 { Pill(text: "\(L("chat.pending")) \(g.pending_decisions!)", color: Theme.warning) }
                    Spacer()
                    Text(Fmt.when(g.last_ts)).font(.caption2).foregroundColor(Theme.muted)
                }
                HStack {
                    Text((g.last_sender.map { $0 + ": " } ?? "") + (g.last_preview ?? "")).font(.caption).foregroundColor(unread ? Theme.text : Theme.muted).lineLimit(1)
                    Spacer()
                    if unread { Circle().fill(Theme.primary).frame(width: 8, height: 8) }
                }
            }
        }.padding(.vertical, 3)
    }
}

struct NewGroupSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var members: Set<String> = []
    @State private var err: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField(L("chat.name"), text: $name)
                Section(L("chat.members")) {
                    ForEach(state.sortedAgents) { a in
                        Button {
                            if members.contains(a.name) { members.remove(a.name) } else { members.insert(a.name) }
                        } label: {
                            HStack { Text(a.name).foregroundColor(Theme.text); Spacer(); if members.contains(a.name) { Image(systemName: "checkmark").foregroundColor(Theme.primary) } }
                        }
                    }
                }
                if let err { Text(err).foregroundColor(Theme.danger) }
            }
            .navigationTitle(L("chat.new"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("chat.create")) {
                        Task {
                            do {
                                let _: OkResponse = try await state.api.request("/api/group-chat/groups", method: "POST",
                                                                                body: ["name": name, "members": Array(members)])
                                await state.refreshGroups(); Haptic.success(); dismiss()
                            } catch { err = error.localizedDescription }
                        }
                    }.disabled(name.isEmpty || members.isEmpty)
                }
            }
        }
    }
}

// 對話：首載 messages?limit=100 → SSE 推新 → 斷線退 5s 輪詢；回前景用 since 補洞（契約 §5）
struct ConversationView: View {
    @EnvironmentObject var state: AppState
    let group: ChatGroup
    @State private var messages: [ChatMessage] = []
    @State private var text = ""
    @State private var sending = false
    @State private var uploading = false
    @State private var err: String?
    @State private var replyTo: ChatMessage?
    @State private var photo: PhotosPickerItem?
    @State private var stream: Task<Void, Never>?
    @State private var lastTs: Double = 0
    @FocusState private var focused: Bool
    private var cacheKey: String { "msgs_\(group.id)" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty { EmptyHint(text: L("chat.empty")) }
                        ForEach(messages) { m in bubble(m).id(m.id) }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(.horizontal, 12).padding(.vertical, 10)
                }
                .onChange(of: messages.count) { _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
                .onTapGesture { focused = false }
            }
            composer
        }
        .screenBackground()
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Text("\(L("chat.members")): \((group.members ?? []).joined(separator: ", "))")
                } label: { Image(systemName: "person.2") }
            }
        }
        .task {
            if let c = DiskCache.load([ChatMessage].self, key: cacheKey) { messages = c; lastTs = c.last?.ts ?? 0 }
            await load(initial: true)
            startStream()
        }
        .onDisappear { stream?.cancel(); state.markRead(group) }
        .onChange(of: photo) { item in if let item { upload(item) } }
    }

    // MARK: bubbles
    private func bubble(_ m: ChatMessage) -> some View {
        let mine = m.isHuman
        return HStack(alignment: .bottom) {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 4) {
                if !mine { Text(m.sender ?? "").font(.caption2.weight(.semibold)).foregroundColor(Theme.accent) }
                if let r = m.reply_to, let orig = messages.first(where: { $0.id == r }) {
                    Text("↩ \(orig.sender ?? ""): \((orig.content ?? "").prefix(40))").font(.caption2).foregroundColor(Theme.muted).lineLimit(1)
                }
                if let mu = m.media_url, let url = state.api.mediaURL(mu) {
                    if mu.lowercased().hasSuffix(".mp4") || mu.lowercased().hasSuffix(".mov") || mu.lowercased().hasSuffix(".webm") {
                        NavigationLink { VideoScreen(url: url, title: m.sender ?? "") } label: {
                            ZStack { RoundedRectangle(cornerRadius: 10).fill(Color.black).frame(width: 220, height: 124); Image(systemName: "play.circle.fill").font(.largeTitle).foregroundColor(.white) }
                        }
                    } else {
                        AsyncImage(url: url) { img in img.resizable().scaledToFit() } placeholder: { ProgressView() }
                            .frame(maxWidth: 240, maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                if let c = m.content, !c.isEmpty, !(m.media_url != nil && c.hasPrefix("[") && c.hasSuffix("]")) {
                    Text(c).font(.subheadline).foregroundColor(mine ? .white : Theme.text)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(mine ? Theme.primary : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .textSelection(.enabled)
                }
                if (m.decision ?? 0) == 1 { decisionRow(m) }
                Text(Fmt.when(m.ts)).font(.caption2).foregroundColor(Theme.muted)
            }
            .contextMenu {
                Button { replyTo = m; focused = true } label: { Label(L("chat.replying"), systemImage: "arrowshape.turn.up.left") }
                Button { UIPasteboard.general.string = m.content } label: { Label("Copy", systemImage: "doc.on.doc") }
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private func decisionRow(_ m: ChatMessage) -> some View {
        if m.isPending {
            HStack(spacing: 8) {
                Button(L("chat.approve")) { resolve(m, "approved") }.buttonStyle(.borderedProminent).tint(Theme.success).controlSize(.small)
                Button(L("chat.reject")) { resolve(m, "rejected") }.buttonStyle(.bordered).tint(Theme.danger).controlSize(.small)
            }
        } else if let s = m.decision_status {
            Pill(text: s == "approved" ? L("chat.approved") : L("chat.rejected"), color: s == "approved" ? Theme.success : Theme.danger)
        }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            if let r = replyTo {
                HStack {
                    Text("↩ \(r.sender ?? ""): \((r.content ?? "").prefix(50))").font(.caption).foregroundColor(Theme.muted).lineLimit(1)
                    Spacer()
                    Button { replyTo = nil } label: { Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted) }
                }.padding(.horizontal, 14)
            }
            if let err { Text(err).font(.caption2).foregroundColor(Theme.danger).padding(.horizontal, 14) }
            HStack(spacing: 8) {
                PhotosPicker(selection: $photo, matching: .any(of: [.images, .videos])) {
                    Image(systemName: uploading ? "hourglass" : "photo").font(.title3).foregroundColor(Theme.muted)
                }.disabled(uploading)
                TextField(L("chat.placeholder"), text: $text, axis: .vertical).lineLimit(1...5)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundColor(Theme.text)
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                        .foregroundColor(text.trimmingCharacters(in: .whitespaces).isEmpty || sending ? Theme.muted : Theme.primary)
                }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }.background(Theme.bg)
    }

    // MARK: data
    private func load(initial: Bool) async {
        do {
            let since = initial ? 0 : lastTs
            let r: MessagesResponse = try await state.api.request("/api/group-chat/groups/\(group.id)/messages?limit=\(initial ? 100 : 200)&since=\(since)")
            merge(r.messages)
            state.markRead(group)
        } catch { err = error.localizedDescription }
    }
    private func merge(_ new: [ChatMessage]) {
        var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for m in new { byId[m.id] = m }
        messages = byId.values.sorted { ($0.ts ?? 0, $0.id) < ($1.ts ?? 0, $1.id) }
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
                                messages[i].resolved_by = ev.resolved_by; messages[i].verdict_text = ev.verdict_text
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
                // SSE 斷：補洞後 5s 再連（Funnel 會收閒置連線）
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
                err = nil
                await load(initial: false)
            } catch { err = error.localizedDescription; Haptic.error(); text = content }
            sending = false
        }
    }
    private func resolve(_ m: ChatMessage, _ status: String) {
        Haptic.medium()
        Task {
            do {
                let _: OkResponse = try await state.api.request("/api/group-chat/decisions/\(m.id)/resolve", method: "POST", body: ["status": status])
                await load(initial: false)
            } catch { err = error.localizedDescription }
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
                guard let mu = r.media_url else { err = r.error ?? "upload failed"; return }
                let _: OkResponse = try await state.api.request("/api/group-chat/groups/\(group.id)/messages", method: "POST",
                    body: ["sender": state.senderName, "content": text.isEmpty ? "[\(r.filename ?? "photo")]" : text, "msg_type": "human", "media_url": mu, "decision": false])
                text = ""; Haptic.success()
                await load(initial: false)
            } catch { err = error.localizedDescription; Haptic.error() }
        }
    }
}
