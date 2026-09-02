import SwiftUI

struct MapsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var place = "台北101"

    // Google 地圖 output=embed 必須包在 <iframe> 內才會出圖（頂層載入會回 API 錯誤）
    private var mapHTML: String {
        let q = place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Taipei"
        let src = "https://maps.google.com/maps?q=\(q)&hl=zh-TW&z=15&output=embed"
        return """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>html,body{margin:0;padding:0;height:100%;background:#0F1220;overflow:hidden}
        iframe{border:0;width:100%;height:100%;display:block}</style></head>
        <body><iframe src="\(src)" allowfullscreen loading="eager"></iframe></body></html>
        """
    }

    var body: some View {
        VStack(spacing: 14) {
            SearchBar(text: $query, accent: Theme.maps,
                      placeholder: "找地點、地址、店名") { q in
                place = q
            }
            .padding(.horizontal, 16)

            // 常用地點快捷：一點即跳，語音/打字之外的第三種快速入口
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["台北101", "台北車站", "松山機場", "台積電", "台北醫學大學"], id: \.self) { p in
                        Button { place = p; query = "" } label: {
                            Text(p)
                                .font(Theme.label(13))
                                .foregroundStyle(place == p ? .white : Theme.maps)
                                .padding(.horizontal, 13).padding(.vertical, 7)
                                .background(
                                    Capsule().fill(place == p ? Theme.maps : Theme.maps.opacity(0.14))
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            ZStack(alignment: .top) {
                WebView(html: mapHTML)
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
