import SwiftUI

// 語系＝鏡射網頁 i18n.jsx：key 為繁中原文，四語（zh-TW / zh-CN / en / ja），查無翻譯回傳原文
struct LangOpt: Identifiable { let code: String; let label: String; var id: String { code } }
let LANGS: [LangOpt] = [
    LangOpt(code: "zh-TW", label: "繁體中文"),
    LangOpt(code: "zh-CN", label: "简体中文"),
    LangOpt(code: "en", label: "English"),
    LangOpt(code: "ja", label: "日本語"),
]

final class L10n: ObservableObject {
    static let shared = L10n()
    @AppStorage("aif_lang") var lang: String = "zh-TW" { didSet { objectWillChange.send() } }
    var label: String { LANGS.first { $0.code == lang }?.label ?? "繁體中文" }
    func t(_ zh: String) -> String {
        if lang == "zh-TW" { return zh }
        return I18nTable.TR[zh]?[lang] ?? zh
    }
}
func L(_ zh: String) -> String { L10n.shared.t(zh) }
