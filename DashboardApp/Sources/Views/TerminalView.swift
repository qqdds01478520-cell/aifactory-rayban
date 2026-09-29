import SwiftUI

// 終端機：rendered（乾淨歷史）1.5s 輪詢；拿不到時退 raw buffer 去 ANSI。輸入走 /api/terminal/input（契約 §4）
struct TerminalView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var l10n: L10n
    @Binding var preselect: String?
    @State private var agent: String = ""
    @State private var lines: [String] = []
    @State private var source: String = ""
    @State private var rawTotal = 0
    @State private var rawText = ""
    @State private var input = ""
    @State private var rawMode = false
    @State private var err: String?
    @State private var urls: [String] = []
    @State private var poller: Task<Void, Never>?
    @State private var autoScroll = true
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                picker
                if !urls.isEmpty { urlBar }
                output
                inputBar
            }
            .screenBackground()
            .navigationTitle(L("tab.terminal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Toggle(isOn: $rawMode) { Text(rawMode ? L("term.raw") : L("term.chat")).font(.caption) }
                        .toggleStyle(.button).tint(Theme.primary)
                }
            }
        }
        .onAppear {
            if let p = preselect { agent = p; preselect = nil }
            if agent.isEmpty { agent = state.sortedAgents.first(where: { $0.isRunning })?.name ?? state.sortedAgents.first?.name ?? "" }
            startPolling()
        }
        .onDisappear { poller?.cancel() }
        .onChange(of: preselect) { p in if let p { agent = p; preselect = nil; startPolling() } }
        .onChange(of: agent) { _ in lines = []; rawText = ""; rawTotal = 0; urls = []; startPolling() }
    }

    private var picker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(state.sortedAgents) { a in
                    Button {
                        Haptic.select(); agent = a.name
                    } label: {
                        HStack(spacing: 6) {
                            StatusDot(running: a.isRunning, error: a.hasAuthError)
                            Text(a.name).font(.footnote.weight(agent == a.name ? .bold : .regular))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(agent == a.name ? Theme.primary.opacity(0.18) : Theme.surface)
                        .foregroundColor(agent == a.name ? Theme.primary : Theme.text)
                        .clipShape(Capsule())
                    }
                }
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Theme.bg)
    }

    private var urlBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text(L("term.urls")).font(.caption2).foregroundColor(Theme.muted)
                ForEach(urls, id: \.self) { u in
                    if let url = URL(string: u) {
                        Link(destination: url) {
                            Text(url.host ?? u).font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Theme.accent.opacity(0.18)).foregroundColor(Theme.accent).clipShape(Capsule())
                        }
                    }
                }
            }.padding(.horizontal, 12).padding(.bottom, 6)
        }
    }

    private var output: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if lines.isEmpty && rawText.isEmpty {
                        Text(err ?? L("common.loading")).font(.footnote).foregroundColor(Theme.muted).padding()
                    }
                    if !lines.isEmpty {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                            Text(l.isEmpty ? " " : l)
                                .font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    } else if !rawText.isEmpty {
                        Text(rawText).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
            .background(Color.black.opacity(0.92))
            .onChange(of: lines.count) { _ in if autoScroll { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: rawText) { _ in if autoScroll { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onTapGesture { focused = false }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if rawMode {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        key("Esc", "\u{1B}"); key("Tab", "\t"); key("↑", "\u{1B}[A"); key("↓", "\u{1B}[B")
                        key("←", "\u{1B}[D"); key("→", "\u{1B}[C"); key("Enter", "\r"); key("^C", "\u{03}")
                        key("Shift+Tab", "\u{1B}[Z"); key("1", "1"); key("2", "2"); key("y", "y"); key("n", "n")
                    }.padding(.horizontal, 12)
                }
            }
            HStack(spacing: 8) {
                TextField(L("term.placeholder"), text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundColor(Theme.text)
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundColor(input.isEmpty ? Theme.muted : Theme.primary)
                }.disabled(input.isEmpty)
            }.padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .background(Theme.bg)
    }

    private func key(_ label: String, _ seq: String) -> some View {
        Button {
            Haptic.tap()
            Task { await sendRaw(seq) }
        } label: {
            Text(label).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                .background(Theme.surface).foregroundColor(Theme.text).clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func send() {
        let text = input
        input = ""
        Haptic.tap()
        Task {
            if rawMode { await sendRaw(text + "\r") }
            else {
                do {
                    let _: OkResponse = try await state.api.request("/api/terminal/input", method: "POST",
                                                                    body: ["name": agent, "text": text, "group_reply": true])
                    err = nil
                } catch { err = error.localizedDescription; Haptic.error() }
            }
        }
    }
    private func sendRaw(_ seq: String) async {
        do {
            let _: OkResponse = try await state.api.request("/api/terminal/input", method: "POST",
                                                            body: ["name": agent, "text": seq, "group_reply": false])
        } catch { err = error.localizedDescription }
    }

    private func startPolling() {
        poller?.cancel()
        guard !agent.isEmpty else { return }
        let name = agent
        poller = Task {
            var tick = 0
            while !Task.isCancelled {
                await pollOnce(name)
                if tick % 4 == 0 {
                    if let u: TerminalURLs = try? await state.api.request("/api/terminal/urls/\(name)") { urls = u.urls ?? [] }
                }
                tick += 1
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }
    private func pollOnce(_ name: String) async {
        do {
            let r: TerminalBuffer = try await state.api.request("/api/terminal/rendered/\(name)")
            if let l = r.lines {
                if l != lines { lines = l }
                source = "scrollback"; err = nil
                return
            }
            let b: TerminalBuffer = try await state.api.request("/api/terminal/buffer/\(name)?after=\(rawTotal)")
            if b.source == "none" { err = L("term.nopty"); return }
            let chunk = (b.lines ?? []).joined()
            if !chunk.isEmpty {
                rawText = String((rawText + ANSI.strip(chunk)).suffix(60_000))
            }
            rawTotal = b.total ?? rawTotal
            source = b.source ?? ""; err = nil
        } catch let e as APIError where e.status == 404 {
            err = L("term.nopty")
        } catch {
            err = error.localizedDescription
        }
    }
}
