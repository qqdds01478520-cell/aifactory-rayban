import SwiftUI

/// 克拉扣 OS 設計 tokens。全彩、深靛藍底、每個功能一個語意色（色彩編碼＝好認）。
/// 深淺兩主題都給；顏色都經 asset-free 直寫，模擬器一定渲染得出。
enum Theme {
    // 底 / 卡片 / 分隔（深色為主視覺，淺色自動對應）
    static func ground(_ s: ColorScheme) -> Color {
        s == .dark ? Color(hex: 0x0F1220) : Color(hex: 0xF6F5F1)
    }
    static func surface(_ s: ColorScheme) -> Color {
        s == .dark ? Color(hex: 0x1A1E30) : Color(hex: 0xFFFFFF)
    }
    static func surfaceHi(_ s: ColorScheme) -> Color {
        s == .dark ? Color(hex: 0x242A42) : Color(hex: 0xECEAF3)
    }
    static func line(_ s: ColorScheme) -> Color {
        s == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    // 文字
    static func ink(_ s: ColorScheme) -> Color {
        s == .dark ? Color(hex: 0xF2EFE9) : Color(hex: 0x181A22)
    }
    static func inkDim(_ s: ColorScheme) -> Color {
        s == .dark ? Color(hex: 0x9AA0B4) : Color(hex: 0x6A6F80)
    }
    // 簽名暖金（克拉扣品牌）＋功能語意色
    static let brand = Color(hex: 0xF5A524)   // 克拉扣 / 語音
    static let youtube = Color(hex: 0xFF4D5E) // 珊瑚紅
    static let maps = Color(hex: 0x22C55E)    // 翡翠綠
    static let telegram = Color(hex: 0x38BDF8) // 天藍
    static let travel = Color(hex: 0xA78BFA)  // 薰衣草紫（旅遊模式）
    static let glasses = Color(hex: 0xD9BC7A) // 金（眼鏡連線）

    // 字型層級（SF Pro rounded，中文自動走系統）
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func body(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .rounded) }
    static func label(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
}

/// 一個功能分頁的身分（色彩編碼＋圖示）。
enum AppTab: String, CaseIterable, Identifiable {
    case youtube, maps, telegram, travel, glasses
    var id: String { rawValue }
    var title: String {
        switch self {
        case .youtube: return "YouTube"
        case .maps: return "地圖"
        case .telegram: return "Telegram"
        case .travel: return "旅遊"
        case .glasses: return "眼鏡"
        }
    }
    var icon: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .maps: return "map.fill"
        case .telegram: return "paperplane.fill"
        case .travel: return "airplane"
        case .glasses: return "eyeglasses"
        }
    }
    var accent: Color {
        switch self {
        case .youtube: return Theme.youtube
        case .maps: return Theme.maps
        case .telegram: return Theme.telegram
        case .travel: return Theme.travel
        case .glasses: return Theme.glasses
        }
    }
    var hint: String {
        switch self {
        case .youtube: return "搜尋・語音／打字都行"
        case .maps: return "找地點・語音／打字都行"
        case .telegram: return "跟克拉扣說話・語音／打字"
        case .travel: return "克拉扣隨行・導遊/菜單/行程"
        case .glasses: return "連 Ray-Ban Display・鏡頭/鏡片"
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
