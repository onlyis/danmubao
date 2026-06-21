import SwiftUI

/// 站点图标：圆角方形 + 品牌色 + 字形（或 SF Symbol）。
/// 无品牌资产时以纯色块 + 文字呈现，保持干净不抢视觉。
struct SiteIcon: View {
    var glyph: String
    var color: Color
    var symbol: String? = nil
    var size: CGFloat = Theme.Size.quickLinkIcon
    var corner: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    Text(glyph)
                        .font(.system(size: glyph.count > 1 ? size * 0.30 : size * 0.46,
                                      weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.04), lineWidth: Theme.Size.hairline)
            )
    }
}

/// 小尺寸列表用站点图标
struct SiteIconSmall: View {
    var glyph: String
    var color: Color
    var symbol: String? = nil
    var body: some View {
        SiteIcon(glyph: glyph, color: color, symbol: symbol, size: 30, corner: 7)
    }
}
