import SwiftUI

/// 网址导航站点
struct NavSite: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let glyph: String
    let colorHex: UInt
    var color: Color { Color(hex: colorHex) }
}

/// 导航分类
struct NavCategory: Identifiable {
    let id = UUID()
    let title: String
    let sites: [NavSite]
}

/// 内置网址导航目录（首页第二屏）
enum NavCatalog {
    static let categories: [NavCategory] = [
        .init(title: "常用", sites: [
            .init(name: "百度", url: "baidu.com", glyph: "百", colorHex: 0x2932E1),
            .init(name: "微博", url: "weibo.com", glyph: "微", colorHex: 0xE6162D),
            .init(name: "知乎", url: "zhihu.com", glyph: "知", colorHex: 0x0066FF),
            .init(name: "豆瓣", url: "douban.com", glyph: "豆", colorHex: 0x2D963D),
            .init(name: "贴吧", url: "tieba.baidu.com", glyph: "贴", colorHex: 0x3385FF),
        ]),
        .init(title: "视频影音", sites: [
            .init(name: "优酷", url: "youku.com", glyph: "优", colorHex: 0x1AA1E1),
            .init(name: "腾讯视频", url: "v.qq.com", glyph: "腾", colorHex: 0xFF9B00),
            .init(name: "爱奇艺", url: "iqiyi.com", glyph: "爱", colorHex: 0x00BE06),
            .init(name: "芒果TV", url: "mgtv.com", glyph: "芒", colorHex: 0xFF6600),
            .init(name: "bilibili", url: "bilibili.com", glyph: "B", colorHex: 0xFB7299),
        ]),
        .init(title: "购物", sites: [
            .init(name: "淘宝", url: "taobao.com", glyph: "淘", colorHex: 0xFF4400),
            .init(name: "天猫", url: "tmall.com", glyph: "猫", colorHex: 0xFF0036),
            .init(name: "京东", url: "jd.com", glyph: "京", colorHex: 0xE3101E),
            .init(name: "拼多多", url: "pinduoduo.com", glyph: "拼", colorHex: 0xE22E1F),
            .init(name: "唯品会", url: "vip.com", glyph: "唯", colorHex: 0xE10F46),
        ]),
        .init(title: "社交资讯", sites: [
            .init(name: "小红书", url: "xiaohongshu.com", glyph: "红", colorHex: 0xFF2442),
            .init(name: "抖音", url: "douyin.com", glyph: "抖", colorHex: 0x161823),
            .init(name: "今日头条", url: "toutiao.com", glyph: "头", colorHex: 0xED4040),
            .init(name: "腾讯新闻", url: "news.qq.com", glyph: "讯", colorHex: 0x2E7CF6),
            .init(name: "网易", url: "163.com", glyph: "网", colorHex: 0xD8232A),
        ]),
        .init(title: "工具", sites: [
            .init(name: "百度翻译", url: "fanyi.baidu.com", glyph: "译", colorHex: 0x4E6EF2),
            .init(name: "有道", url: "youdao.com", glyph: "有", colorHex: 0xD7000F),
            .init(name: "12306", url: "12306.cn", glyph: "铁", colorHex: 0x2A7BD8),
            .init(name: "快递100", url: "kuaidi100.com", glyph: "递", colorHex: 0x00A0E9),
            .init(name: "GitHub", url: "github.com", glyph: "G", colorHex: 0x24292E),
        ]),
    ]
}

/// 网址导航目录视图（首页第二屏）：可展开分类——点击分类标题，下方展开/收起子网格。
struct NavDirectoryView: View {
    @EnvironmentObject var vm: BrowserViewModel
    var lightText: Bool = false
    @State private var expanded: Set<String> = ["常用"]   // 默认展开第一个
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(NavCatalog.categories) { cat in
                    VStack(spacing: 0) {
                        Button {
                            Haptics.light()
                            withAnimation(.easeInOut(duration: 0.22)) {
                                if expanded.contains(cat.title) { expanded.remove(cat.title) }
                                else { expanded.insert(cat.title) }
                            }
                        } label: {
                            HStack {
                                Text(cat.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.primaryText)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.tertiaryText)
                                    .rotationEffect(.degrees(expanded.contains(cat.title) ? 0 : -90))
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if expanded.contains(cat.title) {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(cat.sites) { site in
                                    Button { Haptics.light(); vm.open(url: site.url, title: site.name) } label: {
                                        VStack(spacing: 5) {
                                            SiteIcon(glyph: site.glyph, color: site.color, size: 44, corner: 12)
                                            Text(site.name)
                                                .font(.system(size: 10))
                                                .foregroundStyle(Theme.Colors.secondaryText)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 14)
                        }
                    }
                    .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
        }
    }
}
