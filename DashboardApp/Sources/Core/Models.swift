import Foundation

// 對應 handoffs\8896_api_contract_for_ios_20260929.md 的回應形狀。欄位一律 optional 防伺服器演進打掛解碼。

struct LoginResponse: Codable {
    var ok: Bool?
    var token: String
    var refresh_token: String?
    var expires_in: Int?
    var username: String?
    var role: String?
    var tenant_id: String?
}

struct StateResponse: Codable {
    var agents: [Agent]
    var env: String?
    var tenant: String?
}

struct Agent: Codable, Identifiable, Hashable {
    var name: String
    var title: String?
    var steward: Bool?
    var model: String?
    var channels: [String]?
    var running: Bool?
    var pid: Int?
    var managed: Bool?
    var busy: Bool?
    var auth_error: Bool?
    var seeded: Bool?
    var backend: String?
    var engine: String?
    var id: String { name }
    var isRunning: Bool { running ?? false }
    var isBusy: Bool { busy ?? false }
    var hasAuthError: Bool { auth_error ?? false }
    // 網頁版 engineLabel()
    var engineLabel: String {
        let m = model ?? ""
        if engine == "claude-codex" { return "ChatGPT 額度 · " + m }
        if engine == "claude-grok" { return "Grok 額度 · grok-4.6" }
        if backend == "codex" { return "Codex（ChatGPT）· " + m }
        return m
    }
}

struct HealthResponse: Codable {
    var status: String?
    var version: String?
    var uptime_seconds: Int?
    var isInternal: Bool?
    enum CodingKeys: String, CodingKey { case status, version, uptime_seconds, isInternal = "internal" }
}

struct UsageResponse: Codable {
    var range: String?
    var agents: [UsageAgent]?
}
struct HourBucket: Codable, Hashable {
    var input: Double?
    var output: Double?
    var cache_create: Double?
    var cache_read: Double?
    var calls: Double?
}
struct UsageAgent: Codable {
    var name: String
    var model: String?
    var input: Double?
    var output: Double?
    var cache_create: Double?
    var cache_read: Double?
    var calls: Double?
    var per_hour: [String: HourBucket]?
    var total7d: Double { (input ?? 0) + (output ?? 0) + (cache_create ?? 0) + (cache_read ?? 0) }
}

struct OkResponse: Codable {
    var ok: Bool?
    var name: String?
    var error: String?
    var message_id: Int?
    var group_id: Int?
    var media_url: String?
    var filename: String?
}

struct ClaudeMD: Codable {
    var name: String?
    var content: String?
}

struct TerminalBuffer: Codable {
    var lines: [String]?
    var total: Int?
    var source: String?
}
struct TerminalURLs: Codable { var urls: [String]? }

struct GroupsResponse: Codable { var groups: [ChatGroup] }
struct ChatGroup: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var created_at: Double?
    var member_count: Int?
    var members: [String]?
    var last_msg_id: Int?
    var last_ts: Double?
    var last_sender: String?
    var last_msg_type: String?
    var last_preview: String?
    var pending_decisions: Int?
}
struct MembersResponse: Codable { var members: [String] }
struct MessagesResponse: Codable { var messages: [ChatMessage] }
struct ChatMessage: Codable, Identifiable, Hashable {
    var id: Int
    var group_id: Int?
    var sender: String?
    var content: String?
    var ts: Double?
    var msg_type: String?
    var media_url: String?
    var decision: Int?
    var decision_status: String?
    var resolved_ts: Double?
    var resolved_by: String?
    var verdict_text: String?
    var reply_to: Int?
    var isHuman: Bool { msg_type == "human" || msg_type == "user" }
    var isPending: Bool { (decision ?? 0) == 1 && decision_status == "pending" }
}
// SSE 事件（新訊息或 decision_update）
struct SSEEvent: Codable {
    var type: String?
    var id: Int?
    var sender: String?
    var content: String?
    var msg_type: String?
    var media_url: String?
    var decision: Int?
    var decision_status: String?
    var reply_to: Int?
    var resolved_by: String?
    var verdict_text: String?
    var resolved_ts: Double?
}

struct ProductsTree: Codable {
    var stations: [ProductStation]
    var media_base: String?
}
struct ProductStation: Codable, Identifiable, Hashable {
    var name: String
    var date_count: Int?
    var video_count: Int?
    var image_count: Int?
    var latest: String?
    var dates: [ProductDate]
    var id: String { name }
}
struct ProductDate: Codable, Identifiable, Hashable {
    var date: String
    var title: String?
    var videos: [ProductFile]
    var images: [ProductFile]
    var id: String { date }
}
struct ProductFile: Codable, Identifiable, Hashable {
    var name: String
    var size: Int?
    var mtime: Int?
    var rel: String
    var id: String { rel }
}

struct BoardProjects: Codable { var ok: Bool?; var projects: [BoardProject]? }
struct BoardProject: Codable, Identifiable, Hashable {
    var id: String
    var name: String?
    var description: String?
    var status: String?
    var progress: Double?
    var task_counts: [String: Int]?
}
struct BoardTasks: Codable { var ok: Bool?; var tasks: [BoardTask]? }
struct BoardTask: Codable, Identifiable, Hashable {
    var id: Int
    var project_id: String?
    var title: String?
    var detail: String?
    var assignee: String?
    var status: String?
    var percent: Double?
    var updated_at: String?
    var last_update: BoardUpdate?
}
struct BoardUpdate: Codable, Hashable { var author: String?; var content: String?; var created_at: String? }

struct BackupList: Codable { var backups: [BackupItem]? }
struct BackupItem: Codable, Identifiable, Hashable {
    var label: String?
    var timestamp: String?
    var iso: String?
    var agents: Int?
    var files: Int?
    var size_mb: Double?
    var zip_exists: Bool?
    var id: String { timestamp ?? UUID().uuidString }
}
struct BackupStatus: Codable { var running: Bool?; var interval_hours: Double?; var backup_dir: String?; var total_backups: Int? }

struct AuditList: Codable { var events: [AuditEvent]?; var count: Int?; var total: Int? }
struct AuditEvent: Codable, Identifiable, Hashable {
    var ts: String?
    var actor: String?
    var action: String?
    var target: String?
    var result: String?
    var id: String { (ts ?? "") + (actor ?? "") + (action ?? "") }
}

struct UsersList: Codable { var users: [DashUser]? }
struct DashUser: Codable, Identifiable, Hashable {
    var id: Int
    var username: String
    var email: String?
    var email_verified: Bool?
    var role: String?
    var tenant_id: String?
    var created_at: String?
    var last_login: String?
    var status: String?
}

struct KnowledgeFiles: Codable { var files: [KnowledgeFile]? }
struct KnowledgeFile: Codable, Identifiable, Hashable {
    var name: String
    var agent: String?
    var type: String?
    var size: Int?
    var path: String?
    var id: String { (agent ?? "") + "/" + (path ?? name) }
}
struct KnowledgeRead: Codable { var content: String?; var name: String?; var path: String? }

struct DiscordChannels: Codable { var channels: [DiscordChannel]? }
struct DiscordChannel: Codable, Identifiable, Hashable { var id: String; var name: String? }
struct DiscordMessages: Codable { var messages: [DiscordMessage]?; var count: Int? }
struct DiscordAuthor: Codable, Hashable { var username: String?; var global_name: String? }
struct DiscordMessage: Codable, Identifiable, Hashable {
    var id: String
    var content: String?
    var timestamp: String?
    var author: DiscordAuthor?
}

struct StoreOrders: Codable { var ok: Bool?; var orders: [StoreOrder]? }
struct StoreOrder: Codable, Identifiable, Hashable {
    var id: String?
    var order_id: String?
    var product: String?
    var buyer: String?
    var status: String?
    var created_at: String?
    var identity: String { id ?? order_id ?? UUID().uuidString }
}
struct StoreBuyers: Codable { var ok: Bool?; var buyers: [StoreBuyer]? }
struct StoreBuyer: Codable, Identifiable, Hashable {
    var id: String
    var email: String?
    var status: String?
    var created_at: String?
}

// ---- 2026-09-29 v2.1 網頁對齊新增 ----
struct TemplatesResponse: Codable { var templates: [AgentTemplate]? }
struct AgentTemplate: Codable, Identifiable, Hashable {
    var id: String
    var name: String?
    var icon: String?
    var tagline: String?
    var sample_tasks: [String]?
    var claude_md: String?
}
struct TemplateDetail: Codable { var template: AgentTemplate? }
struct FccStatus: Codable { var chatgpt_connected: Bool?; var running: Bool? }
struct TunnelStatus: Codable {
    var running: Bool?
    var url: String?
    var qr: String?
    var mode: String?
    var installed: Bool?
    var error: String?
    var status: String?
}
struct LicenseList: Codable { var licenses: [LicenseItem]? }
struct LicenseItem: Codable, Identifiable, Hashable {
    var key: String
    var tenant_id: String?
    var tier: String?
    var status: String?
    var expires_at: String?
    var id: String { key }
}
struct HwidResponse: Codable { var hwid: String? }
struct IssueResponse: Codable { var key: String?; var error: String?; var detail: String? }
struct SearchResponse: Codable { var results: [SearchHit]? }
struct SearchHit: Codable, Hashable {
    var source: String?
    var agent: String?
    var channel_name: String?
    var author: String?
    var ts: String?
    var snippet: String?
}
struct AdminStats: Codable {
    var total_users: Int?
    var total_listings: Int?
    var total_orders: Int?
    var total_revenue: Double?
    var total_licenses: Int?
}
struct AdminListings: Codable { var listings: [AdminListing]? }
struct ListingPricing: Codable, Hashable { var per_month: Double?; var one_time: Double?; var currency: String? }
struct AdminListing: Codable, Identifiable, Hashable {
    var id: String
    var name: String?
    var description: String?
    var type: String?
    var status: String?
    var seller_name: String?
    var pricing: ListingPricing?
}
struct StoreProducts: Codable { var products: [StoreProduct]?; var central: Bool? }
struct StoreProduct: Codable, Identifiable, Hashable {
    var id: String
    var name: String?
    var type: String?
    var description: String?
    var price: Double?
    var currency: String?
    var official: Bool?
    var seller_name: String?
    var drm: Bool?
}
struct StoreCentral: Codable { var url: String?; var configured: Bool?; var reachable: Bool?; var third_party_listing: Bool? }
struct StoreOwned: Codable { var owned: [OwnedItem]? }
struct OwnedItem: Codable, Identifiable, Hashable {
    var product_id: String
    var name: String?
    var ptype: String?
    var drm: Bool?
    var unlocked_at: String?
    var id: String { product_id }
}
struct BuyerAccount: Codable { var logged_in: Bool?; var email: String?; var configured: Bool? }
struct CheckoutResponse: Codable { var ok: Bool?; var checkout_url: String?; var error: String? }
struct RedeemResponse: Codable { var ok: Bool?; var drm: Bool?; var error: String?; var detail: String? }
struct CodexStatus: Codable { var installed: Bool?; var installing: Bool?; var progress: Double?; var logged_in: Bool?; var error: String? }
struct ConnectStatus: Codable { var connected: Bool?; var state: String?; var email: String?; var error: String?; var running: Bool? }
struct ConnectStart: Codable { var ok: Bool?; var authorization_url: String?; var error: String? }
struct AiLoginStatus: Codable { var connected: Bool?; var ok: Bool?; var already: Bool?; var authorization_url: String?; var error: String? }
struct ErrorTour: Codable { var enabled: Bool? }
struct UserPluginsResponse: Codable { var plugins: [UserPlugin]? }
struct TranslateResponse: Codable { var content: String?; var translated: String?; var text: String?; var error: String? }
struct MessageResp: Codable { var ok: Bool?; var message: String?; var error: String?; var who: String?; var pending: Bool? }
