import SwiftUI

// 導覽狀態＝鏡射 App.jsx 的 page / subPage：分頁列在子頁、插件頁、聊天室內隱藏
enum Tab: String, CaseIterable { case overview, agents, terminal, chat, more }

enum SubPage: String, Identifiable {
    case usage, backup, search, license, users, knowledge, products, store, admin, claudeToken, remote, company
    var id: String { rawValue }
    var title: String {
        switch self {
        case .usage: return L("Token 用量")
        case .backup: return L("備份管理")
        case .search: return L("搜尋")
        case .products: return L("影片成品區")
        case .license: return L("授權管理")
        case .users: return L("用戶管理")
        case .knowledge: return L("知識庫")
        case .admin: return L("管理後台")
        case .claudeToken: return L("AI 認證設定")
        case .remote: return L("遠端連線")
        case .store: return L("商城")
        case .company: return L("公司")
        }
    }
}

struct UserPlugin: Codable, Identifiable, Hashable {
    var name: String
    var url: String?
    var page: String?
    var proxied: Bool?
    var id: String { name + "|" + (url ?? page ?? "") }
}

struct ToastMsg: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let kind: String
}

@MainActor
final class Nav: ObservableObject {
    static let shared = Nav()
    @Published var tab: Tab = .overview
    @Published var sub: SubPage? = nil
    @Published var plugin: UserPlugin? = nil
    @Published var chatRoom: Bool = false
    @Published var terminalAgent: String? = nil
    @Published var toast: ToastMsg? = nil
    private var toastTask: Task<Void, Never>?

    var tabBarHidden: Bool { sub != nil || plugin != nil || chatRoom }

    func go(_ t: Tab) { withAnimation(.easeInOut(duration: 0.15)) { sub = nil; plugin = nil; tab = t } }
    func open(_ s: SubPage) { Haptic.tap(); withAnimation(.easeInOut(duration: 0.15)) { sub = s } }
    func openPlugin(_ p: UserPlugin) {
        Haptic.tap()
        if p.page == "products" { open(.products); return }
        withAnimation(.easeInOut(duration: 0.15)) { plugin = p }
    }
    // 網頁：子頁返回 → 'more'
    func back() { Haptic.tap(); withAnimation(.easeInOut(duration: 0.15)) { sub = nil; plugin = nil; tab = .more } }
    func openTerminal(_ agent: String) { terminalAgent = agent; go(.terminal) }

    func show(_ text: String, _ kind: String = "info", ms: Int = 2500) {
        toastTask?.cancel()
        withAnimation { toast = ToastMsg(text: text, kind: kind) }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            if !Task.isCancelled { withAnimation { toast = nil } }
        }
    }
}
