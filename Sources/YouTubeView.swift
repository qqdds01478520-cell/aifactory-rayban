import SwiftUI

struct YTVideo: Identifiable, Decodable {
    let id: String
    let title: String
    let len: String
    var thumb: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg") }
}

@MainActor
final class YouTubeModel: ObservableObject {
    @Published var videos: [YTVideo] = []
    @Published var loading = false
    @Published var note = ""

    func search(_ q: String) async {
        loading = true; note = ""
        defer { loading = false }
        guard var c = URLComponents(string: AppConfig.relayBase + "/ytsearch") else { return }
        c.queryItems = [.init(name: "k", value: AppConfig.authKey), .init(name: "q", value: q)]
        guard let url = c.url else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                note = "連線狀態 \(http.statusCode)（需設定 relay 金鑰）"; return
            }
            videos = (try? JSONDecoder().decode([YTVideo].self, from: data)) ?? []
            if videos.isEmpty { note = "沒有找到「\(q)」的結果" }
        } catch {
            note = "連線失敗，請確認網路"
        }
    }
}

struct YouTubeView: View {
    @Environment(\.colorScheme) private var scheme
    @StateObject private var model = YouTubeModel()
    @State private var query = ""
    @State private var playing: YTVideo?

    var body: some View {
        VStack(spacing: 14) {
            SearchBar(text: $query, accent: Theme.youtube,
                      placeholder: "搜尋 YouTube 影片") { q in
                Task { await model.search(q) }
            }
            .padding(.horizontal, 16)

            if model.loading {
                Spacer()
                ProgressView().tint(Theme.youtube)
                Spacer()
            } else if model.videos.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.videos) { v in
                            Button { playing = v } label: { card(v) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .task { if model.videos.isEmpty { await model.search("每日新聞") } }
        .fullScreenCover(item: $playing) { v in
            player(v)
        }
    }

    private func card(_ v: YTVideo) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: v.thumb) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Theme.surfaceHi(scheme)
                }
                .frame(width: 128, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if !v.len.isEmpty {
                    Text(v.len)
                        .font(Theme.label(11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.75)))
                        .padding(6)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(v.title)
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.ink(scheme))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    Image(systemName: "play.circle.fill").font(.system(size: 12))
                    Text("點一下播放").font(Theme.body(12))
                }
                .foregroundStyle(Theme.youtube)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface(scheme))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line(scheme), lineWidth: 1))
        )
    }

    private func player(_ v: YTVideo) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text(v.title).font(Theme.title(15)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    Button { playing = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26)).foregroundStyle(.white.opacity(0.9))
                    }
                }
                .padding()
                WebView(url: URL(string: "https://www.youtube.com/embed/\(v.id)?autoplay=1&playsinline=1")!)
                    .aspectRatio(16.0/9.0, contentMode: .fit)
                Spacer()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 46)).foregroundStyle(Theme.youtube.opacity(0.85))
            Text(model.note.isEmpty ? "講一句或打字，搜尋想看的影片" : model.note)
                .font(Theme.body(15)).foregroundStyle(Theme.inkDim(scheme))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
