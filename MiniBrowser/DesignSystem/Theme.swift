import SwiftUI

/// 全局设计令牌：颜色、间距、圆角、字体。
/// 视觉关键词：极简、白底、浅灰分割线、黑色文字、蓝/绿强调色。
enum Theme {

    // MARK: - 颜色
    enum Colors {
        /// 页面背景：浅色浅灰 #F2F2F7，深色近黑（随系统自适应）
        static let background = Color(uiColor: UIColor { tc in
            tc.userInterfaceStyle == .dark
                ? UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
                : UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1)
        })
        /// 卡片 / 内容背景（纯白）
        static let card = Color(.systemBackground)
        /// 二级背景
        static let groupedBackground = Color(.secondarySystemBackground)
        /// 极细分割线
        static let separator = Color(.separator)
        /// 主文字（黑）
        static let primaryText = Color(.label)
        /// 辅助文字（灰）
        static let secondaryText = Color(.secondaryLabel)
        static let tertiaryText = Color(.tertiaryLabel)
        /// 蓝色强调色
        static let accent = Color(hex: 0x0A84FF)
        /// 绿色强调色（安全 / 盾牌）
        static let safe = Color(hex: 0x34C759)
        /// 危险操作（删除等）
        static let danger = Color(hex: 0xFF3B30)
        /// 工具栏图标
        static let toolbarIcon = Color(.label)
        static let toolbarDisabled = Color(.tertiaryLabel)
        /// 无痕模式紫
        static let incognito = Color(hex: 0x5E5CE6)
    }

    // MARK: - 间距
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }

    // MARK: - 圆角
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let pill: CGFloat = 22
        static let sheet: CGFloat = 16
    }

    // MARK: - 尺寸
    enum Size {
        static let toolbarHeight: CGFloat = 49
        static let searchBarHeight: CGFloat = 44
        static let quickLinkIcon: CGFloat = 60
        static let hairline: CGFloat = 1.0 / 3.0
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// 极细分割线
struct Hairline: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: Theme.Size.hairline)
            .padding(.leading, inset)
    }
}
