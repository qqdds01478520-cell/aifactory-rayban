import SwiftUI
import UIKit

// 主題＝逐字鏡射 8896 網頁版 index.css token（:root 淺色 / [data-theme=dark] 深色），依系統深淺色切換
extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

enum Theme {
    static func dyn(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> Color { dynA(light, alpha, dark, alpha) }
    static func dynA(_ light: UInt32, _ la: CGFloat, _ dark: UInt32, _ da: CGFloat) -> Color {
        Color(UIColor { tc in
            let hex = tc.userInterfaceStyle == .dark ? dark : light
            let a = tc.userInterfaceStyle == .dark ? da : la
            return UIColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: a)
        })
    }
    static let bg           = dyn(0xf8f3eb, 0x16130f)
    static let surface      = dyn(0xfffefa, 0x211d17)
    static let surface2     = dyn(0xf3ece0, 0x2a251d)
    static let surface3     = dyn(0xe4d9c8, 0x38322a)
    static let primary      = dyn(0xc25628, 0xe3733f)
    static let primarySoft  = dynA(0xc25628, 0.07, 0xe3733f, 0.14)
    static let primaryHover = dyn(0xa84920, 0xee8757)
    static let primaryHi    = primaryHover
    static let accent       = dyn(0x5a7a65, 0x7fa085)
    static let success      = dyn(0x4a8c5c, 0x6cc183)
    static let text         = dyn(0x2c1810, 0xf1ebe0)
    static let text2        = dyn(0x6d5d4e, 0xc6bbab)
    static let text3        = dyn(0x9a8a78, 0x8f8474)
    static let muted        = text2
    static let border       = dynA(0x261c12, 0.06, 0xf5efe6, 0.08)
    static let borderStrong = dynA(0x261c12, 0.10, 0xf5efe6, 0.14)
    static let danger       = Color(hex: 0xd4543a)
    static let warning      = Color(hex: 0xc49a2c)
    static let tagError     = Color(hex: 0xb5341a)
    static let shadow       = Color(hex: 0x2c1810, alpha: 0.06)
    static let radius: CGFloat = 16
    static let cardPad: CGFloat = 16
}

// 字體：Fraunces → 系統襯線；DM Mono → 系統等寬；Plus Jakarta/Noto Sans TC → 系統無襯線
enum WF {
    static func serif(_ s: CGFloat, _ w: Font.Weight = .semibold) -> Font { .system(size: s, weight: w, design: .serif) }
    static func mono(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w, design: .monospaced) }
    static func sans(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w) }
}

// .card：bg surface / radius 16 / padding 16 / 1px border / 淡陰影
struct CardStyle: ViewModifier {
    var pad: CGFloat = Theme.cardPad
    var radius: CGFloat = Theme.radius
    func body(content: Content) -> some View {
        content
            .padding(pad)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .shadow(color: Theme.shadow, radius: 6, x: 0, y: 2)
    }
}
// .input-warm：padding 14/16、bg --bg、1.5px border-strong、radius 12、15px
struct InputWarm: ViewModifier {
    var padV: CGFloat = 14
    var padH: CGFloat = 16
    var size: CGFloat = 15
    func body(content: Content) -> some View {
        content
            .font(WF.sans(size))
            .foregroundColor(Theme.text)
            .padding(.vertical, padV).padding(.horizontal, padH)
            .background(Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1.5))
    }
}
// 一般表單欄（網頁 p-2.5 bg surface-2 border-strong radius-xl text-sm）
struct FormField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(WF.sans(14))
            .foregroundColor(Theme.text)
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(Theme.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.borderStrong, lineWidth: 1))
    }
}
extension View {
    func card(pad: CGFloat = Theme.cardPad, radius: CGFloat = Theme.radius) -> some View { modifier(CardStyle(pad: pad, radius: radius)) }
    func inputWarm(padV: CGFloat = 14, padH: CGFloat = 16, size: CGFloat = 15) -> some View { modifier(InputWarm(padV: padV, padH: padH, size: size)) }
    func formField() -> some View { modifier(FormField()) }
    func screenBackground() -> some View { background(Theme.bg.ignoresSafeArea()) }
    // 網頁 .page：底部留 100px 給浮動分頁列
    func pageBody() -> some View { padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 110) }
    func noAutoCap() -> some View { textInputAutocapitalization(.never).autocorrectionDisabled() }
}

// .btn-warm：bg primary 白字 radius 12 padding 10/20 600 + 陰影
struct WarmButtonStyle: ButtonStyle {
    var padV: CGFloat = 10
    var padH: CGFloat = 20
    var size: CGFloat = 14
    var full: Bool = false
    var bg: Color = Theme.primary
    var fg: Color = .white
    var radius: CGFloat = 12
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WF.sans(size, .semibold))
            .frame(maxWidth: full ? .infinity : nil)
            .padding(.vertical, padV).padding(.horizontal, padH)
            .background(bg.opacity(configuration.isPressed ? 0.85 : 1))
            .foregroundColor(fg)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: bg.opacity(0.22), radius: 6, x: 0, y: 3)
    }
}
// 次要按鈕：bg surface-2、字 text
struct SoftButtonStyle: ButtonStyle {
    var padV: CGFloat = 10
    var padH: CGFloat = 16
    var size: CGFloat = 13
    var full: Bool = false
    var bg: Color = Theme.surface2
    var fg: Color = Theme.text
    var radius: CGFloat = 12
    var border: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WF.sans(size, .semibold))
            .frame(maxWidth: full ? .infinity : nil)
            .padding(.vertical, padV).padding(.horizontal, padH)
            .background(bg.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundColor(fg)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(border ? Theme.borderStrong : Color.clear, lineWidth: 1))
    }
}
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WF.sans(15, .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(configuration.isPressed ? Theme.primaryHover : Theme.primary)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// .page-title（Fraunces 22 600）／.section-title（18）／總覽 h1 26
struct PageTitle: View {
    let text: String
    var size: CGFloat = 22
    init(_ text: String, size: CGFloat = 22) { self.text = text; self.size = size }
    var body: some View { Text(text).font(WF.serif(size, .semibold)).foregroundColor(Theme.text) }
}
// .mono-label：DM Mono 10px 600 大寫 letter-spacing .1em text-3
struct MonoLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = Theme.text3
    init(_ text: String, size: CGFloat = 10, color: Color = Theme.text3) { self.text = text; self.size = size; self.color = color }
    var body: some View { Text(text.uppercased()).font(WF.mono(size, .semibold)).tracking(1).foregroundColor(color) }
}

// .tag（DM Mono 11 600 radius 6 padding 3/8）
enum TagKind { case success, error, warning, info }
struct Tag: View {
    let text: String
    var kind: TagKind = .info
    init(_ text: String, _ kind: TagKind = .info) { self.text = text; self.kind = kind }
    var fg: Color {
        switch kind {
        case .success: return Theme.success
        case .error: return Theme.tagError
        case .warning: return Theme.warning
        case .info: return Theme.primary
        }
    }
    var bg: Color {
        switch kind {
        case .success: return Color(hex: 0x4a8c5c, alpha: 0.1)
        case .error: return Color(hex: 0xb5341a, alpha: 0.1)
        case .warning: return Color(hex: 0xc49a2c, alpha: 0.1)
        case .info: return Theme.primarySoft
        }
    }
    var body: some View {
        Text(text).font(WF.mono(11, .semibold)).foregroundColor(fg)
            .padding(.vertical, 3).padding(.horizontal, 8).background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
// .chip（11 600 膠囊 padding 3/10 有框）
enum ChipKind { case success, info, warn, danger, muted, ai }
struct Chip: View {
    let text: String
    var kind: ChipKind = .muted
    init(_ text: String, _ kind: ChipKind = .muted) { self.text = text; self.kind = kind }
    var color: Color {
        switch kind {
        case .success: return Theme.success
        case .info: return Color(hex: 0x5b8fd6)
        case .warn: return Color(hex: 0xc79a2e)
        case .danger: return Color(hex: 0xd4543a)
        case .muted: return Theme.text2
        case .ai: return Color(hex: 0x8b5cf6)
        }
    }
    var body: some View {
        Text(text).font(WF.sans(11, .semibold)).foregroundColor(color)
            .padding(.vertical, 3).padding(.horizontal, 10)
            .background(color.opacity(0.1)).clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
    }
}
// BusyBadge：運算中（10px 粗 primary、5px 脈動點）
struct BusyBadge: View {
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.primary).frame(width: 5, height: 5).opacity(pulse ? 0.3 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            Text(L("運算中")).font(WF.sans(10, .bold)).foregroundColor(Theme.primary)
        }
        .padding(.vertical, 2).padding(.horizontal, 7)
        .background(Theme.primary.opacity(0.12)).clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.primary.opacity(0.35), lineWidth: 1))
        .onAppear { pulse = true }
    }
}
// .status-dot 10px：running #4caf50 發光 / stopped #555 / error #f44336
struct StatusDot: View {
    let running: Bool
    var error: Bool = false
    var size: CGFloat = 10
    var color: Color { error ? Color(hex: 0xf44336) : (running ? Color(hex: 0x4caf50) : Color(hex: 0x555555)) }
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .shadow(color: running && !error ? Color(hex: 0x4caf50, alpha: 0.6) : Color.clear, radius: 4)
    }
}
// .agent-avatar：42×42 radius 12（size*0.28），白粗首字，色＝AGENT_COLORS 或 charCode 雜湊調色盤
enum AgentColors {
    static let fixed: [String: UInt32] = ["COO": 0x5a7a65, "Worker-1": 0x2c6ec4, "Worker-2": 0xc43d7a, "Worker-3": 0xe07040, "Worker-4": 0x3d8ec4]
    static let palette: [UInt32] = [0xc25628, 0x5a7a65, 0x6b5ce7, 0xc49a2c, 0x2c6ec4, 0xc43d7a, 0xe07040, 0x3d8ec4]
    static func color(_ name: String) -> Color {
        if let f = fixed[name] { return Color(hex: f) }
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hex: palette[sum % palette.count])
    }
}
struct AgentAvatar: View {
    let name: String
    var size: CGFloat = 42
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(AgentColors.color(name))
            Text(String(name.prefix(1)).uppercased()).font(WF.sans(size * 0.38, .bold)).foregroundColor(.white)
        }.frame(width: size, height: size)
    }
}

// 子頁返回列：← 40×40 圓鈕 bg surface ＋ 16px 粗標題
struct BackHeader<Trailing: View>: View {
    let title: String
    var size: CGFloat = 16
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    init(title: String, size: CGFloat = 16, onBack: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title; self.size = size; self.onBack = onBack; self.trailing = trailing
    }
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Text("←").font(WF.sans(18, .medium)).foregroundColor(Theme.text)
                    .frame(width: 40, height: 40).background(Theme.surface).clipShape(Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            Text(title).font(WF.sans(size, .bold)).foregroundColor(Theme.text).lineLimit(1)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.bg)
    }
}
extension BackHeader where Trailing == EmptyView {
    init(title: String, size: CGFloat = 16, onBack: @escaping () -> Void) {
        self.init(title: title, size: size, onBack: onBack, trailing: { EmptyView() })
    }
}
// ModalSheet 表頭：36×4 把手 ＋ 18px 粗標題 ＋ ✕
struct SheetHeader: View {
    let title: String
    let onClose: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Capsule().fill(Theme.surface3).frame(width: 36, height: 4).padding(.top, 8)
            HStack {
                Text(title).font(WF.sans(18, .bold)).foregroundColor(Theme.text)
                Spacer()
                Button(action: onClose) { Text("✕").font(WF.sans(18)).foregroundColor(Theme.text2).frame(width: 32, height: 32) }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 6)
    }
}
struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String = ""
    var body: some View {
        VStack(spacing: 8) {
            Text(icon).font(.system(size: 40))
            Text(title).font(WF.sans(15, .semibold)).foregroundColor(Theme.text).multilineTextAlignment(.center)
            if !subtitle.isEmpty { Text(subtitle).font(WF.sans(13)).foregroundColor(Theme.text2).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 16)
    }
}
struct EmptyHint: View {
    let text: String
    var body: some View { EmptyState(icon: "📭", title: text) }
}
// 分段頁籤（surface-2 radius 12 p1；active bg primary 白字）
struct SegTabs: View {
    let items: [String]
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                Button { withAnimation(.easeInOut(duration: 0.15)) { selection = i }; Haptic.select() } label: {
                    Text(items[i]).font(WF.sans(13, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(selection == i ? Theme.primary : Color.clear)
                        .foregroundColor(selection == i ? Color.white : Theme.text2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .padding(4).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
// 篩選膠囊（padding 6/14 radius 20 12px 600；active bg primary 白字＋陰影）
struct FilterPill: View {
    let label: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(WF.sans(12, .semibold))
                .padding(.vertical, 6).padding(.horizontal, 14)
                .background(active ? Theme.primary : Theme.surface)
                .foregroundColor(active ? Color.white : Theme.text2)
                .clipShape(Capsule())
                .shadow(color: active ? Theme.primary.opacity(0.3) : Color.clear, radius: 5, x: 0, y: 2)
        }
    }
}
// 錯誤導覽用的滑動開關（44×26，開 #E07A3F）
struct WebSwitch: View {
    let on: Bool
    var body: some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? Color(hex: 0xe07a3f) : Theme.surface3).frame(width: 44, height: 26)
            Circle().fill(Color.white).frame(width: 20, height: 20).padding(3).shadow(color: Color.black.opacity(0.25), radius: 1.5, y: 1)
        }.animation(.easeInOut(duration: 0.2), value: on)
    }
}
// Toast（頂端置中）
struct ToastView: View {
    let msg: ToastMsg
    var color: Color { msg.kind == "error" ? Theme.danger : (msg.kind == "success" ? Theme.success : Theme.text) }
    var body: some View {
        Text(msg.text).font(WF.sans(13, .semibold)).foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10).padding(.horizontal, 16)
            .background(color.opacity(0.95)).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 10, y: 4)
            .padding(.horizontal, 24)
    }
}

// 通用載入器
struct Loader<T: Decodable, Content: View>: View {
    @EnvironmentObject var state: AppState
    let path: String
    var timeout: TimeInterval = 25
    @ViewBuilder var content: (T, @escaping () async -> Void) -> Content
    @State private var value: T?
    @State private var err: String?
    var body: some View {
        Group {
            if let v = value { content(v, load) }
            else if let err {
                VStack(spacing: 10) {
                    Text(err).font(WF.sans(13)).foregroundColor(Theme.danger).multilineTextAlignment(.center)
                    Button(L("重試")) { Task { await load() } }.buttonStyle(SoftButtonStyle())
                }.frame(maxWidth: .infinity).padding(30)
            } else { ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding(40) }
        }
        .task { await load() }
    }
    private func load() async {
        do { let v: T = try await state.api.request(path, timeout: timeout); value = v; err = nil }
        catch { if value == nil { err = error.localizedDescription } }
    }
}

enum Haptic {
    static func tap()     { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium()  { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func select()  { UISelectionFeedbackGenerator().selectionChanged() }
}

extension Date {
    static func fromUnix(_ ts: Double?) -> Date? { ts.map { Date(timeIntervalSince1970: $0 > 1e12 ? $0 / 1000 : $0) } }
}
enum Fmt {
    // 網頁 fmtTokens
    static func tokens(_ n: Double) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", n / 1_000) }
        return String(format: "%.0f", n)
    }
    static let grouping: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f }()
    static func num(_ n: Double) -> String { grouping.string(from: NSNumber(value: n)) ?? String(Int(n)) }
    static func num(_ n: Int) -> String { grouping.string(from: NSNumber(value: n)) ?? String(n) }
    static func bytes(_ b: Int) -> String {
        let n = Double(b)
        if n > 1e9 { return String(format: "%.1f GB", n / 1e9) }
        if n > 1e6 { return String(format: "%.1f MB", n / 1e6) }
        return "\(Int((n / 1e3).rounded())) KB"
    }
    static let tw: DateFormatter = { let f = DateFormatter(); f.timeZone = TimeZone(identifier: "Asia/Taipei"); f.dateFormat = "MM/dd HH:mm"; return f }()
    static let twTime: DateFormatter = { let f = DateFormatter(); f.timeZone = TimeZone(identifier: "Asia/Taipei"); f.dateFormat = "HH:mm"; return f }()
    static let twFull: DateFormatter = { let f = DateFormatter(); f.timeZone = TimeZone(identifier: "Asia/Taipei"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()
    static func hhmm(_ ts: Double?) -> String { guard let d = Date.fromUnix(ts) else { return "" }; return twTime.string(from: d) }
    static func when(_ ts: Double?) -> String {
        guard let d = Date.fromUnix(ts) else { return "" }
        return Calendar.current.isDateInToday(d) ? twTime.string(from: d) : tw.string(from: d)
    }
    static func uptime(_ s: Int) -> String { "\(s / 3600)h \((s % 3600) / 60)m" }
    // 網頁 fmtTime：ISO → 'YYYY-MM-DD HH:MM'
    static func isoShort(_ s: String) -> String { String(s.replacingOccurrences(of: "T", with: " ").prefix(16)) }
    static func iso(_ s: String) -> String {
        let p = ISO8601DateFormatter(); p.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = p.date(from: s) { return tw.string(from: d) }
        p.formatOptions = [.withInternetDateTime]
        if let d = p.date(from: s) { return tw.string(from: d) }
        return String(s.prefix(16))
    }
    static func isoFull(_ s: String) -> String {
        let p = ISO8601DateFormatter(); p.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = p.date(from: s) { return twFull.string(from: d) }
        p.formatOptions = [.withInternetDateTime]
        if let d = p.date(from: s) { return twFull.string(from: d) }
        return String(s.replacingOccurrences(of: "T", with: " ").prefix(19))
    }
}
