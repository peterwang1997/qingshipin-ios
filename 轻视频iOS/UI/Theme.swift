import SwiftUI
import UIKit

/// 全局尺寸与字号。
/// 以 iPhone 15 Pro 的 393pt 屏幕宽度为设计基准，在 15 Pro Max 等更宽的机型上等比放大，
/// 小屏机型（375pt 及以下）保持 1.0，不做缩放。
enum UI {

    /// 当前窗口宽度（取前台活跃场景，避免用到过期的尺寸）
    static var screenWidth: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return active?.screen.bounds.width ?? 393
    }

    /// 缩放倍率：393pt 基准，最大 1.5 倍
    static var scale: CGFloat {
        min(max(screenWidth / 393, 1.0), 1.5)
    }

    /// 字号
    static func font(_ base: CGFloat) -> CGFloat {
        (base * scale).rounded()
    }

    /// 尺寸（宽高、间距、圆角、内边距）
    static func size(_ base: CGFloat) -> CGFloat {
        (base * scale).rounded()
    }

    // MARK: 常用字号档位

    /// 特大标题（登录页应用名）
    static var display: CGFloat { font(40) }
    /// 页面标题
    static var title: CGFloat { font(26) }
    /// 卡片 / 列表主标题
    static var headline: CGFloat { font(19) }
    /// 正文
    static var body: CGFloat { font(17) }
    /// 说明文字
    static var note: CGFloat { font(14.5) }
    /// 辅助小字
    static var fine: CGFloat { font(13) }

    // MARK: 常用尺寸

    /// 页面左右边距
    static var hPad: CGFloat { size(18) }
    /// 可点击区域最小边长（苹果建议 44pt，随屏幕放大）
    static var tapTarget: CGFloat { size(46) }
}
