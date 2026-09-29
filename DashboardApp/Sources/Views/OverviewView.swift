import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var l10n: L10n
    var goTab: (Int) -> Void
    private let quota: Double = 5_000_000   // 網頁版寫死的配額常數

    var running: [Agent] { state.agents.filter { $0.isRunning } }
    var authErr: [Agent] { running.filter { $0.hasAuthError } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if state.offline {
                        Label(L("common.offline"), systemImage: "wifi.slash").font(.footnote).foregroundColor(Theme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                    }
                    if !authErr.isEmpty {
                        Button { goTab(2) } label: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.warning)
                                Text("\(authErr.count) \(L("ov.autherr"))").font(.footnote).foregroundColor(Theme.text)
                                Spacer(); Image(systemName: "chevron.right").foregroundColor(Theme.muted)
                            }.card(pad: 12)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        kpi(L("ov.running"), "\(running.count)/\(state.agents.count)", icon: "bolt.fill", color: Theme.success)
                        kpi(L("ov.tokens"), state.usage.isEmpty ? (state.usageLoading ? "…" : "—") : Fmt.tokens(state.tokens7d), icon: "cpu", color: Theme.primary)
                        kpi(L("ov.uptime"), state.agents.isEmpty ? "—" : "\(Int((Double(running.count) / Double(state.agents.count) * 100).rounded()))%", icon: "waveform.path.ecg", color: Theme.accent)
                        kpi(L("ov.total"), "\(state.agents.count)", icon: "person.3.fill", color: Theme.warning)
                    }
                    quotaCard
                    systemCard
                    activeCard
                    recentChats
                }
                .padding(16)
            }
            .screenBackground()
            .refreshable { await state.refreshAll(); await state.refreshUsage() }
            .navigationTitle(L("tab.overview"))
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func kpi(_ title: String, _ value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: icon).foregroundColor(color); Spacer() }
            StatNumber(value: value, size: 26)
            Text(title).font(.caption).foregroundColor(Theme.muted).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var quotaCard: some View {
        let used = state.tokens7d
        let pct = min(1, used / quota)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("ov.quota")).font(.subheadline.weight(.semibold)).foregroundColor(Theme.text)
                Spacer()
                Text(state.usage.isEmpty ? L("ov.usage.wait") : "\(Int((pct * 100).rounded()))%").font(.caption).foregroundColor(Theme.muted)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2)
                    Capsule().fill(pct > 0.9 ? Theme.danger : Theme.primary).frame(width: max(4, g.size.width * pct))
                }
            }.frame(height: 8)
            Text("\(Int(used).formatted()) / \(Int(quota).formatted())").font(.caption2).foregroundColor(Theme.muted).monospacedDigit()
        }.card()
    }

    private var systemCard: some View {
        HStack(spacing: 12) {
            Circle().fill(running.isEmpty ? Theme.muted : Theme.success).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(running.isEmpty ? L("ov.none") : L("ov.allok")).font(.subheadline.weight(.semibold)).foregroundColor(Theme.text)
                HStack(spacing: 10) {
                    if let v = state.health?.version { Text("v\(v)") }
                    if let u = state.health?.uptime_seconds { Text("\(L("ov.up")) \(Fmt.uptime(u))") }
                    if !state.env.isEmpty { Text(state.env) }
                }.font(.caption).foregroundColor(Theme.muted)
            }
            Spacer()
            Text(URL(string: state.baseString)?.host ?? "").font(.caption2).foregroundColor(Theme.muted).lineLimit(1).frame(maxWidth: 120)
        }.card()
    }

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("ov.active")).font(.subheadline.weight(.semibold)).foregroundColor(Theme.text)
                Spacer()
                Button(L("tab.agents")) { goTab(1) }.font(.caption)
            }
            if running.isEmpty {
                Text(L("common.none")).font(.footnote).foregroundColor(Theme.muted)
            } else {
                ForEach(state.sortedAgents.filter { $0.isRunning }.prefix(12)) { a in
                    HStack(spacing: 10) {
                        StatusDot(running: true, error: a.hasAuthError)
                        Text(a.name).font(.subheadline).foregroundColor(Theme.text)
                        if a.isBusy { Pill(text: L("ag.busy"), color: Theme.primary) }
                        Spacer()
                        Text(a.engineLabel).font(.caption2).foregroundColor(Theme.muted).lineLimit(1)
                    }
                }
            }
        }.card()
    }

    private var recentChats: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("ov.recent")).font(.subheadline.weight(.semibold)).foregroundColor(Theme.text)
                Spacer()
                Button(L("tab.chat")) { goTab(3) }.font(.caption)
            }
            ForEach(state.groups.prefix(4)) { g in
                Button { goTab(3) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).font(.subheadline.weight(.medium)).foregroundColor(Theme.text)
                            Text("\(g.last_sender ?? ""): \(g.last_preview ?? "")").font(.caption).foregroundColor(Theme.muted).lineLimit(2)
                        }
                        Spacer()
                        Text(Fmt.when(g.last_ts)).font(.caption2).foregroundColor(Theme.muted)
                    }
                }
            }
        }.card()
    }
}
