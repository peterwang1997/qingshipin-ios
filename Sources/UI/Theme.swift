import SwiftUI

/// 与安卓端 colors.xml 一一对应的配色
enum Theme {
    static let primary = Color(hex: 0x1F7AFF)
    static let primaryDark = Color(hex: 0x0D47A1)
    static let accent = Color(hex: 0xFF6D00)
    static let background = Color(hex: 0x0E0E12)
    static let surface = Color(hex: 0x1A1A22)
    static let surfaceLight = Color(hex: 0x24242E)
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x9E9E9E)
    static let divider = Color(hex: 0x2A2A35)
    static let danger = Color(hex: 0xFF5252)
    static let episodeSelected = Color(hex: 0xFF8A3D)

    /// 底部渐变压暗效果（对应 bg_feed_gradient）
    static let feedGradient = LinearGradient(
        colors: [Color.black.opacity(0.8), Color.black.opacity(0)],
        startPoint: .bottom,
        endPoint: .top
    )

    static let cornerCard: CGFloat = 12
    static let cornerCover: CGFloat = 10

    /// 播放器顶栏内容高度（安卓为 52dp）
    static let playerBarHeight: CGFloat = 52
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// 屏幕尺寸工具：iPhone 15 Pro Max 为 430×932pt，这里统一按安全区动态适配
enum Screen {
    static var bounds: CGRect { UIScreen.main.bounds }
    static var width: CGFloat { UIScreen.main.bounds.width }
    static var height: CGFloat { UIScreen.main.bounds.height }
    static var isCompactHeight: Bool { height < 800 }
    /// 剧场两列卡片的封面高度：按卡片宽度 3:2 计算（与安卓 setCover 一致）
    static func coverHeight(forColumnWidth w: CGFloat) -> CGFloat {
        max((w * 3 / 2).rounded(), 120)
    }
}

extension String {
    /// 秒 → mm:ss
    func clockText(seconds: Double) -> String { String.clockText(seconds) }
}

extension String {
    static func clockText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
