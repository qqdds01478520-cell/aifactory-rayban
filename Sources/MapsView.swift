import SwiftUI

struct MapsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var place = "台北101"

    private var mapURL: URL {
        let q = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Taipei"
        // Google 地圖免 API key 的嵌入方式（output=embed）
        return URL(string: "https://maps.google.com/maps?q=\(q)&hl=zh-TW&z=15&output=embed")!
    }

    var body: some View {
        VStack(spacing: 14) {
            SearchBar(text: $query, accent: Theme.maps,
                      placeholder: "找地點、地址、店名") { q in
                place = q
            }
            .padding(.horizontal, 16)

            ZStack(alignment: .top) {
                WebView(url: mapURL)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Theme.line(scheme), lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.maps)
                    Text(place).font(Theme.label(14)).foregroundStyle(Theme.ink(scheme)).lineLimit(1)
                    Spacer()
                    Button {
                        let q = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let u = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(q)") {
                            openURL(u)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            Text("導航").font(Theme.label(13))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Theme.maps))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    Capsule().fill(Theme.surface(scheme).opacity(0.96))
                        .overlay(Capsule().stroke(Theme.line(scheme), lineWidth: 1))
                )
                .padding(.horizontal, 12)
                .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }
}
