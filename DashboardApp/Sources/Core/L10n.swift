import SwiftUI

// 繁英切換（網頁版 aif_lang 對應；app 端純客戶端）
final class L10n: ObservableObject {
    static let shared = L10n()
    @AppStorage("aif_lang") var lang: String = "zh" { didSet { objectWillChange.send() } }

    private static let zh: [String: String] = [
        "tab.overview": "總覽", "tab.agents": "員工", "tab.terminal": "終端機", "tab.chat": "群聊", "tab.more": "更多",
        "login.title": "AI 工廠控制台", "login.sub": "登入你的商用控制台", "login.user": "帳號", "login.pass": "密碼",
        "login.server": "伺服器網址", "login.go": "登入", "login.faceid": "使用 Face ID 解鎖", "login.busy": "登入中…",
        "ov.running": "運行中員工", "ov.tokens": "TOKEN 用量（7日）", "ov.uptime": "正常運行率", "ov.quota": "TOKEN 配額",
        "ov.allok": "所有系統運行正常", "ov.none": "目前無運行中的 Agent", "ov.active": "活躍員工", "ov.total": "總員工數",
        "ov.server": "伺服器", "ov.version": "版本", "ov.up": "已運行", "ov.autherr": "個員工登入異常，開終端機處理",
        "ov.recent": "最近群聊", "ov.usage.wait": "統計中…",
        "ag.search": "搜尋員工", "ag.start": "啟動", "ag.stop": "停止", "ag.busy": "運算中", "ag.running": "運行中",
        "ag.stopped": "已停止", "ag.autherr": "登入異常", "ag.claudemd": "CLAUDE.md", "ag.terminal": "開終端機",
        "ag.dm": "私訊", "ag.save": "儲存", "ag.saved": "已儲存", "ag.adminonly": "需管理員權限", "ag.model": "模型",
        "ag.pid": "PID", "ag.detail": "員工詳情", "ag.confirmstop": "停止此員工？", "ag.filter.all": "全部", "ag.filter.running": "運行中",
        "term.pick": "選擇員工", "term.raw": "原生", "term.chat": "對話", "term.send": "送出", "term.placeholder": "輸入指令或訊息…",
        "term.nopty": "此員工未在運行，先到員工頁啟動", "term.history": "歷史", "term.live": "即時", "term.urls": "登入連結",
        "chat.groups": "群組", "chat.new": "新群組", "chat.name": "群組名稱", "chat.members": "成員", "chat.send": "傳送",
        "chat.placeholder": "訊息…", "chat.pending": "待裁決", "chat.approve": "核准", "chat.reject": "退回",
        "chat.approved": "已核准", "chat.rejected": "已退回", "chat.photo": "照片", "chat.uploading": "上傳中…", "chat.create": "建立",
        "chat.empty": "還沒有訊息", "chat.replying": "回覆",
        "more.products": "影片成品區", "more.board": "看板", "more.discord": "Discord 訊息", "more.backup": "備份",
        "more.audit": "審計紀錄", "more.knowledge": "知識庫", "more.users": "管理員設定", "more.store": "市集授權後台",
        "more.settings": "設定", "more.logout": "登出", "more.lang": "語言", "more.faceid": "Face ID 鎖定",
        "more.bgrefresh": "背景更新", "more.push": "推播通知", "more.server": "伺服器", "more.version": "App 版本",
        "more.cache": "離線快取", "more.cache.clear": "清除快取", "more.account": "帳號", "more.role": "角色",
        "more.haptics": "觸覺回饋", "more.dispatch": "分享派工目標員工",
        "prod.videos": "支影片", "prod.dates": "個日期", "prod.play": "播放", "prod.images": "圖片",
        "board.projects": "專案", "board.tasks": "任務", "board.progress": "進度",
        "bk.create": "立即備份", "bk.status": "自動備份", "bk.every": "每", "bk.hours": "小時", "bk.total": "份",
        "bk.restore": "還原", "bk.delete": "刪除", "bk.confirmrestore": "還原此備份？現有資料會被覆蓋。", "bk.confirmdelete": "刪除此備份？",
        "au.filter": "篩選 actor / action",
        "us.create": "新增用戶", "us.suspend": "停權", "us.activate": "復權", "us.reset": "重設密碼", "us.newpass": "新密碼",
        "us.role": "角色", "us.confirmdel": "刪除此用戶？",
        "dc.channels": "頻道", "dc.send": "傳送到頻道",
        "kb.files": "檔案",
        "common.retry": "重試", "common.error": "錯誤", "common.ok": "好", "common.cancel": "取消", "common.loading": "載入中…",
        "common.offline": "離線 · 顯示快取", "common.refresh": "重新整理", "common.none": "無", "common.confirm": "確認",
        "lock.title": "已鎖定", "lock.unlock": "解鎖",
        "share.title": "派工給員工", "share.send": "派工", "share.agent": "員工", "share.sent": "已送到終端機",
    ]
    private static let en: [String: String] = [
        "tab.overview": "Overview", "tab.agents": "Agents", "tab.terminal": "Terminal", "tab.chat": "Chat", "tab.more": "More",
        "login.title": "AI Factory Console", "login.sub": "Sign in to your console", "login.user": "Username", "login.pass": "Password",
        "login.server": "Server URL", "login.go": "Sign in", "login.faceid": "Unlock with Face ID", "login.busy": "Signing in…",
        "ov.running": "Running agents", "ov.tokens": "Tokens (7d)", "ov.uptime": "Availability", "ov.quota": "Token quota",
        "ov.allok": "All systems normal", "ov.none": "No agent running", "ov.active": "Active agents", "ov.total": "Total agents",
        "ov.server": "Server", "ov.version": "Version", "ov.up": "Up", "ov.autherr": "agent(s) need login, open terminal",
        "ov.recent": "Recent chats", "ov.usage.wait": "computing…",
        "ag.search": "Search agents", "ag.start": "Start", "ag.stop": "Stop", "ag.busy": "Busy", "ag.running": "Running",
        "ag.stopped": "Stopped", "ag.autherr": "Auth error", "ag.claudemd": "CLAUDE.md", "ag.terminal": "Open terminal",
        "ag.dm": "DM", "ag.save": "Save", "ag.saved": "Saved", "ag.adminonly": "Admin only", "ag.model": "Model",
        "ag.pid": "PID", "ag.detail": "Agent", "ag.confirmstop": "Stop this agent?", "ag.filter.all": "All", "ag.filter.running": "Running",
        "term.pick": "Pick agent", "term.raw": "Raw", "term.chat": "Chat", "term.send": "Send", "term.placeholder": "Command or message…",
        "term.nopty": "Agent not running. Start it on the Agents tab.", "term.history": "History", "term.live": "Live", "term.urls": "Login links",
        "chat.groups": "Groups", "chat.new": "New group", "chat.name": "Group name", "chat.members": "Members", "chat.send": "Send",
        "chat.placeholder": "Message…", "chat.pending": "Pending", "chat.approve": "Approve", "chat.reject": "Reject",
        "chat.approved": "Approved", "chat.rejected": "Rejected", "chat.photo": "Photo", "chat.uploading": "Uploading…", "chat.create": "Create",
        "chat.empty": "No messages yet", "chat.replying": "Reply to",
        "more.products": "Finished videos", "more.board": "Board", "more.discord": "Discord", "more.backup": "Backups",
        "more.audit": "Audit log", "more.knowledge": "Knowledge base", "more.users": "Admin", "more.store": "Marketplace admin",
        "more.settings": "Settings", "more.logout": "Sign out", "more.lang": "Language", "more.faceid": "Face ID lock",
        "more.bgrefresh": "Background refresh", "more.push": "Push notifications", "more.server": "Server", "more.version": "App version",
        "more.cache": "Offline cache", "more.cache.clear": "Clear cache", "more.account": "Account", "more.role": "Role",
        "more.haptics": "Haptics", "more.dispatch": "Share-sheet dispatch target",
        "prod.videos": "videos", "prod.dates": "dates", "prod.play": "Play", "prod.images": "Images",
        "board.projects": "Projects", "board.tasks": "Tasks", "board.progress": "Progress",
        "bk.create": "Back up now", "bk.status": "Auto backup", "bk.every": "every", "bk.hours": "h", "bk.total": "total",
        "bk.restore": "Restore", "bk.delete": "Delete", "bk.confirmrestore": "Restore this backup? Current data will be overwritten.", "bk.confirmdelete": "Delete this backup?",
        "au.filter": "Filter actor / action",
        "us.create": "Create user", "us.suspend": "Suspend", "us.activate": "Activate", "us.reset": "Reset password", "us.newpass": "New password",
        "us.role": "Role", "us.confirmdel": "Delete this user?",
        "dc.channels": "Channels", "dc.send": "Send to channel",
        "kb.files": "Files",
        "common.retry": "Retry", "common.error": "Error", "common.ok": "OK", "common.cancel": "Cancel", "common.loading": "Loading…",
        "common.offline": "Offline · cached", "common.refresh": "Refresh", "common.none": "None", "common.confirm": "Confirm",
        "lock.title": "Locked", "lock.unlock": "Unlock",
        "share.title": "Dispatch to agent", "share.send": "Dispatch", "share.agent": "Agent", "share.sent": "Sent to terminal",
    ]
    func t(_ key: String) -> String {
        let table = lang == "en" ? L10n.en : L10n.zh
        return table[key] ?? L10n.zh[key] ?? key
    }
}
func L(_ key: String) -> String { L10n.shared.t(key) }
