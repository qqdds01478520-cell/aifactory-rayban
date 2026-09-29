import SwiftUI

// 控制總覽＝網頁 OverviewPage：認證過期橫幅、h1 控制總覽＋副標、右側帳號＋角色、4 KPI、TOKEN 配額、活躍員工
struct OverviewView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @EnvironmentObject var l10n: L10n

    var running: [Agent] { state.agents.filter { $0.isRunning } }
    var total: Int { state.agents.count }
    var tokens: Double { state.tokens7d }
    var uptimePct: Int { total == 0 ? 100 : Int((Double(running.count) / Double(total) * 100).rounded()) }
    var quotaPct: Int { min(100, Int((tokens / 5_000_000 * 100).rounded())) }
    var roleLabel: String { state.role == "admin" ? L("管理員") : (state.role == "owner" ? L("擁有者") : L("使用者")) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Spacer(); LanguagePill() }.padding(.top, -8)
                AuthErrorBanner(agents: state.agents)
                header
                kpiGrid
                quotaCard
                activeSection
            }
            .pageBody()
        }
        .refreshable { await state.refreshAll() }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                PageTitle(L("控制總覽"), size: 26)
                Text(running.isEmpty ? L("目前無運行中的 Agent") : L("所有系統運行正常")).font(WF.sans(13)).foregroundColor(Theme.text2)
                if state.offline { Text(L("離線 · 顯示快取")).font(WF.sans(11)).foregroundColor(Theme.warning) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(state.username).font(WF.sans(13, .semibold)).foregroundColor(Theme.text)
                Tag(roleLabel, .info)
            }
        }
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            KpiCard(label: L("運行中員工"), value: "\(running.count)", suffix: "/ \(total)", glow: Color(hex: 0x4a8c5c, alpha: 0.08))
            KpiCard(label: L("TOKEN 用量"), value: state.usage.isEmpty && state.usageLoading ? "—" : Fmt.tokens(tokens), suffix: nil, glow: Color(hex: 0xc25628, alpha: 0.08))
            KpiCard(label: L("正常運行率"), value: "\(uptimePct)", suffix: "%", glow: Color(hex: 0x5a7a65, alpha: 0.08))
            KpiCard(label: L("總員工數"), value: "\(total)", suffix: "agents", glow: Color(hex: 0xc49a2c, alpha: 0.08))
        }
    }

    private var quotaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MonoLabel(L("TOKEN 配額"))
                Spacer()
                Text("\(quotaPct)%").font(WF.sans(13, .semibold)).foregroundColor(Theme.primary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2)
                    Capsule().fill(LinearGradient(colors: [Theme.primary, Color(hex: 0xe07040)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, g.size.width * CGFloat(quotaPct) / 100))
                }
            }.frame(height: 6)
            HStack {
                Text(Fmt.num(tokens)).font(WF.sans(11)).foregroundColor(Theme.text3)
                Spacer()
                Text("5,000,000").font(WF.sans(11)).foregroundColor(Theme.text3)
            }
        }.card()
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MonoLabel(L("活躍員工"))
                Spacer()
                Button { nav.go(.agents) } label: { Text(L("查看全部") + " →").font(WF.sans(12, .medium)).foregroundColor(Theme.primary) }
            }
            VStack(spacing: 0) {
                if running.isEmpty {
                    Text(L("目前沒有運行中的 Agent")).font(WF.sans(13)).foregroundColor(Theme.text3).frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    ForEach(Array(running.enumerated()), id: \.element.id) { i, a in
                        Button { nav.openTerminal(a.name) } label: { AgentRowView(agent: a, showButtons: false) }
                            .buttonStyle(.plain)
                        if i < running.count - 1 { Divider().overlay(Theme.border) }
                    }
                }
            }.card(pad: 0)
        }
    }
}

// .kpi-card：mono-label ＋ 32px 襯線數字 ＋ 12px text-3 後綴 ＋ 右下角光暈
struct KpiCard: View {
    let label: String
    let value: String
    let suffix: String?
    let glow: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(WF.serif(32, .semibold)).foregroundColor(Theme.text).minimumScaleFactor(0.6).lineLimit(1)
                if let suffix { Text(suffix).font(WF.sans(12)).foregroundColor(Theme.text3) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .overlay(alignment: .bottomTrailing) { Circle().fill(glow).frame(width: 50, height: 50).blur(radius: 12).offset(x: 8, y: 8) }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .shadow(color: Theme.shadow, radius: 6, x: 0, y: 2)
    }
}

// Claude 認證已過期 橫幅（#fef3cd / #ffc107 / #856404）
struct AuthErrorBanner: View {
    @EnvironmentObject var nav: Nav
    let agents: [Agent]
    var errAgents: [Agent] { agents.filter { $0.isRunning && $0.hasAuthError } }
    var body: some View {
        if !errAgents.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Text("⚠️").font(.system(size: 20))
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Claude 認證已過期")).font(WF.sans(14, .bold)).foregroundColor(Color(hex: 0x856404))
                    Text(errAgents.map { $0.name }.joined(separator: "、") + " " + L("無法工作。到那位員工的「終端機」分頁，照畫面提示登入一次就會恢復。（憑證是每位員工各自持有的，所以要在他自己的終端機登入。）"))
                        .font(WF.sans(12)).foregroundColor(Color(hex: 0x856404))
                    Button { nav.openTerminal(errAgents[0].name) } label: {
                        Text("💻 " + L("去終端機登入")).font(WF.sans(12, .bold)).foregroundColor(.white)
                            .padding(.vertical, 6).padding(.horizontal, 12).background(Color(hex: 0x856404))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(16)
            .background(Color(hex: 0xfef3cd))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(hex: 0xffc107), lineWidth: 1))
        }
    }
}

// .agent-row：頭像 42 ＋ 名稱 14/600 ＋ 狀態點 ＋ 運算中 ＋ 引擎 mono-label ＋ 職稱 12 text-2 ＋（啟停鈕）＋ ›
struct AgentRowView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    let agent: Agent
    var showButtons: Bool = true
    var busyName: String? = nil
    var onToggle: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 12) {
            AgentAvatar(name: agent.name, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent.name).font(WF.sans(14, .semibold)).foregroundColor(Theme.text).lineLimit(1)
                    if agent.steward == true { Tag(L("管家"), .info) }
                    StatusDot(running: agent.isRunning, error: agent.isRunning && agent.hasAuthError)
                    if agent.isBusy { BusyBadge() }
                }
                MonoLabel(agent.engineLabel.isEmpty ? "N/A" : agent.engineLabel)
                if let t = agent.title, !t.isEmpty { Text(t).font(WF.sans(12)).foregroundColor(Theme.text2).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if showButtons {
                if agent.isRunning && agent.hasAuthError { Tag("⚠️ " + L("認證"), .warning) }
                Button { onToggle?() } label: {
                    Text(busyName == agent.name ? "…" : (agent.isRunning ? L("停止") : L("啟動")))
                        .font(WF.mono(12, .semibold))
                        .foregroundColor(agent.isRunning ? Theme.tagError : Theme.success)
                        .padding(.vertical, 6).padding(.horizontal, 12)
                        .background(agent.isRunning ? Color(hex: 0xb5341a, alpha: 0.1) : Color(hex: 0x4a8c5c, alpha: 0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busyName == agent.name)
            }
            Text("›").font(WF.sans(16)).foregroundColor(Theme.text3)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .contentShape(Rectangle())
    }
}
