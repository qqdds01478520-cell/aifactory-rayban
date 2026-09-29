import Foundation

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
    var isAuth: Bool { status == 401 }
}

// 直打 8896 FastAPI；401 自動 refresh 一次重試（契約 §1）
final class APIClient {
    var baseURL: URL
    var token: String?
    var refreshToken: String?
    var onTokens: ((String, String?) -> Void)?   // refresh 成功回寫 Keychain
    var onSessionExpired: (() -> Void)?

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 25
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    init(baseURL: URL) { self.baseURL = baseURL }

    func url(_ path: String) -> URL {
        if path.hasPrefix("http") { return URL(string: path)! }
        return URL(string: path, relativeTo: baseURL)!.absoluteURL
    }

    // 媒體網址（/uploads、/products-media 免 auth；rel 逐段 percent-encode）
    func mediaURL(_ pathOrRel: String, base: String = "") -> URL? {
        let raw = base + pathOrRel
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false).map { seg -> String in
            String(seg).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))) ?? String(seg)
        }
        return URL(string: parts.joined(separator: "/"), relativeTo: baseURL)?.absoluteURL
    }

    private static let decoder = JSONDecoder()

    @discardableResult
    func request<T: Decodable>(_ path: String, method: String = "GET", body: Any? = nil,
                               auth: Bool = true, retry: Bool = true, timeout: TimeInterval? = nil) async throws -> T {
        var req = URLRequest(url: url(path))
        req.httpMethod = method
        if let timeout { req.timeoutInterval = timeout }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if auth, let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 401 && auth && retry {
            if await tryRefresh() { return try await request(path, method: method, body: body, auth: auth, retry: false, timeout: timeout) }
            onSessionExpired?()
            throw APIError(status: 401, message: "session expired")
        }
        guard (200..<300).contains(status) else {
            throw APIError(status: status, message: Self.extractError(data, status: status))
        }
        if T.self == OkResponse.self, data.isEmpty { return OkResponse() as! T }
        do { return try Self.decoder.decode(T.self, from: data) }
        catch { throw APIError(status: status, message: "decode: \(error.localizedDescription)") }
    }

    func requestData(_ path: String, auth: Bool = true) async throws -> Data {
        var req = URLRequest(url: url(path))
        if auth, let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError(status: status, message: Self.extractError(data, status: status)) }
        return data
    }

    // multipart 上傳（群聊 /api/group-chat/upload，欄位名 file）
    func upload(_ path: String, fileData: Data, filename: String, mime: String) async throws -> OkResponse {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let boundary = "aif-" + UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        req.timeoutInterval = 120
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError(status: status, message: Self.extractError(data, status: status)) }
        return try Self.decoder.decode(OkResponse.self, from: data)
    }

    private var refreshing: Task<Bool, Never>?
    func tryRefresh() async -> Bool {
        if let r = refreshing { return await r.value }
        let t = Task<Bool, Never> { [weak self] in
            guard let self, let rt = self.refreshToken else { return false }
            do {
                let r: LoginResponse = try await self.request("/api/auth/refresh", method: "POST",
                                                              body: ["refresh_token": rt], auth: false, retry: false)
                self.token = r.token
                if let nrt = r.refresh_token { self.refreshToken = nrt }
                self.onTokens?(r.token, self.refreshToken)
                return true
            } catch { return false }
        }
        refreshing = t
        let ok = await t.value
        refreshing = nil
        return ok
    }

    static func extractError(_ data: Data, status: Int) -> String {
        if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let d = j["detail"] as? String { return d }
            if let arr = j["detail"] as? [[String: Any]] {
                return arr.compactMap { $0["msg"] as? String }.joined(separator: "；")
            }
            if let e = j["error"] as? String { return e }
        }
        return "HTTP \(status)"
    }

    // SSE：群聊 stream（token 放 query），逐行吐 data: JSON
    func sse(_ path: String, onEvent: @escaping (Data) -> Void) async throws {
        guard let t = token else { throw APIError(status: 401, message: "no token") }
        var comps = URLComponents(url: url(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "token", value: t)]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 3600
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, resp) = try await session.bytes(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw APIError(status: status, message: "sse \(status)") }
        for try await line in bytes.lines {
            if line.hasPrefix("data:") {
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if let d = payload.data(using: .utf8) { onEvent(d) }
            }
        }
    }
}

// ANSI 去碼：raw PTY 區塊 → 可讀文字（rendered 端點拿不到時的退路）
enum ANSI {
    private static let csi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-?]*[ -/]*[@-~]")
    private static let osc = try! NSRegularExpression(pattern: "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)")
    private static let esc = try! NSRegularExpression(pattern: "\u{1B}[@-Z\\\\-_]")
    static func strip(_ s: String) -> String {
        var out = s
        for re in [osc, csi, esc] {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        }
        out = out.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return out.filter { $0 == "\n" || $0 == "\t" || !$0.isASCII || ($0.asciiValue ?? 32) >= 32 }
    }
}
