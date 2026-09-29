import SwiftUI
import AVKit

// 子頁 A：Token 用量／備份管理／搜尋／知識庫／影片成品區（皆由 SubPageHost 提供 ← 返回列）

// MARK: - Token 用量 (7天)
struct UsagePage: View {
    @EnvironmentObject var state: AppState
    @State private var agents: [UsageAgent] = []
    @State private var loading = true
    @State private var err: String?
    @State private var open: Set<String> = []
    private func cost(_ a: UsageAgent) -> Double { (a.input ?? 0) + (a.output ?? 0) + ((a.cache_create ?? 0) + (a.cache_read ?? 0)) / 10 }
    private var sumIn: Double { agents.reduce(0) { $0 + ($1.input ?? 0) } }
    private var sumOut: Double { agents.reduce(0) { $0 + ($1.output ?? 0) } }
    private var sumCache: Double { agents.reduce(0) { $0 + ($1.cache_create ?? 0) + ($1.cache_read ?? 0) } }
    private var sumCalls: Double { agents.reduce(0) { $0 + ($1.calls ?? 0) } }
    private var totalCost: Double { agents.reduce(0) { $0 + cost($1) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading && agents.isEmpty { ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding(40) }
                else if let err, agents.isEmpty { Text(err).font(WF.sans(13)).foregroundColor(Theme.danger) }
                else {
                    HStack(spacing: 10) {
                        summary("Input", sumIn, Color(hex: 0x5b8fd6))
                        summary("Output", sumOut, Theme.success)
                        summary("Cache", sumCache, Color(hex: 0x8b5cf6))
                    }
                    UsageCard(title: "🧮 " + L("全部員工加總"), input: sumIn, output: sumOut, cache: sumCache, calls: sumCalls, pct: nil, perHour: mergedHours, expanded: open.contains("__all__")) { toggle("__all__") }
                    ForEach(agents.sorted { cost($0) > cost($1) }, id: \.name) { a in
                        UsageCard(title: a.name, input: a.input ?? 0, output: a.output ?? 0, cache: (a.cache_create ?? 0) + (a.cache_read ?? 0), calls: a.calls ?? 0,
                                  pct: totalCost > 0 ? cost(a) / totalCost : 0, perHour: a.per_hour ?? [:], expanded: open.contains(a.name)) { toggle(a.name) }
                    }
                    if agents.isEmpty { EmptyState(icon: "📊", title: L("尚無用量資料"), subtitle: "") }
                }
            }.pageBody()
        }
        .background(Theme.bg.ignoresSafeArea())
        .refreshable { await load() }
        .task { await load() }
    }
    private func toggle(_ k: String) { if open.contains(k) { open.remove(k) } else { open.insert(k) } }
    private var mergedHours: [String: HourBucket] {
        var m: [String: HourBucket] = [:]
        for a in agents { for (k, v) in a.per_hour ?? [:] {
            var b = m[k] ?? HourBucket()
            b.input = (b.input ?? 0) + (v.input ?? 0); b.output = (b.output ?? 0) + (v.output ?? 0)
            b.cache_create = (b.cache_create ?? 0) + (v.cache_create ?? 0); b.cache_read = (b.cache_read ?? 0) + (v.cache_read ?? 0); b.calls = (b.calls ?? 0) + (v.calls ?? 0)
            m[k] = b
        } }
        return m
    }
    private func summary(_ label: String, _ v: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(WF.sans(11, .semibold)).foregroundColor(Theme.text2)
            Text(Fmt.tokens(v)).font(WF.serif(20, .semibold)).foregroundColor(c).minimumScaleFactor(0.7).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).card(pad: 12)
    }
    private func load() async {
        loading = true
        do {
            let r: UsageResponse = try await state.api.request("/api/usage?granularity=both&range=7d", timeout: 180)
            agents = r.agents ?? []; err = nil
        } catch { err = error.localizedDescription }
        loading = false
    }
}
struct UsageCard: View {
    let title: String
    let input: Double, output: Double, cache: Double, calls: Double
    let pct: Double?
    let perHour: [String: HourBucket]
    let expanded: Bool
    let onToggle: () -> Void
    private var byDate: [(String, HourBucket, [(String, HourBucket)])] {
        var days: [String: [(String, HourBucket)]] = [:]
        for (k, v) in perHour { let d = String(k.prefix(10)); days[d, default: []].append((k, v)) }
        return days.keys.sorted(by: >).map { d in
            let hours = days[d]!.sorted { $0.0 > $1.0 }
            var tot = HourBucket()
            for (_, h) in hours { tot.input = (tot.input ?? 0) + (h.input ?? 0); tot.output = (tot.output ?? 0) + (h.output ?? 0); tot.cache_create = (tot.cache_create ?? 0) + (h.cache_create ?? 0); tot.cache_read = (tot.cache_read ?? 0) + (h.cache_read ?? 0); tot.calls = (tot.calls ?? 0) + (h.calls ?? 0) }
            return (d, tot, hours)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack {
                    Text(title).font(WF.sans(14, .bold)).foregroundColor(Theme.text)
                    Spacer()
                    if let pct { Text(String(format: "%.0f%%", pct * 100)).font(WF.mono(12, .semibold)).foregroundColor(Theme.primary) }
                    Text(expanded ? "▾" : "▸").foregroundColor(Theme.text3)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if let pct {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface2)
                        Capsule().fill(LinearGradient(colors: [Theme.primary, Color(hex: 0xe07040)], startPoint: .leading, endPoint: .trailing)).frame(width: max(0, g.size.width * pct))
                    }
                }.frame(height: 6)
            }
            Text(L("近 7 天總計")).font(WF.sans(11)).foregroundColor(Theme.text3)
            HStack(spacing: 14) {
                stat("In", input); stat("Out", output); stat("Cache", cache); stat("calls", calls)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(byDate, id: \.0) { item in
                        DrillDay(date: item.0, total: item.1, hours: item.2)
                    }
                    if byDate.isEmpty { Text(L("無逐時資料")).font(WF.sans(12)).foregroundColor(Theme.text3) }
                }.padding(.top, 4)
            }
        }.card()
    }
    private func stat(_ l: String, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l).font(WF.mono(10, .semibold)).foregroundColor(Theme.text3)
            Text(Fmt.tokens(v)).font(WF.sans(13, .semibold)).foregroundColor(Theme.text)
        }
    }
}
struct DrillDay: View {
    let date: String
    let total: HourBucket
    let hours: [(String, HourBucket)]
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation { open.toggle() } } label: {
                HStack {
                    Text(date).font(WF.mono(12, .semibold)).foregroundColor(Theme.text)
                    Spacer()
                    Text("In \(Fmt.tokens(total.input ?? 0)) · Out \(Fmt.tokens(total.output ?? 0)) · \(Int(total.calls ?? 0)) calls").font(WF.sans(11)).foregroundColor(Theme.text2)
                    Text(open ? "▾" : "▸").foregroundColor(Theme.text3)
                }.padding(8).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open {
                ForEach(hours, id: \.0) { item in
                    let k = item.0, h = item.1
                    HStack {
                        Text(String(k.suffix(5))).font(WF.mono(11)).foregroundColor(Theme.text2)
                        Spacer()
                        Text("In \(Fmt.tokens(h.input ?? 0)) · Out \(Fmt.tokens(h.output ?? 0)) · Cache \(Fmt.tokens((h.cache_create ?? 0) + (h.cache_read ?? 0))) · \(Int(h.calls ?? 0))").font(WF.sans(11)).foregroundColor(Theme.text3)
                    }.padding(.leading, 12)
                }
            }
        }
    }
}

// MARK: - 備份管理
struct BackupPage: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var nav: Nav
    @State private var items: [BackupItem] = []
    @State private var status: BackupStatus?
    @State private var busy = false
    @State private var confirmRestore: BackupItem?
    @State private var confirmDelete: BackupItem?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    PageTitle(L("備份管理"))
                    Spacer()
                    Button(busy ? L("備份中...") : L("立即備份")) { create() }.buttonStyle(WarmButtonStyle(padV: 8, padH: 14, size: 13)).disabled(busy)
                }
                HStack(spacing: 10) {
                    Circle().fill(status?.running == true ? Theme.success : Theme.text3).frame(width: 10, height: 10)
                    Text(L("自動備份") + " " + (status?.running == true ? L("已啟用") : L("已停用"))).font(WF.sans(13, .semibold)).foregroundColor(Theme.text)
                    Spacer()
                    Text(L("共") + " \(status?.total_backups ?? items.count) " + L("份")).font(WF.sans(12)).foregroundColor(Theme.text2)
                }.card()
                if items.isEmpty { EmptyState(icon: "💾", title: L("尚無備份"), subtitle: "") }
                ForEach(items) { b in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(b.iso.map { Fmt.isoFull($0) } ?? (b.timestamp ?? "")).font(WF.mono(12, .semibold)).foregroundColor(Theme.text)
                            Spacer()
                            Chip((b.label ?? "").contains("auto") ? L("自動") : L("手動"), (b.label ?? "").contains("auto") ? .info : .ai)
                        }
                        Text("\(b.agents ?? 0) agents | \(b.files ?? 0) files | \(String(format: "%.1f", b.size_mb ?? 0)) MB").font(WF.sans(12)).foregroundColor(Theme.text2)
                        HStack(spacing: 8) {
                            Button(L("還原")) { confirmRestore = b }.buttonStyle(SoftButtonStyle(padV: 8, padH: 14, size: 12, bg: Color(hex: 0x5b8fd6, alpha: 0.12), fg: Color(hex: 0x5b8fd6)))
                            Button(L("刪除")) { confirmDelete = b }.buttonStyle(SoftButtonStyle(padV: 8, padH: 14, size: 12, bg: Color(hex: 0xb5341a, alpha: 0.1), fg: Theme.tagError))
                        }
                    }.card()
                }
            }.pageBody()
        }
        .background(Theme.bg.ignoresSafeArea())
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(L("確定要還原此備份？這會覆蓋現有設定檔。"), isPresented: Binding(get: { confirmRestore != nil }, set: { if !$0 { confirmRestore = nil } }), titleVisibility: .visible) {
            Button(L("還原"), role: .destructive) { if let b = confirmRestore { act("/api/backup/restore", ["zip_path": zipPath(b), "restore_sessions": false], L("已還原")) }; confirmRestore = nil }
        }
        .confirmationDialog(L("確定要刪除此備份？"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button(L("刪除"), role: .destructive) { if let b = confirmDelete { act("/api/backup/delete", ["zip_path": zipPath(b)], L("已刪除")) }; confirmDelete = nil }
        }
    }
    private func zipPath(_ b: BackupItem) -> String { ((status?.backup_dir ?? "") as NSString).appendingPathComponent((b.label ?? b.timestamp ?? "") + ".zip") }
    private func load() async {
        if let r: BackupList = try? await state.api.request("/api/backup/list") { items = r.backups ?? [] }
        if let s: BackupStatus = try? await state.api.request("/api/backup/status") { status = s }
    }
    private func create() {
        busy = true
        Task {
            do { let _: OkResponse = try await state.api.request("/api/backup/create", method: "POST", body: ["include_sessions": true], timeout: 120); nav.show(L("備份完成"), "success"); Haptic.success() }
            catch { nav.show(error.localizedDescription, "error") }
            await load(); busy = false
        }
    }
    private func act(_ path: String, _ body: [String: Any], _ okMsg: String) {
        Task {
            do { let r: OkResponse = try await state.api.request(path, method: "POST", body: body, timeout: 120); if r.ok == false { nav.show(r.error ?? L("失敗"), "error") } else { nav.show(okMsg, "success") } }
            catch { nav.show(error.localizedDescription, "error") }
            await load()
        }
    }
}

// MARK: - 搜尋
struct SearchPage: View {
    @EnvironmentObject var state: AppState
    @State private var q = ""
    @State private var hits: [SearchHit] = []
    @State private var searched = false
    @State private var busy = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField(L("搜尋所有日誌..."), text: $q).inputWarm(padV: 12, padH: 14, size: 14).submitLabel(.search).onSubmit { run() }
                Button(L("搜尋")) { run() }.buttonStyle(WarmButtonStyle(padV: 12, padH: 16, size: 13)).disabled(busy || q.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(.horizontal, 16).padding(.vertical, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if busy { ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding(30) }
                    else if !searched { EmptyState(icon: "🔍", title: L("輸入關鍵字開始搜尋"), subtitle: L("可搜尋 Discord 訊息及 Agent 工作階段紀錄")) }
                    else if hits.isEmpty { EmptyState(icon: "🔍", title: L("無搜尋結果"), subtitle: L("嘗試不同的關鍵字")) }
                    ForEach(Array(hits.enumerated()), id: \.offset) { _, h in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Chip(h.source == "discord" ? "Discord" : "Session", h.source == "discord" ? .ai : .info)
                                Text(h.agent ?? "").font(WF.sans(12, .semibold)).foregroundColor(Theme.text)
                                if let c = h.channel_name { Text("#" + c).font(WF.sans(11)).foregroundColor(Theme.text2) }
                                Spacer()
                                Text(h.ts.map { Fmt.isoShort($0) } ?? "").font(WF.mono(10)).foregroundColor(Theme.text3)
                            }
                            if let a = h.author { Text(a).font(WF.sans(11, .semibold)).foregroundColor(Theme.text2) }
                            Text(highlight(h.snippet ?? "")).font(WF.sans(13)).foregroundColor(Theme.text)
                        }.card()
                    }
                }.padding(.horizontal, 16).padding(.bottom, 110)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
    private func highlight(_ s: String) -> AttributedString {
        var out = AttributedString()
        var rest = Substring(s)
        while let r = rest.range(of: "<<") {
            out += AttributedString(String(rest[rest.startIndex..<r.lowerBound]))
            rest = rest[r.upperBound...]
            if let e = rest.range(of: ">>") {
                var m = AttributedString(String(rest[rest.startIndex..<e.lowerBound])); m.backgroundColor = Theme.primary.opacity(0.25); m.font = WF.sans(13, .bold)
                out += m; rest = rest[e.upperBound...]
            } else { break }
        }
        out += AttributedString(String(rest))
        return out
    }
    private func run() {
        let s = q.trimmingCharacters(in: .whitespaces); guard !s.isEmpty else { return }
        busy = true
        Task {
            let enc = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
            if let r: SearchResponse = try? await state.api.request("/api/search?q=\(enc)&limit=20", timeout: 60) { hits = r.results ?? [] } else { hits = [] }
            searched = true; busy = false
        }
    }
}

// MARK: - 知識庫
struct KnowledgePage: View {
    @EnvironmentObject var state: AppState
    @State private var path = ""
    @State private var files: [KnowledgeFile] = []
    @State private var loading = false
    @State private var viewing: KnowledgeFile?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageTitle(L("知識庫"))
                HStack(spacing: 8) {
                    Button("🏠 " + L("根目錄")) { path = ""; Task { await load() } }.buttonStyle(SoftButtonStyle(padV: 6, padH: 12, size: 12))
                    if !path.isEmpty { Button("⬆️ " + L("上一層")) { up() }.buttonStyle(SoftButtonStyle(padV: 6, padH: 12, size: 12)) }
                    Text("/" + path).font(WF.mono(11)).foregroundColor(Theme.text2).lineLimit(1).truncationMode(.head)
                    Spacer()
                }
                if loading { ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding(30) }
                else if files.isEmpty { EmptyState(icon: "📚", title: L("這裡是空的"), subtitle: "") }
                VStack(spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { i, f in
                        Button { tap(f) } label: {
                            HStack(spacing: 12) {
                                Text(icon(f)).font(.system(size: 20)).frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.name).font(WF.sans(14, .medium)).foregroundColor(Theme.text).lineLimit(1)
                                    Text(f.type == "folder" ? L("資料夾 · 點擊進入") : "\(f.size ?? 0) bytes · " + L("點擊檢視")).font(WF.sans(12)).foregroundColor(Theme.text2)
                                }
                                Spacer()
                                Text(f.type == "folder" ? "›" : "👁").foregroundColor(Theme.text3)
                            }.padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if i < files.count - 1 { Divider().overlay(Theme.border).padding(.leading, 60) }
                    }
                }.card(pad: 0)
            }.pageBody()
        }
        .background(Theme.bg.ignoresSafeArea())
        .task { await load() }
        .sheet(item: $viewing) { f in KnowledgeViewer(file: f) }
    }
    private func icon(_ f: KnowledgeFile) -> String {
        if f.type == "folder" { return "📁" }
        let n = f.name.lowercased()
        if n.hasSuffix(".md") { return "📝" }; if n.hasSuffix(".py") { return "🐍" }; if n.hasSuffix(".json") { return "🧩" }
        return "📄"
    }
    private func tap(_ f: KnowledgeFile) {
        if f.type == "folder" { path = f.path ?? ((path.isEmpty ? "" : path + "/") + f.name); Task { await load() } }
        else { viewing = f }
    }
    private func up() {
        var parts = path.split(separator: "/").map(String.init); if !parts.isEmpty { parts.removeLast() }
        path = parts.joined(separator: "/"); Task { await load() }
    }
    private func load() async {
        loading = true
        let enc = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        if let r: KnowledgeFiles = try? await state.api.request("/api/knowledge/files?path=\(enc)") { files = r.files ?? [] } else { files = [] }
        loading = false
    }
}
struct KnowledgeViewer: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    let file: KnowledgeFile
    @State private var content: String?
    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: file.name) { dismiss() }
            ScrollView([.vertical, .horizontal]) {
                Text(content ?? L("載入中…")).font(WF.mono(12.5)).foregroundColor(Theme.text).textSelection(.enabled).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .task {
            let a = (file.agent ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let p = (file.path ?? file.name).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let r: KnowledgeRead = try? await state.api.request("/api/knowledge/read?agent=\(a)&path=\(p)") { content = r.content ?? "" } else { content = L("讀取失敗") }
        }
    }
}

// MARK: - 影片成品區
struct ProductsPage: View {
    @EnvironmentObject var state: AppState
    @State private var tree: ProductsTree?
    @State private var station: ProductStation?
    @State private var err: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Button { station = nil } label: { PageTitle(L("影片成品區")) }.buttonStyle(.plain)
                    if let s = station { Text("› " + s.name).font(WF.sans(15, .semibold)).foregroundColor(Theme.text2).lineLimit(1) }
                }
                if let tree {
                    if let s = station { StationBody(station: s, mediaBase: tree.media_base ?? "") }
                    else if tree.stations.isEmpty { EmptyState(icon: "🎞️", title: L("還沒有成品"), subtitle: "") }
                    else {
                        ForEach(tree.stations) { s in
                            Button { station = s } label: {
                                HStack(spacing: 12) {
                                    Text("🎞️").font(.system(size: 22))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.name).font(WF.sans(15, .bold)).foregroundColor(Theme.text)
                                        Text(L("最新") + " \(s.latest ?? "—") · \(s.video_count ?? 0) " + L("部影片") + " · \(s.image_count ?? 0) " + L("張圖")).font(WF.sans(12)).foregroundColor(Theme.text2)
                                    }
                                    Spacer()
                                    Text("›").foregroundColor(Theme.text3)
                                }.card()
                            }.buttonStyle(.plain)
                        }
                    }
                } else if let err { Text(err).font(WF.sans(13)).foregroundColor(Theme.danger) }
                else { ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding(40) }
            }.pageBody()
        }
        .background(Theme.bg.ignoresSafeArea())
        .task {
            do { tree = try await state.api.request("/api/products/tree", timeout: 60) } catch { err = error.localizedDescription }
        }
    }
}
struct StationBody: View {
    @EnvironmentObject var state: AppState
    let station: ProductStation
    let mediaBase: String
    @State private var playing: ProductFile?
    @State private var lightbox: ProductFile?
    private var dlBase: String {
        let host = state.api.url("/").host ?? ""
        return host.hasSuffix(".ts.net") ? "https://\(host):10000" : "http://\(host):8899"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(station.dates ?? []) { d in
                VStack(alignment: .leading, spacing: 8) {
                    Text(d.date.uppercased()).font(WF.sans(12, .bold)).foregroundColor(Theme.text2)
                    if let t = d.title, !t.isEmpty { Text(t).font(WF.sans(14, .semibold)).foregroundColor(Theme.text) }
                    ForEach(d.videos) { v in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Button { playing = playing == v ? nil : v } label: {
                                    HStack(spacing: 8) {
                                        Text(playing == v ? "⏸️" : "▶️").font(.system(size: 18))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(v.name).font(WF.sans(13, .semibold)).foregroundColor(Theme.text).lineLimit(2)
                                            Text(Fmt.bytes(v.size ?? 0)).font(WF.sans(11)).foregroundColor(Theme.text2)
                                        }
                                        Spacer()
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button {
                                    let enc = v.rel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? v.rel
                                    if let u = URL(string: dlBase + "/dl/" + enc) { UIApplication.shared.open(u) }
                                } label: { Text("⬇️").font(.system(size: 18)).frame(width: 44, height: 44).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 12)) }
                            }
                            if playing == v, let u = state.api.mediaURL(v.rel, base: mediaBase) {
                                InlineVideo(url: u).frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }.card(pad: 12)
                    }
                    if !d.images.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(d.images) { im in
                                Button { lightbox = im } label: {
                                    AsyncImage(url: state.api.mediaURL(im.rel, base: mediaBase)) { $0.resizable().scaledToFill() } placeholder: { Theme.surface2 }
                                        .aspectRatio(16/10, contentMode: .fill).clipShape(RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            if (station.dates ?? []).isEmpty { EmptyState(icon: "🎞️", title: L("還沒有成品"), subtitle: "") }
        }
        .fullScreenCover(item: $lightbox) { im in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                AsyncImage(url: state.api.mediaURL(im.rel, base: mediaBase)) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) }
                Button { lightbox = nil } label: { Text("✕").font(WF.sans(22)).foregroundColor(.white).padding(20) }
            }
        }
    }
}
