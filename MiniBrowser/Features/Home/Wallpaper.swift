import SwiftUI

/// 主页沉浸式壁纸。壁纸保持低存在感，确保搜索框与文字清晰。
enum Wallpaper: String, CaseIterable, Identifiable {
    case none = "系统默认"
    case paper = "纯色 · 米白"
    case slate = "纯色 · 石墨"
    case sunset = "渐变 · 晚霞"
    case ocean = "渐变 · 海洋"
    case aurora = "渐变 · 极光"
    case blur = "模糊照片"

    var id: String { rawValue }

    /// 该壁纸下是否更适合浅色文字
    var prefersLightText: Bool {
        switch self {
        case .none, .paper: return false
        default: return true
        }
    }

    @ViewBuilder
    var background: some View {
        switch self {
        case .none:
            Theme.Colors.background
        case .paper:
            Color(hex: 0xF3EFE6)
        case .slate:
            Color(hex: 0x2E3338)
        case .sunset:
            LinearGradient(colors: [Color(hex: 0xFF8A65), Color(hex: 0xF06292), Color(hex: 0x7E57C2)],
                           startPoint: .top, endPoint: .bottom)
        case .ocean:
            LinearGradient(colors: [Color(hex: 0x4FC3F7), Color(hex: 0x2979FF), Color(hex: 0x1A237E)],
                           startPoint: .top, endPoint: .bottom)
        case .aurora:
            LinearGradient(colors: [Color(hex: 0x00C9A7), Color(hex: 0x2B86C5), Color(hex: 0x845EC2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        case .blur:
            // 用 GeometryReader 让光斑按容器尺寸缩放：全屏壁纸与设置页小缩略图都比例正确
            // （原来固定 260/220pt 在 150pt 高的缩略图里会撑爆、错位）。
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x355C7D), Color(hex: 0x6C5B7B), Color(hex: 0xC06C84)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(.white.opacity(0.18))
                        .frame(width: s * 1.1).blur(radius: s * 0.24)
                        .offset(x: -geo.size.width * 0.35, y: -geo.size.height * 0.4)
                    Circle().fill(Color(hex: 0xFFD54F).opacity(0.25))
                        .frame(width: s * 0.9).blur(radius: s * 0.28)
                        .offset(x: geo.size.width * 0.35, y: geo.size.height * 0.35)
                }
            }
        }
    }

    /// 缩略图（设置页选择用）
    @ViewBuilder
    var thumbnail: some View {
        background
    }
}

/// 壁纸背景容器：壁纸 + 顶部到底部的轻微暗化渐变，保证内容可读。
struct WallpaperBackground: View {
    let wallpaper: Wallpaper
    var body: some View {
        wallpaper.background
            .overlay(
                LinearGradient(colors: [.black.opacity(wallpaper == .none ? 0 : 0.05), .clear],
                               startPoint: .top, endPoint: .center)
            )
            .ignoresSafeArea()
    }
}
