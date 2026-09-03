import Foundation

/// 對接已上線的 Cloudflare Worker relay（worker.js）。
/// 端點沿用現有：/ask_sync（語音問答·長輪詢+秒答）、/messages（顯示台訊息）、
/// /push（COO 推文字上鏡）、/photo（拍照上傳後取回）。
/// base 與 authKey 對應 rayban-relay.goingtosheon.workers.dev、k= 參數。
struct RelayClient {
    let base: URL
    let authKey: String

    init(base: String = "https://rayban-relay.goingtosheon.workers.dev",
         authKey: String) {
        self.base = URL(string: base)!
        self.authKey = authKey
    }

    private func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "k", value: authKey)]
        items.append(contentsOf: query.map { URLQueryItem(name: $0.key, value: $0.value) })
        c.queryItems = items
        return c.url!
    }

    /// 問答：送一句話，拿 COO 的回答（伺服器端秒答時間類，其餘長輪詢等 COO）。
    func ask(_ text: String) async throws -> String {
        var req = URLRequest(url: url("/ask_sync"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
        req.timeoutInterval = 60
        let (data, _) = try await URLSession.shared.data(for: req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 帶照片的問答：照片跟問題綁同一單（COO 端看得到圖才答得準）。回單號。
    func askPhoto(_ jpeg: Data, text: String) async throws -> String {
        var req = URLRequest(url: url("/ask"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text, "photo_b64": jpeg.base64EncodedString()])
        req.timeoutInterval = 60
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["id"] as? String) ?? ""
    }

    /// 輪詢答案（/answer/{id}），最多 timeout 秒；沒等到回 nil。
    func pollAnswer(id: String, timeout: TimeInterval = 100) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let (data, _) = try? await URLSession.shared.data(from: url("/answer/\(id)")),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               (obj["answered"] as? Bool) == true,
               let a = obj["answer"] as? String, !a.isEmpty {
                return a
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return nil
    }

    /// 拍照上傳，回傳伺服器分配的 photo id（之後 COO 可用 /photo/{id} 取回辨識）。
    func uploadPhoto(_ jpeg: Data) async throws -> String {
        var req = URLRequest(url: url("/photo"))
        req.httpMethod = "POST"
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = jpeg
        let (data, _) = try await URLSession.shared.data(for: req)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["id"] as? String) ?? ""
    }

    /// 拉取要顯示在鏡片上的新訊息（COO push 的戰情/回覆）。after = 已收到的最大 id。
    func pullMessages(after: Int64) async throws -> [RelayMessage] {
        let (data, _) = try await URLSession.shared.data(from: url("/messages", ["after": String(after)]))
        let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        return arr.map {
            RelayMessage(id: ($0["id"] as? Int64) ?? 0,
                         text: ($0["text"] as? String) ?? "",
                         from: ($0["from"] as? String) ?? "coo")
        }
    }
}

struct RelayMessage: Identifiable {
    let id: Int64
    let text: String
    let from: String   // "coo" | "chairman"
}
