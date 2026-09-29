import SwiftUI

// 員工管理＝網頁 AgentsPage：h1＋「+ 新增」、運行/停止/錯誤 tag、篩選膠囊、agent-row 清單、詳情 SlidePanel、新增 ModalSheet
struct AgentsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @EnvironmentObject var l10n: L10n
    @State private var filter = 0     // 0 全部 1 運行中 2 已停止
    @State private var showCreate = false
    @State private var detail: Agent?
    @State private var busyName: String?

    var all: [Agent] { state.sortedAgents }
    var runningN: Int { all.filter { $0.isRunning }.count }
    var errorN: Int { all.filter { $0.isRunning && $0.hasAuthError }.count }
    var stoppedN: Int { all.count - runningN }
    var shown: [Agent] {
        switch filter { case 1: return all.filter { $0.isRunning }; case 2: return all.filter { !$0.isRunning }; default: return all }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    PageTitle(L("員工管理"), size: 26)
                    Spacer()
                    Button("+ " + L("新增")) { showCreate = true }.buttonStyle(WarmButtonStyle(padV: 8, padH: 16, size: 13))
                }
                HStack(spacing: 8) {
                    Tag("\(runningN) " + L("運行"), .success)
                    Tag("\(stoppedN) " + L("停止"), .info)
                    Tag("\(errorN) " + L("錯誤"), .error)
                }
                HStack(spacing: 8) {
                    FilterPill(label: L("全部") + " (\(all.count))", active: filter == 0) { filter = 0 }
                    FilterPill(label: L("運行中") + " (\(runningN))", active: filter == 1) { filter = 1 }
                    FilterPill(label: L("已停止") + " (\(stoppedN))", active: filter == 2) { filter = 2 }
                }
                if all.isEmpty {
                    EmptyState(icon: "👤", title: L("建立你的第一位員工，他會兼任你的管家"), subtitle: L("按右上「+ 新增」從模板挑一位，馬上開工"))
                        .card()
                } else if shown.isEmpty {
                    EmptyState(icon: "🤖", title: L("沒有符合條件的 Agent")).card()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, a in
                            Button { detail = a } label: {
                                AgentRowView(agent: a, showButtons: true, busyName: busyName) { toggle(a) }
                            }.buttonStyle(.plain)
                            if i < shown.count - 1 { Divider().overlay(Theme.border) }
                        }
                    }.card(pad: 0)
                }
            }
            .pageBody()
        }
        .refreshable { await state.refreshState() }
        .background(Theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showCreate) { CreateAgentModal() }
        .fullScreenCover(item: $detail) { a in AgentDetailPanel(agent: a) }
    }

    private func toggle(_ a: Agent) {
        busyName = a.name
        Task {
            let err = a.isRunning ? await state.stopAgent(a.name) : await state.startAgent(a.name)
            busyName = nil
            if let err { nav.show(err, "error") }
            else { nav.show(a.isRunning ? L("已停止") + " " + a.name : L("已啟動") + " " + a.name, "success") }
        }
    }
}

// 員工詳情＝網頁 AgentDetailPanel（SlidePanel）：狀態卡＋啟動/停止/重啟＋打包販售＋資訊/CLAUDE.md/中文版
struct AgentDetailPanel: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @Environment(\.dismiss) var dismiss
    let agent: Agent
    @State private var tab = 0
    @State private var md = ""
    @State private var mdLoaded = false
    @State private var zh = ""
    @State private var zhLoading = false
    @State private var busy = false
    var live: Agent { state.agents.first { $0.name == agent.name } ?? agent }

    var body: some View {
        VStack(spacing: 0) {
            BackHeader(title: agent.name, size: 18) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusCard
                    Button { nav.show(L("打包販售：請到「商城 › 我要上架」選這位員工（後端未開放第三方上架時不顯示）"), "info", ms: 4000); nav.open(.store); dismiss() } label: {
                        Text("📦 " + L("打包販售（自動保護你的資料）")).font(WF.sans(13, .semibold)).foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity).padding(.vertical, 12).background(Theme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    SegTabs(items: [L("資訊"), "CLAUDE.md", L("中文版")], selection: $tab)
                    switch tab {
                    case 0: infoTab
                    case 1: mdTab
                    default: zhTab
                    }
                }
                .padding(16).padding(.bottom, 40)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onChange(of: tab) { t in
            if t == 1 && !mdLoaded { Task { await loadMD() } }
            if t == 2 && zh.isEmpty { Task { await loadZh() } }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StatusDot(running: live.isRunning, error: live.isRunning && live.hasAuthError)
                Text(live.isRunning ? L("運行中") : L("已停止")).font(WF.sans(14, .semibold)).foregroundColor(live.isRunning ? Theme.success : Theme.text2)
                if let pid = live.pid, live.isRunning { Text("PID: \(pid)").font(WF.sans(12)).foregroundColor(Theme.text3) }
                Spacer()
                if live.isBusy { BusyBadge() }
            }
            HStack(spacing: 8) {
                if !live.isRunning {
                    actionBtn(L("啟動"), bg: Color(hex: 0xf0fdf4), fg: Color(hex: 0x15803d)) { await run { await state.startAgent(agent.name) } }
                } else {
                    actionBtn(L("停止"), bg: Color(hex: 0xfef2f2), fg: Color(hex: 0xb91c1c)) { await run { await state.stopAgent(agent.name) } }
                    actionBtn(L("重啟"), bg: Color(hex: 0x713f12), fg: Color(hex: 0xfde047)) {
                        await run {
                            if let e = await state.stopAgent(agent.name) { return e }
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            return await state.startAgent(agent.name)
                        }
                    }
                }
                actionBtn("💻 " + L("終端機"), bg: Theme.surface2, fg: Theme.text) { dismiss(); nav.openTerminal(agent.name) }
            }
        }.card()
    }
    private func actionBtn(_ title: String, bg: Color, fg: Color, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(busy ? "…" : title).font(WF.sans(14, .bold)).foregroundColor(fg)
                .frame(maxWidth: .infinity).frame(height: 44).background(bg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }.disabled(busy)
    }
    private func run(_ op: () async -> String?) async {
        busy = true
        if let e = await op() { nav.show(e, "error") }
        busy = false
    }

    private var infoTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            infoCard(L("模型"), live.engineLabel.isEmpty ? "—" : live.engineLabel)
            infoCard(L("職稱"), (live.title ?? "").isEmpty ? "—" : live.title!)
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(L("頻道"))
                if (live.channels ?? []).isEmpty { Text("—").font(WF.sans(13)).foregroundColor(Theme.text2) }
                else { HStack(spacing: 6) { ForEach(live.channels ?? [], id: \.self) { c in Chip(c, .info) } } }
            }.frame(maxWidth: .infinity, alignment: .leading).card()
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(L("啟動設定"))
                Text("backend: \(live.backend ?? "claude")\nengine: \(live.engine ?? "claude")\nmodel: \(live.model ?? "")\nmanaged: \(live.managed ?? true)")
                    .font(WF.mono(12)).foregroundColor(Theme.text2)
            }.frame(maxWidth: .infinity, alignment: .leading).card()
        }
    }
    private func infoCard(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { MonoLabel(k); Text(v).font(WF.sans(14)).foregroundColor(Theme.text) }
            .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var mdTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !mdLoaded { ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding() }
            TextEditor(text: $md)
                .font(WF.mono(12)).foregroundColor(Theme.text).scrollContentBackground(.hidden)
                .frame(minHeight: 300).padding(8).background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
            Button(L("儲存 CLAUDE.md")) {
                Task {
                    do {
                        let _: OkResponse = try await state.api.request("/api/agents/\(agent.name)/claude-md", method: "POST", body: ["content": md])
                        nav.show(L("已儲存"), "success"); Haptic.success()
                    } catch { nav.show(error.localizedDescription, "error") }
                }
            }.buttonStyle(WarmButtonStyle(padV: 12, full: true))
        }
    }
    private var zhTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if zhLoading {
                HStack(spacing: 8) { ProgressView().tint(Theme.primary); Text(L("AI 翻譯中...")).font(WF.sans(13)).foregroundColor(Theme.text2) }
                    .frame(maxWidth: .infinity).padding()
            } else {
                Text(zh.isEmpty ? "—" : zh).font(WF.sans(13)).foregroundColor(Theme.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).card()
            }
        }
    }
    private func loadMD() async {
        if let r: ClaudeMD = try? await state.api.request("/api/agents/\(agent.name)/claude-md") { md = r.content ?? "" }
        mdLoaded = true
    }
    private func loadZh() async {
        zhLoading = true
        defer { zhLoading = false }
        do {
            let r: TranslateResponse = try await state.api.request("/api/agents/\(agent.name)/claude-md-translate", timeout: 120)
            zh = r.translated ?? r.content ?? r.text ?? r.error ?? ""
        } catch { zh = error.localizedDescription }
    }
}

// 新增員工＝網頁 CreateAgentModal（ModalSheet）：✨ 從模板建立 / 🛠️ 自訂
struct CreateAgentModal: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @Environment(\.dismiss) var dismiss
    @State private var tab = 0
    @State private var templates: [AgentTemplate] = []
    @State private var sel: AgentTemplate?
    @State private var persona = ""
    @State private var showPersona = false
    @State private var tplName = ""
    @State private var tplBackend = "claude"
    // 自訂
    @State private var name = ""
    @State private var model = "opus"
    @State private var backend = "claude"
    @State private var title = ""
    @State private var channels = ""
    @State private var claudeMd = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: L("新增員工")) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        modeBtn("✨ " + L("從模板建立"), 0)
                        modeBtn("🛠️ " + L("自訂"), 1)
                    }
                    if tab == 0 { templateSection } else { customSection }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .task {
            if let r: TemplatesResponse = try? await state.api.request("/api/templates") { templates = r.templates ?? [] }
            if let f: FccStatus = try? await state.api.request("/api/setup/fcc-status"), f.chatgpt_connected == true { backend = "claude-codex"; tplBackend = "claude-codex" }
        }
    }
    private func modeBtn(_ t: String, _ i: Int) -> some View {
        Button { withAnimation { tab = i } } label: {
            Text(t).font(WF.sans(13, .bold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(tab == i ? Theme.primary : Theme.surface2).foregroundColor(tab == i ? Color.white : Theme.text2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: 模板
    @ViewBuilder private var templateSection: some View {
        if let t = sel {
            VStack(alignment: .leading, spacing: 12) {
                Button("← " + L("回模板列表")) { sel = nil }.font(WF.sans(13)).foregroundColor(Theme.primary)
                HStack(spacing: 12) {
                    Text(t.icon ?? "🤖").font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name ?? t.id).font(WF.sans(16, .bold)).foregroundColor(Theme.text)
                        Text(t.tagline ?? "").font(WF.sans(12)).foregroundColor(Theme.text2)
                    }
                }
                label(L("幫這位員工命名") + " *")
                TextField(L("例如：小美、客服一號"), text: $tplName).noAutoCap().formField()
                label(L("引擎"))
                Picker("", selection: $tplBackend) {
                    Text(L("Claude（套用此模板的人設＋技能）")).tag("claude")
                    Text(L("用我的 ChatGPT 額度（人設＋技能照樣套用）")).tag("claude-codex")
                    Text(L("Codex（OpenAI · 常駐終端機 TUI · gpt-5.5）")).tag("codex")
                }.pickerStyle(.menu).tint(Theme.text).frame(maxWidth: .infinity, alignment: .leading).formField()
                Text(tplBackend == "codex" ? L("Codex 員工不套模板人設，第一次啟動會在終端機請你登入 ChatGPT。")
                     : tplBackend == "claude-codex" ? L("介面是 Claude，額度吃 ChatGPT Pro；先到「更多 › AI 認證設定」連接 ChatGPT。")
                     : L("需要 Claude 訂閱；首次啟動到終端機登入一次。")).font(WF.sans(11)).foregroundColor(Theme.text3)
                if let tasks = t.sample_tasks, !tasks.isEmpty {
                    label(L("開箱即做的示範任務"))
                    VStack(alignment: .leading, spacing: 4) { ForEach(tasks, id: \.self) { s in Text("• " + s).font(WF.sans(12)).foregroundColor(Theme.text2) } }
                }
                DisclosureGroup(isExpanded: $showPersona) {
                    Text(persona.isEmpty ? L("載入中…") : persona).font(WF.mono(11)).foregroundColor(Theme.text2).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 10))
                } label: { Text(L("預覽完整人設")).font(WF.sans(13, .semibold)).foregroundColor(Theme.text) }
                .tint(Theme.text2)
                .onChange(of: showPersona) { on in if on && persona.isEmpty { Task { await loadPersona(t) } } }
                Button(busy ? L("建立中…") : L("建立並開始工作")) { createFromTemplate(t) }
                    .buttonStyle(WarmButtonStyle(padV: 12, full: true)).disabled(busy || tplName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } else {
            if templates.isEmpty { ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding() }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(templates) { t in
                    Button { sel = t; persona = ""; showPersona = false } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(t.icon ?? "🤖").font(.system(size: 26))
                            Text(t.name ?? t.id).font(WF.sans(14, .bold)).foregroundColor(Theme.text).lineLimit(1)
                            Text(t.tagline ?? "").font(WF.sans(12)).foregroundColor(Theme.text2).lineLimit(2).multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).card(pad: 14)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func loadPersona(_ t: AgentTemplate) async {
        if let r: TemplateDetail = try? await state.api.request("/api/templates/\(t.id)") { persona = r.template?.claude_md ?? "" }
        if persona.isEmpty { persona = L("（無法載入人設）") }
    }
    private func createFromTemplate(_ t: AgentTemplate) {
        busy = true
        Task {
            do {
                let nm = tplName.trimmingCharacters(in: .whitespaces)
                if tplBackend == "codex" {
                    let _: OkResponse = try await state.api.request("/api/agents/create", method: "POST",
                        body: ["name": nm, "backend": "codex", "model": "gpt-5.5", "title": t.tagline ?? "", "claude_md": "", "channels": []], timeout: 60)
                } else {
                    let r: OkResponse = try await state.api.request("/api/agents/from-template", method: "POST",
                        body: ["template_id": t.id, "name": nm, "backend": tplBackend], timeout: 60)
                    if r.ok == false { throw APIError(status: 0, message: r.error ?? L("建立失敗")) }
                }
                await state.refreshState(); Haptic.success(); nav.show(L("已建立") + " " + nm, "success"); dismiss()
            } catch { nav.show(error.localizedDescription, "error") }
            busy = false
        }
    }

    // MARK: 自訂
    private var customSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label(L("名稱") + " *")
            TextField(L("例如：Worker5"), text: $name).noAutoCap().formField()
            label(L("模型"))
            Picker("", selection: $model) {
                Text(L("Opus 4.8（最強，真 1M context）")).tag("opus")
                Text("Sonnet 4.6").tag("sonnet")
                Text("Haiku 4.5").tag("haiku")
            }.pickerStyle(.menu).tint(Theme.text).frame(maxWidth: .infinity, alignment: .leading).formField()
                .disabled(backend == "codex" || backend == "claude-codex").opacity(backend == "codex" || backend == "claude-codex" ? 0.5 : 1)
            label(L("引擎"))
            Picker("", selection: $backend) {
                Text(L("Claude（原生）")).tag("claude")
                Text(L("Claude Code × ChatGPT 額度（介面是 Claude，額度吃 ChatGPT Pro）")).tag("claude-codex")
                Text(L("Codex（OpenAI · 常駐終端機 TUI）")).tag("codex")
                Text(L("free-claude-code 專員（像 CHO，走 proxy 用 GPT 引擎）")).tag("free-claude-code")
            }.pickerStyle(.menu).tint(Theme.text).frame(maxWidth: .infinity, alignment: .leading).formField()
            Text(backend == "codex" ? L("常駐 Codex TUI，模型固定 gpt-5.5；第一次啟動到終端機登入 ChatGPT。")
                 : backend == "claude-codex" ? L("先到「更多 › AI 認證設定」連接 ChatGPT，這位員工就吃你的 ChatGPT 額度。")
                 : backend == "free-claude-code" ? L("走 proxy 用 GPT 引擎，不需 Claude 訂閱。")
                 : L("需要 Claude 訂閱；首次啟動到終端機登入一次。")).font(WF.sans(11)).foregroundColor(Theme.text3)
            label(L("職稱"))
            TextField(L("例如：頻道產線員工"), text: $title).formField()
            label(L("頻道（逗號分隔）"))
            TextField("discord, telegram", text: $channels).noAutoCap().formField()
            label("CLAUDE.md")
            TextEditor(text: $claudeMd).font(WF.mono(12)).foregroundColor(Theme.text).scrollContentBackground(.hidden)
                .frame(minHeight: 140).padding(8).background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
                .overlay(alignment: .topLeading) { if claudeMd.isEmpty { Text(L("Agent 的基礎指令...")).font(WF.mono(12)).foregroundColor(Theme.text3).padding(14).allowsHitTesting(false) } }
            Button(busy ? L("建立中…") : L("建立 Agent")) { createCustom() }
                .buttonStyle(WarmButtonStyle(padV: 12, full: true)).disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
    private func createCustom() {
        busy = true
        Task {
            do {
                let ch = channels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let r: OkResponse = try await state.api.request("/api/agents/create", method: "POST",
                    body: ["name": name.trimmingCharacters(in: .whitespaces), "model": backend == "codex" ? "gpt-5.5" : model,
                           "title": title, "claude_md": claudeMd, "channels": ch, "backend": backend], timeout: 60)
                if r.ok == false { throw APIError(status: 0, message: r.error ?? L("建立失敗")) }
                await state.refreshState(); Haptic.success(); nav.show(L("已建立"), "success"); dismiss()
            } catch { nav.show(error.localizedDescription, "error") }
            busy = false
        }
    }
    private func label(_ t: String) -> some View { Text(t).font(WF.sans(12, .semibold)).foregroundColor(Theme.text2) }
}
