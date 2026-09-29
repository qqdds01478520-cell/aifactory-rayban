import SwiftUI

struct AgentsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var l10n: L10n
    var openTerminal: (String) -> Void
    @State private var query = ""
    @State private var onlyRunning = false
    @State private var toast: String?
    @State private var working: Set<String> = []

    var list: [Agent] {
        state.sortedAgents.filter { a in
            (!onlyRunning || a.isRunning) && (query.isEmpty || a.name.localizedCaseInsensitiveContains(query) || (a.model ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("", selection: $onlyRunning) {
                        Text(L("ag.filter.all")).tag(false)
                        Text(L("ag.filter.running")).tag(true)
                    }.pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                Section {
                    ForEach(list) { a in
                        NavigationLink { AgentDetailView(agent: a, openTerminal: openTerminal) } label: { row(a) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if state.isAdmin {
                                    if a.isRunning {
                                        Button(role: .destructive) { act(a, start: false) } label: { Label(L("ag.stop"), systemImage: "stop.fill") }
                                    } else {
                                        Button { act(a, start: true) } label: { Label(L("ag.start"), systemImage: "play.fill") }.tint(Theme.success)
                                    }
                                }
                            }
                            .listRowBackground(Theme.surface)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .screenBackground()
            .searchable(text: $query, prompt: L("ag.search"))
            .refreshable { await state.refreshState() }
            .navigationTitle(L("tab.agents"))
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast).font(.footnote).foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.danger).clipShape(Capsule()).padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func row(_ a: Agent) -> some View {
        HStack(spacing: 12) {
            StatusDot(running: a.isRunning, error: a.hasAuthError)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(a.name).font(.body.weight(.medium)).foregroundColor(Theme.text)
                    if a.isBusy { Pill(text: L("ag.busy"), color: Theme.primary) }
                    if a.hasAuthError { Pill(text: L("ag.autherr"), color: Theme.danger) }
                }
                Text(a.engineLabel).font(.caption).foregroundColor(Theme.muted).lineLimit(1)
            }
            Spacer()
            if working.contains(a.name) { ProgressView().scaleEffect(0.8) }
            else if let u = state.usage[a.name], u.total7d > 0 {
                Text(Fmt.tokens(u.total7d)).font(.caption2).foregroundColor(Theme.muted).monospacedDigit()
            }
        }.padding(.vertical, 2)
    }

    private func act(_ a: Agent, start: Bool) {
        Haptic.tap()
        working.insert(a.name)
        Task {
            let e = start ? await state.startAgent(a.name) : await state.stopAgent(a.name)
            working.remove(a.name)
            if let e { withAnimation { toast = e }; try? await Task.sleep(nanoseconds: 3_000_000_000); withAnimation { toast = nil } }
        }
    }
}

struct AgentDetailView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    let agent: Agent
    var openTerminal: (String) -> Void
    @State private var md: String = ""
    @State private var mdLoaded = false
    @State private var editing = false
    @State private var saving = false
    @State private var msg: String?
    @State private var confirmStop = false

    var live: Agent { state.agents.first { $0.name == agent.name } ?? agent }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        StatusDot(running: live.isRunning, error: live.hasAuthError)
                        Text(live.isRunning ? L("ag.running") : L("ag.stopped")).font(.subheadline.weight(.semibold)).foregroundColor(Theme.text)
                        if live.isBusy { Pill(text: L("ag.busy"), color: Theme.primary) }
                        Spacer()
                        if let p = live.pid { Text("\(L("ag.pid")) \(p)").font(.caption).foregroundColor(Theme.muted) }
                    }
                    HStack { Text(L("ag.model")).foregroundColor(Theme.muted); Spacer(); Text(live.engineLabel).foregroundColor(Theme.text) }.font(.footnote)
                    if let u = state.usage[agent.name] {
                        HStack { Text("Token 7d").foregroundColor(Theme.muted); Spacer(); Text("in \(Fmt.tokens(u.input ?? 0)) · out \(Fmt.tokens(u.output ?? 0)) · cache \(Fmt.tokens((u.cache_read ?? 0) + (u.cache_create ?? 0)))").foregroundColor(Theme.text) }.font(.footnote)
                    }
                    HStack(spacing: 10) {
                        if state.isAdmin {
                            if live.isRunning {
                                Button { confirmStop = true } label: { Label(L("ag.stop"), systemImage: "stop.fill").frame(maxWidth: .infinity) }
                                    .buttonStyle(.bordered).tint(Theme.danger)
                            } else {
                                Button { Task { msg = await state.startAgent(agent.name) } } label: { Label(L("ag.start"), systemImage: "play.fill").frame(maxWidth: .infinity) }
                                    .buttonStyle(.borderedProminent).tint(Theme.success)
                            }
                        }
                        Button { openTerminal(agent.name); dismiss() } label: { Label(L("ag.terminal"), systemImage: "terminal").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                    }
                    if let msg { Text(msg).font(.footnote).foregroundColor(Theme.danger) }
                }.card()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("ag.claudemd")).font(.subheadline.weight(.semibold)).foregroundColor(Theme.text)
                        Spacer()
                        if editing {
                            Button(saving ? "…" : L("ag.save")) { save() }.disabled(saving).font(.footnote.weight(.semibold))
                        } else {
                            Button { editing = true } label: { Image(systemName: "pencil") }
                        }
                    }
                    if !mdLoaded { ProgressView().frame(maxWidth: .infinity) }
                    else if editing {
                        TextEditor(text: $md).font(.system(.footnote, design: .monospaced)).frame(minHeight: 360)
                            .scrollContentBackground(.hidden).background(Theme.surface2).cornerRadius(10)
                    } else {
                        Text(md.isEmpty ? L("common.none") : md).font(.system(.footnote, design: .monospaced)).foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                }.card()
            }.padding(16)
        }
        .screenBackground()
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { let r: ClaudeMD = try await state.api.request("/api/agents/\(agent.name)/claude-md"); md = r.content ?? "" }
            catch { md = "" }
            mdLoaded = true
        }
        .confirmationDialog(L("ag.confirmstop"), isPresented: $confirmStop, titleVisibility: .visible) {
            Button(L("ag.stop"), role: .destructive) { Task { msg = await state.stopAgent(agent.name) } }
        }
    }
    private func save() {
        saving = true
        Task {
            do {
                let _: OkResponse = try await state.api.request("/api/agents/\(agent.name)/claude-md", method: "POST", body: ["content": md])
                editing = false; Haptic.success(); msg = nil
            } catch { msg = error.localizedDescription; Haptic.error() }
            saving = false
        }
    }
}
