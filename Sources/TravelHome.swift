import SwiftUI

/// 旅遊模式（董事長 2026-09-03 圈定 7 功能）：說書導遊／掃描菜單／行程管家／
/// 交通領航／雙向翻譯／旅費帳房／旅行日記。全部掛在克拉扣即時通道上；
/// 未配 relay 金鑰時各功能以「示範資料」呈現（畫面照常、標示示範）。
struct TravelHome: View {
    @Environment(\.colorScheme) private var scheme
    // CI 截圖：-travelFeature menu 直接深入該功能頁
    @State private var path: [String] = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-travelFeature"), i + 1 < args.count { return [args[i + 1]] }
        return []
    }()

    private let features: [TravelFeature] = [
        .init(id: "guide", title: "說書導遊", sub: "看到哪講到哪，用我們自己的故事庫", icon: "book.fill", tint: Color(hex: 0xF59E0B)),
        .init(id: "menu", title: "掃描菜單", sub: "按一下拍菜單，直接變中文菜單", icon: "doc.text.viewfinder", tint: Color(hex: 0xEF4444)),
        .init(id: "plan", title: "行程管家", sub: "退房、機場、延誤，主動提醒", icon: "calendar.badge.clock", tint: Color(hex: 0x22C55E)),
        .init(id: "transit", title: "交通領航", sub: "下一班・幾號出口・末班倒數", icon: "tram.fill", tint: Color(hex: 0x38BDF8)),
        .init(id: "talk", title: "雙向翻譯", sub: "跟當地人對話，雙向字幕", icon: "bubble.left.and.bubble.right.fill", tint: Color(hex: 0xA78BFA)),
        .init(id: "money", title: "旅費帳房", sub: "講一聲就記帳＋匯率＋日結", icon: "yensign.circle.fill", tint: Color(hex: 0xF472B6)),
        .init(id: "diary", title: "旅行日記", sub: "一天走過的路，自動編成影片", icon: "film.stack", tint: Color(hex: 0x34D399)),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    banner
                    ForEach(features) { f in
                        NavigationLink(value: f.id) { card(f) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Theme.ground(scheme))
            .navigationDestination(for: String.self) { destination($0) }
        }
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.travel)
            VStack(alignment: .leading, spacing: 2) {
                Text("旅遊模式").font(Theme.display(18)).foregroundStyle(Theme.ink(scheme))
                Text(AppConfig.hasRelayKey ? "克拉扣即時連線中" : "示範模式（未配金鑰）")
                    .font(Theme.body(11)).foregroundStyle(Theme.inkDim(scheme))
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.travel.opacity(0.12)))
    }

    private func card(_ f: TravelFeature) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(f.tint.opacity(0.18)).frame(width: 44, height: 44)
                Image(systemName: f.icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(f.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(f.title).font(Theme.title(16)).foregroundStyle(Theme.ink(scheme))
                Text(f.sub).font(Theme.body(12)).foregroundStyle(Theme.inkDim(scheme))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.inkDim(scheme))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface(scheme)))
    }

    @ViewBuilder private func destination(_ id: String) -> some View {
        switch id {
        case "guide": GuideView()
        case "menu": MenuScanView()
        case "plan": ItineraryView()
        case "transit": TransitView()
        case "talk": TranslateView()
        case "money": ExpenseView()
        default: DiaryView()
        }
    }
}

struct TravelFeature: Identifiable {
    let id: String, title: String, sub: String, icon: String
    let tint: Color
}

// MARK: - 1 說書導遊

struct GuideView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var story: String?
    @State private var loading = false
    @State private var picked: String?

    private let spots = [
        ("淺草寺雷門", "659年建，現在的門是松下幸之助1960年捐的——原門被燒了95年沒人重建"),
        ("澀谷十字路口", "一次綠燈最多3000人同時過街——這裡曾是澀谷川的河道，川還在腳下流"),
        ("東京鐵塔", "三分之一的鋼材來自韓戰報廢的美軍戰車——蓋它的工人有人穿草鞋上工"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("附近").font(Theme.label(13)).foregroundStyle(Theme.inkDim(scheme))
                ForEach(spots, id: \.0) { s in
                    Button { tell(s.0, s.1) } label: {
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(Color(hex: 0xF59E0B))
                            Text(s.0).font(Theme.title(15)).foregroundStyle(Theme.ink(scheme))
                            Spacer()
                            if loading && picked == s.0 { ProgressView().controlSize(.small) }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface(scheme)))
                    }
                    .buttonStyle(.plain)
                }
                if let story {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(picked ?? "", systemImage: "book.fill")
                            .font(Theme.label(13)).foregroundStyle(Color(hex: 0xF59E0B))
                        Text(story).font(Theme.body(15)).foregroundStyle(Theme.ink(scheme))
                            .lineSpacing(4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0xF59E0B).opacity(0.10)))
                }
            }
            .padding(16)
        }
        .background(Theme.ground(scheme))
        .navigationTitle("說書導遊")
    }

    private func tell(_ name: String, _ demo: String) {
        picked = name; story = nil; loading = true
        Task {
            defer { loading = false }
            if AppConfig.hasRelayKey {
                let r = try? await RelayClient(authKey: AppConfig.authKey)
                    .ask("導遊模式：我人在\(name)，用說書的方式講一段這裡最反常識的故事")
                story = (r?.isEmpty == false ? r : demo)
            } else {
                try? await Task.sleep(nanoseconds: 600_000_000)
                story = demo + "（示範段落，連線後由克拉扣即時說書）"
            }
        }
    }
}

// MARK: - 3 行程管家

struct ItineraryView: View {
    @Environment(\.colorScheme) private var scheme
    private let items: [(String, String, String, Bool)] = [
        ("09:00", "飯店退房", "行李寄櫃台，拿收據", false),
        ("10:30", "築地場外市場", "人多，先吃玉子燒排隊短", false),
        ("14:00", "回飯店取行李", "預留 40 分鐘車程", true),
        ("16:45", "羽田機場 T3 報到", "CI223 19:05 起飛・目前準點", true),
    ]
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(items, id: \.0) { it in
                    HStack(alignment: .top, spacing: 12) {
                        Text(it.0).font(Theme.title(15)).monospacedDigit()
                            .foregroundStyle(it.3 ? Color(hex: 0x22C55E) : Theme.inkDim(scheme))
                            .frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(it.1).font(Theme.title(15)).foregroundStyle(Theme.ink(scheme))
                            Text(it.2).font(Theme.body(12)).foregroundStyle(Theme.inkDim(scheme))
                        }
                        Spacer()
                        if it.3 { Image(systemName: "bell.badge.fill").foregroundStyle(Color(hex: 0x22C55E)) }
                    }
                    .padding(13)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface(scheme)))
                }
                Label("延誤／登機門變更會主動彈上眼鏡（示範行程）", systemImage: "sparkles")
                    .font(Theme.body(12)).foregroundStyle(Theme.inkDim(scheme))
            }
            .padding(16)
        }
        .background(Theme.ground(scheme))
        .navigationTitle("行程管家")
    }
}

// MARK: - 4 交通領航

struct TransitView: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("銀座線・澀谷方向", systemImage: "tram.fill")
                        .font(Theme.label(13)).foregroundStyle(Color(hex: 0x38BDF8))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("3").font(Theme.display(40)).foregroundStyle(Theme.ink(scheme)).monospacedDigit()
                        Text("分後進站").font(Theme.body(14)).foregroundStyle(Theme.inkDim(scheme))
                        Spacer()
                        Text("下一班 9 分").font(Theme.body(13)).foregroundStyle(Theme.inkDim(scheme))
                    }
                    Divider()
                    Label("往淺草寺 → A4 出口最近", systemImage: "figure.walk")
                        .font(Theme.body(14)).foregroundStyle(Theme.ink(scheme))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface(scheme)))

                HStack {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(Color(hex: 0xF59E0B))
                    Text("末班車 00:12 ・ 還有 2 小時 41 分")
                        .font(Theme.title(14)).foregroundStyle(Theme.ink(scheme))
                    Spacer()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: 0xF59E0B).opacity(0.12)))

                Text("示範班次；連線後接即時時刻表").font(Theme.body(11)).foregroundStyle(Theme.inkDim(scheme))
            }
            .padding(16)
        }
        .background(Theme.ground(scheme))
        .navigationTitle("交通領航")
    }
}

// MARK: - 5 雙向翻譯

struct TranslateView: View {
    @Environment(\.colorScheme) private var scheme
    private let lines: [(Bool, String, String)] = [
        (false, "いらっしゃいませ、何名様ですか？", "歡迎光臨，請問幾位？"),
        (true, "兩位，有靠窗的位子嗎？", "2名です。窓際の席はありますか？"),
        (false, "少々お待ちください。", "請稍等一下。"),
    ]
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                        VStack(alignment: l.0 ? .trailing : .leading, spacing: 3) {
                            Text(l.1).font(Theme.title(15)).foregroundStyle(Theme.ink(scheme))
                            Text(l.2).font(Theme.body(13)).foregroundStyle(Color(hex: 0xA78BFA))
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(l.0 ? Color(hex: 0xA78BFA).opacity(0.14) : Theme.surface(scheme)))
                        .frame(maxWidth: .infinity, alignment: l.0 ? .trailing : .leading)
                    }
                    Text("示範對話；正式版兩邊講話即時上字幕")
                        .font(Theme.body(11)).foregroundStyle(Theme.inkDim(scheme))
                }
                .padding(16)
            }
            HStack(spacing: 14) {
                mic("我說中文", Color(hex: 0xA78BFA))
                mic("對方說日文", Color(hex: 0x38BDF8))
            }
            .padding(16)
        }
        .background(Theme.ground(scheme))
        .navigationTitle("雙向翻譯")
    }
    private func mic(_ t: String, _ c: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "mic.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                .frame(width: 54, height: 54).background(Circle().fill(c))
            Text(t).font(Theme.label(11)).foregroundStyle(Theme.inkDim(scheme))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 6 旅費帳房

struct ExpenseView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var input = ""
    @State private var entries: [(String, Int, Int)] = [
        ("拉麵", 1200, 264), ("地鐵一日券", 800, 176), ("淺草寺御守", 500, 110),
    ]
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("今日 ¥\(entries.reduce(0) { $0 + $1.1 })")
                                .font(Theme.display(24)).foregroundStyle(Theme.ink(scheme)).monospacedDigit()
                            Text("≈ NT$\(entries.reduce(0) { $0 + $1.2 })・匯率 0.22（示範）")
                                .font(Theme.body(12)).foregroundStyle(Theme.inkDim(scheme))
                        }
                        Spacer()
                        Image(systemName: "yensign.circle.fill").font(.system(size: 30))
                            .foregroundStyle(Color(hex: 0xF472B6))
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0xF472B6).opacity(0.10)))
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                        HStack {
                            Text(e.0).font(Theme.title(15)).foregroundStyle(Theme.ink(scheme))
                            Spacer()
                            Text("¥\(e.1)").font(Theme.title(15)).monospacedDigit().foregroundStyle(Theme.ink(scheme))
                            Text("NT$\(e.2)").font(Theme.body(12)).monospacedDigit().foregroundStyle(Theme.inkDim(scheme))
                        }
                        .padding(13)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface(scheme)))
                    }
                }
                .padding(16)
            }
            HStack(spacing: 10) {
                TextField("講或打：拉麵 1200", text: $input)
                    .font(Theme.body(15)).padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface(scheme)))
                Button { add() } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Circle().fill(Color(hex: 0xF472B6)))
                }
            }
            .padding(16)
        }
        .background(Theme.ground(scheme))
        .navigationTitle("旅費帳房")
    }
    private func add() {
        let parts = input.split(separator: " ")
        guard parts.count >= 2, let yen = Int(parts.last!) else { return }
        let name = parts.dropLast().joined(separator: " ")
        entries.append((name, yen, Int(Double(yen) * 0.22)))
        input = ""
    }
}

// MARK: - 7 旅行日記

struct DiaryView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var queued = false
    private let moments: [(String, String)] = [
        ("08:12", "築地場外・第一口玉子燒"),
        ("11:40", "淺草雷門・你問了燈籠底下的龍"),
        ("15:03", "澀谷十字路口・一次綠燈 3000 人"),
        ("18:30", "居酒屋・老闆教你唸『樽酒』"),
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(moments, id: \.0) { m in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(Color(hex: 0x34D399)).frame(width: 8, height: 8).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.0).font(Theme.label(12)).foregroundStyle(Theme.inkDim(scheme)).monospacedDigit()
                            Text(m.1).font(Theme.title(15)).foregroundStyle(Theme.ink(scheme))
                        }
                    }
                }
                Button { queued = true } label: {
                    Label(queued ? "已排入・今晚交片" : "把今天編成影片",
                          systemImage: queued ? "checkmark.circle.fill" : "film.stack")
                        .font(Theme.title(15)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(queued ? Color(hex: 0x22C55E) : Color(hex: 0x34D399)))
                }
                .buttonStyle(.plain)
                Text("示範時間軸；正式版自動收路線＋照片＋對話")
                    .font(Theme.body(11)).foregroundStyle(Theme.inkDim(scheme))
            }
            .padding(16)
        }
        .background(Theme.ground(scheme))
        .navigationTitle("旅行日記")
    }
}
