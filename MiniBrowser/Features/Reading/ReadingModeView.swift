import SwiftUI

/// 阅读模式：去除干扰，仅标题/正文/图片。底部翻页与进度，可调字体背景。
struct ReadingModeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false
    @State private var fontSize: CGFloat = 18
    @State private var bg: ReadBG = .paper
    @State private var page = 3

    enum ReadBG: CaseIterable { case white, paper, gray, black
        var color: Color {
            switch self {
            case .white: return .white
            case .paper: return Color(hex: 0xF3ECD8)
            case .gray: return Color(hex: 0xC9C9C9)
            case .black: return Color(hex: 0x1A1A1A)
            }
        }
        var text: Color { self == .black ? Color(hex: 0xCFCFCF) : Color(hex: 0x222222) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("沉浸式阅读：让长文回归纯粹")
                        .font(.system(size: fontSize + 8, weight: .bold))
                        .foregroundStyle(bg.text)
                    Text("来源 · example.com    阅读时长约 6 分钟")
                        .font(.system(size: 13)).foregroundStyle(bg.text.opacity(0.5))
                    ForEach(0..<8, id: \.self) { i in
                        Text(Self.paragraph(i))
                            .font(.system(size: fontSize))
                            .lineSpacing(fontSize * 0.45)
                            .foregroundStyle(bg.text)
                    }
                }
                .padding(Theme.Spacing.xl)
            }
            Hairline()
            HStack {
                Button { } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text("\(page) / 12").font(.system(size: 13)).foregroundStyle(bg.text.opacity(0.6))
                Spacer()
                Button { } label: { Image(systemName: "chevron.right") }
            }
            .foregroundStyle(bg.text)
            .padding(.horizontal, Theme.Spacing.xl).frame(height: 44)
        }
        .background(bg.color.ignoresSafeArea())
        .navigationTitle("阅读模式").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(bg.color, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("返回") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "textformat.size") }
            }
        }
        .sheet(isPresented: $showSettings) {
            ReadingSettingsSheet(fontSize: $fontSize, bg: $bg)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
    }

    static func paragraph(_ i: Int) -> String {
        ["阅读模式会自动识别文章主体，剔除广告、侧边栏、评论与脚本干扰，只保留对阅读真正有价值的内容。",
         "你可以自由调整字体大小、字体类型、行距、段距与页面宽度，找到最舒适的阅读节奏。",
         "支持白色、米色、灰色与夜间黑色四种背景，配合护眼色长时间阅读也不易疲劳。",
         "针对小说和长文章，阅读模式提供智能拼页与连续滚动两种方式，翻页顺滑自然。",
         "点击屏幕左右两侧即可快速翻页，也可以使用底部翻页按钮或上下滑动浏览。",
         "简繁转换让你在不同地区的内容之间自由切换，阅读无障碍。",
         "所有排版参数都会被记住，下次进入阅读模式时自动恢复你的偏好设置。",
         "返回即可回到原始网页，阅读模式只是叠加在网页之上的一层纯净视图。"][i % 8]
    }
}

struct ReadingSettingsSheet: View {
    @Binding var fontSize: CGFloat
    @Binding var bg: ReadingModeView.ReadBG
    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Capsule().fill(Theme.Colors.separator).frame(width: 36, height: 5).padding(.top, 8)
            HStack {
                Text("A").font(.system(size: 14))
                Slider(value: $fontSize, in: 14...26, step: 1)
                Text("A").font(.system(size: 24))
            }
            HStack(spacing: Theme.Spacing.l) {
                ForEach(ReadingModeView.ReadBG.allCases, id: \.self) { c in
                    Circle().fill(c.color)
                        .frame(width: 38, height: 38)
                        .overlay(Circle().strokeBorder(c == bg ? Theme.Colors.accent : Theme.Colors.separator, lineWidth: c == bg ? 2.5 : 1))
                        .onTapGesture { bg = c }
                }
            }
            HStack(spacing: Theme.Spacing.xl) {
                labelToggle("上下滚动", "arrow.up.arrow.down")
                labelToggle("点击翻页", "hand.tap")
                labelToggle("简繁转换", "character")
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.xl)
    }
    private func labelToggle(_ t: String, _ s: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: s).font(.system(size: 20)).foregroundStyle(Theme.Colors.accent)
            Text(t).font(.system(size: 11)).foregroundStyle(Theme.Colors.secondaryText)
        }
    }
}
