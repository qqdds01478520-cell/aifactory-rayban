import SwiftUI

@MainActor
final class ChatModel: ObservableObject {
    @Published var messages: [RelayMessage] = []
    @Published var sending = false
    private let client = RelayClient(authKey: AppConfig.authKey)
    private var lastId: Int64 = 0
    private var polling = false

    /// 首開示範對話：內容取自 relay 上真實發生過的語音問答（Siri 捷徑那條已通的路），
    /// 讓一進來就看得到「跟克拉扣對話」長怎樣，而非空狀態。真機連上 relay 後即被即時訊息接續。
    static let seedConversation: [RelayMessage] = [
        .init(id: 1, text: "現在幾點", from: "chairman"),
        .init(id: 2, text: "現在是晚上 9 點 35 分。董事長，捷徑通了，這就是我，克拉扣。", from: "coo"),
        .init(id: 3, text: "今天幾月幾號星期幾", from: "chairman"),
        .init(id: 4, text: "今天是 2026 年 9 月 1 日，星期二。", from: "coo"),
        .init(id: 5, text: "幫我看一下產線狀況", from: "chairman"),
        .init(id: 6, text: "四支片在製：黑盒子長短片 i2v、名人通組裝、老趙重投都在跑，佇列正常，沒有卡死。", from: "coo")
    ]

    init() {
        messages = Self.seedConversation
        // 只拉「開 app 之後」進來的新訊息，不重灌歷史 backlog（正確聊天行為，
        // 也避免示範畫面被舊訊息洗版）。
        lastId = Int64(Date().timeIntervalSince1970 * 1000)
    }

    func refresh() async {
        guard let msgs = try? await client.pullMessages(after: lastId), !msgs.isEmpty else { return }
        for m in msgs where m.id > lastId { lastId = m.id }
        // 合併（避免重複）
        let known = Set(messages.map(\.id))
        messages.append(contentsOf: msgs.filter { !known.contains($0.id) })
    }

    func startPolling() {
        guard !polling else { return }
        polling = true
        Task {
            while polling {
                await refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
    func stopPolling() { polling = false }

    func send(_ text: String) async {
        sending = true; defer { sending = false }
        // 樂觀顯示自己的話
        let mine = RelayMessage(id: Int64(Date().timeIntervalSince1970 * 1000), text: text, from: "chairman")
        messages.append(mine)
        let answer = (try? await client.ask(text)) ?? ""
        if !answer.isEmpty {
            messages.append(RelayMessage(id: mine.id + 1, text: answer, from: "coo"))
        }
    }
}

struct TelegramView: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var model = ChatModel()
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            if model.messages.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(model.messages) { m in bubble(m).id(m.id) }
                        }
                        .padding(16)
                    }
                    .onChange(of: model.messages.count) { _, _ in
                        if let last = model.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
            }

            HStack(spacing: 10) {
                SearchBar(text: $draft, accent: Theme.telegram,
                          placeholder: "跟克拉扣說話…") { text in
                    draft = ""
                    Task { await model.send(text) }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.ground(scheme))
        }
        .task { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    private func bubble(_ m: RelayMessage) -> some View {
        let mine = m.from == "chairman"
        return HStack {
            if mine { Spacer(minLength: 40) }
            Text(m.text)
                .font(Theme.body(16))
                .foregroundStyle(mine ? Color.black : Theme.ink(scheme))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(mine ? Theme.brand : Theme.surface(scheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(mine ? .clear : Theme.line(scheme), lineWidth: 1)
                        )
                )
            if !mine { Spacer(minLength: 40) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "paperplane.fill")
                .font(.system(size: 44)).foregroundStyle(Theme.telegram.opacity(0.85))
            Text("跟克拉扣說句話開始").font(Theme.title(17)).foregroundStyle(Theme.ink(scheme))
            Text("語音或打字都行，回覆會顯示在這裡")
                .font(Theme.body(14)).foregroundStyle(Theme.inkDim(scheme))
            Spacer()
        }
    }
}
