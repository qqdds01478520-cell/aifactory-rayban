import Foundation

/// 遠端遙測（fire-and-forget）：綁定/連線每一步打回 relay /applog，
/// COO 在工廠機直接讀 /applogs 自查，不用董事長口述現場。
enum RemoteLog {
    static func send(_ msg: String) {
        guard AppConfig.hasRelayKey,
              var c = URLComponents(string: AppConfig.relayBase + "/applog") else { return }
        c.queryItems = [URLQueryItem(name: "k", value: AppConfig.authKey)]
        guard let u = c.url else { return }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["m": msg])
        URLSession.shared.dataTask(with: req).resume()
    }
}
