import SwiftUI

// 終端機＝網頁 TerminalPage：h1 終端機／即時操作介面、Mac 式深色終端卡（三色點＋員工下拉＋連線燈＋📜歷史 📋 🔄）、
// 🔗 開啟登入網址、Esc ↑ ↓ ⏎ 更多▸ 📋 貼代碼、原生 切換＋輸入列＋送出
struct TerminalView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @EnvironmentObject var l10n: L10n
    @State private var agent: String = ""
    @State private var lines: [String] = []
    @State private var rawTotal = 0
    @State private var rawText = ""
    @State private var input = ""
    @State private var rawMode = false
    @State private var showHistory = false
    @State private var showMoreKeys = false
    @State private var connected = false
    @State private var err: String?
    @State private var urls: [String] = []
    @State private var poller: Task<Void, Never>?
    @State private var refreshCount = 0
    @FocusState private var focused: Bool

    private let termBg = Color(hex: 0x1c1917)
    private let headBg = Color(hex: 0x292524)
    private let green = Color(hex: 0x28c840)

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                PageTitle(L("終端機"), size: 26)
                Text(L("即時操作介面")).font(WF.sans(13)).foregroundColor(Theme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 12)

            termCard.padding(.horizontal, 16)
            if !agent.isEmpty && !urls.isEmpty { urlBar.padding(.horizontal, 16).padding(.top, 8) }
            if !agent.isEmpty { keyRow.padding(.horizontal, 16).padding(.top, 8) }
            inputBar.padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            if let p = nav.terminalAgent { agent = p; nav.terminalAgent = nil }
            if agent.isEmpty { agent = state.sortedAgents.first(where: { $0.isRunning })?.name ?? state.sortedAgents.first?.name ?? "" }
            startPolling()
        }
        .onDisappear { poller?.cancel() }
        .onChange(of: nav.terminalAgent) { p in if let p { agent = p; nav.terminalAgent = nil } }
        .onChange(of: agent) { _ in lines = []; rawText = ""; rawTotal = 0; urls = []; connected = false; startPolling() }
        .onChange(of: refreshCount) { _ in lines = []; rawText = ""; rawTotal = 0; connected = false; startPolling() }
    }

    // MARK: 終端卡
    private var termCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(Color(hex: 0xff5f57)).frame(width: 10, height: 10)
                Circle().fill(Color(hex: 0xfebc2e)).frame(width: 10, height: 10)
                Circle().fill(green).frame(width: 10, height: 10)
                Menu {
                    ForEach(state.sortedAgents) { a in
                        Button { agent = a.name } label: { Text(a.name + (a.isRunning ? " ● " + L("運行中") : "")) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(agent.isEmpty ? L("選擇 Agent") : agent + ((state.agents.first { $0.name == agent }?.isRunning ?? false) ? " ● " + L("運行中") : ""))
                            .font(WF.mono(11)).foregroundColor(Color(hex: 0xa8a29e)).lineLimit(1)
                        Text("▾").font(WF.mono(9)).foregroundColor(Color(hex: 0xa8a29e))
                    }
                }.padding(.leading, 8)
                Spacer()
                Circle().fill(connected ? Color(hex: 0x4caf50) : Color(hex: 0x555555)).frame(width: 6, height: 6)
                Text(connected ? "HTTP" : L("離線")).font(WF.mono(10)).foregroundColor(Color(hex: 0x78716c))
                headBtn("📜 " + L("歷史"), active: showHistory) { showHistory.toggle(); Haptic.tap() }
                headBtn("📋", active: false) { UIPasteboard.general.string = fullText; nav.show(L("已複製"), "success", ms: 1200) }
                headBtn("🔄", active: false) { refreshCount += 1; Haptic.tap() }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(headBg)
            .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .bottom)

            if agent.isEmpty {
                VStack(spacing: 8) {
                    Text("💻").font(.system(size: 32))
                    Text(L("選擇一個 Agent 開始連線")).font(WF.mono(13)).foregroundColor(Color(hex: 0x78716c))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                output
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(termBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 12)
    }
    private func headBtn(_ t: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(WF.sans(12)).foregroundColor(active ? green : Color(hex: 0xa8a29e))
                .padding(.vertical, 4).padding(.horizontal, 8)
                .background(active ? green.opacity(0.18) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
    private var fullText: String { lines.isEmpty ? rawText : lines.joined(separator: "\n") }

    private var output: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal], showsIndicators: showHistory) {
                VStack(alignment: .leading, spacing: 0) {
                    if lines.isEmpty && rawText.isEmpty {
                        Text(err ?? L("連線中…")).font(WF.mono(12.5)).foregroundColor(Color(hex: 0x78716c)).padding(8)
                    } else {
                        Text(fullText.isEmpty ? " " : fullText)
                            .font(WF.mono(12.5)).foregroundColor(Color(hex: 0xe7e5e4))
                            .lineSpacing(3)
                            .fixedSize(horizontal: showHistory, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            .onChange(of: lines.count) { _ in if !showHistory { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: rawText) { _ in if !showHistory { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onTapGesture { focused = false }
        }
    }

    // MARK: 登入網址列
    private var urlBar: some View {
        HStack(spacing: 6) {
            Button { openLatestLoginUrl() } label: {
                Text("🔗 " + L("開啟登入網址")).font(WF.mono(13, .semibold)).foregroundColor(green).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9).padding(.horizontal, 12)
                    .background(green.opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(green.opacity(0.4), lineWidth: 1))
            }
            Button { UIPasteboard.general.string = urls.first; nav.show(L("已複製網址"), "success", ms: 1200) } label: {
                Text("📋").font(WF.mono(13)).foregroundColor(Theme.text2).padding(.vertical, 9).padding(.horizontal, 12)
                    .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            }
        }
    }
    private func openLatestLoginUrl() {
        Task {
            var url = urls.first ?? ""
            if let r: TerminalURLs = try? await state.api.request("/api/terminal/urls/\(agent)") {
                let fresh = (r.urls ?? []).compactMap { $0.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) }.filter { $0.hasPrefix("http") }
                if let f = fresh.first { url = f; urls = Array(NSOrderedSet(array: fresh)) as? [String] ?? fresh }
            }
            if let u = URL(string: url) { UIApplication.shared.open(u) }
        }
    }

    // MARK: 控制鍵列
    private var keyRow: some View {
        HStack(spacing: 6) {
            key("Esc", "\u{1B}"); key("↑", "\u{1B}[A"); key("↓", "\u{1B}[B"); key("⏎", "\r")
            Button { withAnimation { showMoreKeys.toggle() } } label: {
                Text(showMoreKeys ? L("更多") + "▾" : L("更多") + "▸").font(WF.mono(12)).foregroundColor(Theme.text2)
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.border, lineWidth: 1))
            }
            if showMoreKeys { key("←", "\u{1B}[D"); key("→", "\u{1B}[C"); key("Tab", "\t"); key("^C", "\u{03}") }
            Spacer(minLength: 0)
            Button { pasteFromClipboard() } label: {
                Text("📋 " + L("貼代碼")).font(WF.mono(13, .semibold)).foregroundColor(green)
                    .padding(.vertical, 6).padding(.horizontal, 12)
                    .background(green.opacity(0.16)).clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(green.opacity(0.4), lineWidth: 1))
            }
        }
    }
    private func key(_ label: String, _ seq: String) -> some View {
        Button { Haptic.tap(); Task { await sendRaw(seq) } } label: {
            Text(label).font(WF.mono(13)).foregroundColor(Theme.text)
                .frame(minWidth: 38).padding(.vertical, 6).padding(.horizontal, 11)
                .background(Color(hex: 0x7c4dff, alpha: 0.10)).clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.border, lineWidth: 1))
        }
    }

    // MARK: 輸入列
    private var inputBar: some View {
        HStack(spacing: 8) {
            Button { rawMode.toggle(); Haptic.select() } label: {
                Text(rawMode ? L("原生✓") : L("原生")).font(WF.mono(12)).foregroundColor(rawMode ? green : Theme.text2)
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(rawMode ? green.opacity(0.18) : Theme.surface).clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            }
            TextField(rawMode ? L("直接送進終端…") : L("輸入指令..."), text: $input)
                .noAutoCap().focused($focused).submitLabel(.send).onSubmit { send() }
                .inputWarm(padV: 10, padH: 14, size: 13)
            Button(L("送出")) { send() }.buttonStyle(WarmButtonStyle(padV: 10, padH: 16, size: 13))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.bg)
        .overlay(Rectangle().fill(Theme.border).frame(height: 1), alignment: .top)
        .padding(.bottom, 96)
    }

    // MARK: 送出
    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !agent.isEmpty else { return }
        input = ""; Haptic.tap()
        Task {
            if rawMode { await sendRaw(text + "\r") }
            else {
                do {
                    let _: OkResponse = try await state.api.request("/api/terminal/input", method: "POST", body: ["name": agent, "text": text])
                    err = nil
                } catch { nav.show(error.localizedDescription, "error"); Haptic.error() }
            }
        }
    }
    private func pasteFromClipboard() {
        guard !agent.isEmpty else { return }
        var txt = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if txt.isEmpty { txt = input.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !txt.isEmpty else { return }
        input = ""
        Task { await sendRaw(txt + "\r") }
    }
    private func sendRaw(_ seq: String) async {
        do {
            let _: OkResponse = try await state.api.request("/api/terminal/input", method: "POST", body: ["name": agent, "text": seq, "group_reply": false])
        } catch { nav.show(error.localizedDescription, "error") }
    }

    // MARK: 輪詢（rendered 1.5s；退 raw buffer 去 ANSI）
    private func startPolling() {
        poller?.cancel()
        guard !agent.isEmpty else { return }
        let name = agent
        poller = Task {
            var tick = 0
            while !Task.isCancelled {
                await pollOnce(name)
                if tick % 4 == 0 {
                    if let u: TerminalURLs = try? await state.api.request("/api/terminal/urls/\(name)") {
                        let fresh = (u.urls ?? []).compactMap { $0.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) }.filter { $0.hasPrefix("http") }
                        urls = Array(NSOrderedSet(array: fresh)) as? [String] ?? fresh
                    }
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
                connected = true; err = nil
                return
            }
            let b: TerminalBuffer = try await state.api.request("/api/terminal/buffer/\(name)?after=\(rawTotal)")
            if b.source == "none" { err = L("此員工未在運行，先到員工頁啟動"); connected = false; return }
            let chunk = (b.lines ?? []).joined()
            if !chunk.isEmpty { rawText = String((rawText + ANSI.strip(chunk)).suffix(60_000)) }
            rawTotal = b.total ?? rawTotal
            connected = true; err = nil
        } catch let e as APIError where e.status == 404 {
            err = L("此員工未在運行，先到員工頁啟動"); connected = false
        } catch { err = error.localizedDescription; connected = false }
    }
}
