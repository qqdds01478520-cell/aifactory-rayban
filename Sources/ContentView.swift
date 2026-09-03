import SwiftUI

/// 克拉扣 OS 手機主畫面（第一批，純 UI、不接眼鏡也能跑）：
/// 頂部品牌列＋即時時鐘，中間功能頁，底部色彩編碼分頁列。
struct ContentView: View {
    @Environment(\.colorScheme) private var scheme
    // 預設 YouTube；CI 截圖時用 launch argument -startTab <youtube|maps|telegram> 指定初始頁，
    // 讓雲端模擬器對每個功能各截一張實際畫面。
    @State private var tab: AppTab = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-startTab"), i + 1 < args.count,
           let t = AppTab(rawValue: args[i + 1]) { return t }
        return .youtube
    }()
    @State private var now = Date()
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.ground(scheme).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                content
                tabBar
            }
        }
        .onReceive(clock) { now = $0 }
        .preferredColorScheme(.dark)
    }

    // 品牌列
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.brand, Theme.brand.opacity(0.7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                Text("克").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(.black)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("克拉扣 OS").font(Theme.display(19)).foregroundStyle(Theme.ink(scheme))
                Text(tab.hint).font(Theme.body(11)).foregroundStyle(Theme.inkDim(scheme))
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(Theme.maps).frame(width: 7, height: 7)
                Text(now, format: .dateTime.hour().minute())
                    .font(Theme.title(16)).monospacedDigit()
                    .foregroundStyle(Theme.ink(scheme))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Theme.surface(scheme)))
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .youtube: YouTubeView()
        case .maps: MapsView()
        case .telegram: TelegramView()
        case .travel: TravelHome()
        case .glasses: GlassesView()
        }
    }

    // 色彩編碼分頁列
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { t in
                let on = t == tab
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tab = t }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon)
                            .font(.system(size: 20, weight: .semibold))
                        Text(t.title).font(Theme.label(11))
                    }
                    .foregroundStyle(on ? t.accent : Theme.inkDim(scheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        ZStack {
                            if on {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(t.accent.opacity(0.14))
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
        .background(
            Theme.surface(scheme)
                .overlay(Rectangle().fill(Theme.line(scheme)).frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

#Preview {
    ContentView()
}
