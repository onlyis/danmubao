import SwiftUI

/// 站点宫格图标：按品牌渲染原创化的简约标识（品牌色 + 渐变 + 几何标记/首字），
/// 非品牌商标的像素级复刻。未识别的站点回退为字形色块。
struct BrandIcon: View {
    let link: QuickLink
    var size: CGFloat = Theme.Size.quickLinkIcon

    private var key: String { link.url.lowercased() }
    private var corner: CGFloat { size * 0.23 }

    var body: some View {
        Group {
            switch true {
            case key.contains("baidu"):      glyphTile(grad(0x2B5BE0, 0x3E7BFF), symbol: "pawprint.fill")
            case key.contains("google"):     googleTile
            case key.contains("bing"):       letterTile(.white, fg: Color(hex: 0x0E8C7F), text: "b", italic: true, bordered: true)
            case key.contains("sogou"):      glyphTile(grad(0xFF7A2F, 0xFB5B16), symbol: "magnifyingglass")
            case key.contains("so.com"):     letterTile(grad2(0x16C172, 0x0FA85F), fg: .white, text: "360")
            case key.contains("youku"):      glyphTile(grad(0x18A0E8, 0x0E7FD6), symbol: "play.fill")
            case key.contains("v.qq"):       glyphTile(grad(0xFFB02E, 0xFF7A00), symbol: "play.fill")
            case key.contains("weibo"):      glyphTile(grad(0xF0334A, 0xD81E32), symbol: "eye.fill")
            case key.contains("zhihu"):      letterTile(grad2(0x1E6FFF, 0x0858E6), fg: .white, text: "知")
            case key.contains("bilibili"):   glyphTile(grad(0x29B7E6, 0x00A1D6), symbol: "tv.fill")
            case key.contains("sm.cn"):      letterTile(grad2(0xFF9020, 0xFF7400), fg: .white, text: "神")
            case link.symbol != nil:         glyphTile(grad2Color(link.color), symbol: link.symbol!)
            default:                          letterTile(grad2Color(link.color), fg: .white, text: link.glyph)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
    }

    // MARK: - 构件
    private func tileBackground(_ fill: some ShapeStyle, bordered: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.black.opacity(bordered ? 0.06 : 0.03),
                                  lineWidth: Theme.Size.hairline)
            )
    }

    private func glyphTile(_ fill: some ShapeStyle, symbol: String) -> some View {
        tileBackground(fill)
            .overlay(Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white))
    }

    private func letterTile(_ fill: some ShapeStyle, fg: Color, text: String, italic: Bool = false, bordered: Bool = false) -> some View {
        tileBackground(fill, bordered: bordered)
            .overlay(
                Text(text)
                    .font(.system(size: text.count > 1 ? size * 0.30 : size * 0.46,
                                  weight: .bold, design: .rounded))
                    .italic(italic)
                    .foregroundStyle(fg)
                    .minimumScaleFactor(0.5).lineLimit(1).padding(.horizontal, 4)
            )
    }

    /// Google 风格多色环（原创简化标记）
    private var googleTile: some View {
        let w = size * 0.14
        let arcInset = size * 0.26
        return tileBackground(Color.white, bordered: true)
            .overlay {
                ZStack {
                    arc(0.00, 0.25, Color(hex: 0x4285F4), w)   // 蓝
                    arc(0.25, 0.50, Color(hex: 0x34A853), w)   // 绿
                    arc(0.50, 0.75, Color(hex: 0xFBBC05), w)   // 黄
                    arc(0.75, 1.00, Color(hex: 0xEA4335), w)   // 红
                    // 中央蓝色横杠
                    Capsule()
                        .fill(Color(hex: 0x4285F4))
                        .frame(width: size * 0.22, height: w)
                        .offset(x: size * 0.11)
                }
                .padding(arcInset)
            }
    }

    private func arc(_ from: CGFloat, _ to: CGFloat, _ color: Color, _ w: CGFloat) -> some View {
        Circle()
            .trim(from: from, to: to)
            .stroke(color, style: StrokeStyle(lineWidth: w, lineCap: .butt))
    }

    // MARK: - 渐变工具
    private func grad(_ a: UInt, _ b: UInt) -> LinearGradient {
        LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .top, endPoint: .bottom)
    }
    private func grad2(_ a: UInt, _ b: UInt) -> LinearGradient { grad(a, b) }
    private func grad2Color(_ c: Color) -> LinearGradient {
        LinearGradient(colors: [c, c.opacity(0.82)], startPoint: .top, endPoint: .bottom)
    }
}
