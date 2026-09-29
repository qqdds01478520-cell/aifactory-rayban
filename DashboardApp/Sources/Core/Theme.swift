import SwiftUI
import UIKit

// 主題色＝鏡射 8896 網頁版 CSS token（dark --bg #16130f… / light --bg #f8f3eb…），依系統深淺色自動切換
enum Theme {
    static func dyn(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> Color {
        Color(UIColor { tc in
            let hex = tc.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xff) / 255,
                           green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
        })
    }
    static let bg        = dyn(0xf8f3eb, 0x16130f)
    static let surface   = dyn(0xfffefa, 0x211d17)
    static let surface2  = dyn(0xf3ece0, 0x2a251d)
    static let text      = dyn(0x2c1810, 0xf1ebe0)
    static let muted     = dyn(0x2c1810, 0xf1ebe0, alpha: 0.55)
    static let primary   = dyn(0xd8622e, 0xe3733f)
    static let primaryHi = dyn(0xe3733f, 0xee8757)
    static let accent    = dyn(0x6a8f72, 0x7fa085)
    static let success   = dyn(0x4a8c5c, 0x6cc183)
    static let warning   = dyn(0xc98a1b, 0xe0a83a)
    static let danger    = dyn(0xc0392b, 0xe06a5c)
    static let border    = dyn(0x2c1810, 0xf5efe6, alpha: 0.08)

    static let radius: CGFloat = 16
    static let cardPad: CGFloat = 14
}

struct CardStyle: ViewModifier {
    var pad: CGFloat = Theme.cardPad
    func body(content: Content) -> some View {
        content
            .padding(pad)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}
extension View {
    func card(pad: CGFloat = Theme.cardPad) -> some View { modifier(CardStyle(pad: pad)) }
    func screenBackground() -> some View { background(Theme.bg.ignoresSafeArea()) }
}

// 觸覺回饋（B11）
enum Haptic {
    static func tap()     { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium()  { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func select()  { UISelectionFeedbackGenerator().selectionChanged() }
}

// 數字用襯線體（網頁版 Fraunces 數字風格 → 系統 serif 設計）
struct StatNumber: View {
    let value: String
    var size: CGFloat = 28
    var body: some View {
        Text(value)
            .font(.system(size: size, weight: .semibold, design: .serif))
            .foregroundColor(Theme.text)
            .monospacedDigit()
    }
}

struct StatusDot: View {
    let running: Bool
    let error: Bool
    var body: some View {
        Circle()
            .fill(error ? Theme.danger : (running ? Theme.success : Theme.muted.opacity(0.4)))
            .frame(width: 9, height: 9)
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.accent
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.16))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(configuration.isPressed ? Theme.primaryHi : Theme.primary)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct EmptyHint: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.title2).foregroundColor(Theme.muted)
            Text(text).font(.footnote).foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

extension Date {
    static func fromUnix(_ ts: Double?) -> Date? { ts.map { Date(timeIntervalSince1970: $0) } }
}

enum Fmt {
    static func tokens(_ n: Double) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", n / 1_000) }
        return String(format: "%.0f", n)
    }
    static func bytes(_ b: Int) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file; return f.string(fromByteCount: Int64(b))
    }
    static let tw: DateFormatter = {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "MM/dd HH:mm"; return f
    }()
    static let twTime: DateFormatter = {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "HH:mm"; return f
    }()
    static func when(_ ts: Double?) -> String {
        guard let d = Date.fromUnix(ts) else { return "" }
        return Calendar.current.isDateInToday(d) ? twTime.string(from: d) : tw.string(from: d)
    }
    static func uptime(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    static func iso(_ s: String) -> String {
        let p = ISO8601DateFormatter(); p.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = p.date(from: s) { return tw.string(from: d) }
        p.formatOptions = [.withInternetDateTime]
        if let d = p.date(from: s) { return tw.string(from: d) }
        return String(s.prefix(16))
    }
}
