import Foundation

/// 遠端除錯橋（董事長 2026-09-01 指定功能）。
/// COO 從工廠機下指令 → app 在眼鏡上執行 → 回傳結果/log，COO 自主 e2e 驗收，
/// 不用董事長肉眼回報。這是「COO 在你眼鏡裡的一隻手」。
///
/// 協議（worker.js 需補上對應端點，本 client 先照此規格寫）：
///   GET  /cmd/pull?dev=glasses      → { id, action, args } 或 null（無待辦）
///   POST /cmd/result                → { id, ok, result, log }
/// action 對應 app 能力：display(顯示文字) / capture(拍照) / speak(唸)
///   / status(回報麥克風·相機·連線狀態) / listen(跑一次語音辨識)
struct RemoteCommand: Decodable {
    let id: String
    let action: String
    let args: [String: String]?
}

struct CommandResult: Encodable {
    let id: String
    let ok: Bool
    let result: String
    let log: String
}

/// 執行者：由 app 主體注入實作（GlassesManager 等 DAT 整合就緒後接上）。
protocol CommandExecutor {
    func execute(_ cmd: RemoteCommand) async -> CommandResult
}

actor RemoteDebugBridge {
    private let base: URL
    private let authKey: String
    private let device: String
    private let executor: CommandExecutor
    private var running = false

    init(base: String = "https://rayban-relay.goingtosheon.workers.dev",
         authKey: String, device: String = "glasses", executor: CommandExecutor) {
        self.base = URL(string: base)!
        self.authKey = authKey
        self.device = device
        self.executor = executor
    }

    private func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "k", value: authKey)]
        items.append(contentsOf: query.map { URLQueryItem(name: $0.key, value: $0.value) })
        c.queryItems = items
        return c.url!
    }

    /// 常駐輪詢：每 pollInterval 秒抓一次指令，有就執行並回報。
    func start(pollInterval: TimeInterval = 2.0) async {
        running = true
        while running {
            do {
                if let cmd = try await pull() {
                    let res = await executor.execute(cmd)
                    try await report(res)
                } else {
                    try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                }
            } catch {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 出錯退避 3s
            }
        }
    }

    func stop() { running = false }

    private func pull() async throws -> RemoteCommand? {
        let (data, _) = try await URLSession.shared.data(from: url("/cmd/pull", ["dev": device]))
        if data.isEmpty { return nil }
        if let s = String(data: data, encoding: .utf8), s == "null" || s.isEmpty { return nil }
        return try? JSONDecoder().decode(RemoteCommand.self, from: data)
    }

    private func report(_ res: CommandResult) async throws {
        var req = URLRequest(url: url("/cmd/result"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(res)
        _ = try await URLSession.shared.data(for: req)
    }
}
