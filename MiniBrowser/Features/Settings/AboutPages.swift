import SwiftUI

// MARK: - 关于：静态内容页（更新日志 / 隐私政策 / 用户协议）
// 纯 ScrollView + Text 排版，避免 List/Section(_:) 的错误重载；中文 UI 与注释。

/// 段落标题样式
private struct ContentHeading: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.Colors.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

/// 正文段落样式
private struct ContentBody: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Theme.Colors.secondaryText)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 复用：静态内容页容器
private struct StaticContentPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                content
            }
            .padding(Theme.Spacing.l)
            .padding(.bottom, 40)
        }
        .background(Theme.Colors.groupedBackground.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 更新日志
struct ChangelogView: View {
    var body: some View {
        StaticContentPage(title: "更新日志") {
            ContentHeading(text: "版本 1.0 (1)　2026-06-22")
            ContentBody("· 全新发布：极简多标签浏览器，支持真实网页浏览与历史、书签持久化。\n· 新增手势按钮：悬浮按钮拖出笔画手势触发后退、前进、新建/关闭标签、刷新等操作，支持圆形手势与直线容差调节。\n· 新增插件市场：广告拦截基于系统内容拦截规则，真实生效。\n· 新增看图模式、漫画阅读、视频悬浮控制条、网页翻译（系统翻译框架）。\n· 新增文件管理与 zip 压缩 / 解压、下载断点续传。\n· 新增沉浸式壁纸、OLED 纯黑、跟随系统的深浅外观。")

            ContentHeading(text: "早期内测")
            ContentBody("· 搭建多标签独立引擎架构与引擎复用池，海量标签下保持流畅。\n· 完善设置中心：通用、主页、自定义、搜索引擎、隐私安全等分组。\n· 优化磁盘写入与历史记录性能，导航不再卡顿主线程。")

            ContentBody("感谢你的使用与反馈，我们会持续打磨每一个细节。")
        }
    }
}

// MARK: - 隐私政策
struct PrivacyPolicyView: View {
    var body: some View {
        StaticContentPage(title: "隐私政策") {
            ContentBody("我们高度重视你的隐私。本浏览器在设计上坚持「数据尽量留在本机」的原则，以下说明我们如何处理你的信息。")

            ContentHeading(text: "一、我们收集的信息")
            ContentBody("本应用不设置自有服务器账号，不要求注册。浏览历史、书签、下载文件、标签会话、搜索记录等数据均存储在你的设备本地（应用沙盒目录）。若你开启 iCloud 同步，书签与历史会通过你的 iCloud 私有数据库在你自己的设备间同步，我们无法访问。")

            ContentHeading(text: "二、信息的使用")
            ContentBody("本地数据仅用于实现浏览器自身功能，例如恢复上次标签、提供历史与搜索建议、展示常用网站。我们不会将这些数据用于广告画像，也不会出售给第三方。")

            ContentHeading(text: "三、网络请求")
            ContentBody("当你访问网页时，请求由系统 WebKit 直接发往你访问的网站，遵循该网站自身的隐私政策。搜索关键词会发送给你在「搜索引擎」设置中选择的搜索服务商。")

            ContentHeading(text: "四、权限说明")
            ContentBody("· 相机：仅在你使用二维码扫描时请求，用于识别二维码。\n· 相册：仅在你保存网页图片时请求，用于写入图片。\n以上权限均按需申请，你可随时在系统设置中关闭。")

            ContentHeading(text: "五、数据的清除")
            ContentBody("你可以在「设置 → 清除浏览数据」中删除历史、Cookie、缓存等本地数据。卸载应用会清除全部本地数据。无痕浏览模式下的会话与 Cookie 仅存于内存，退出即清空。")

            ContentHeading(text: "六、政策更新")
            ContentBody("如本政策有重大变更，我们会在应用内更新日志中说明。继续使用即表示你接受更新后的政策。")

            ContentBody("最近更新日期：2026-06-22")
        }
    }
}

// MARK: - 用户协议
struct UserAgreementView: View {
    var body: some View {
        StaticContentPage(title: "用户协议") {
            ContentBody("欢迎使用本浏览器。在使用本应用前，请你仔细阅读并理解以下条款。当你开始使用本应用时，即视为你已接受本协议的全部内容。")

            ContentHeading(text: "一、服务说明")
            ContentBody("本应用是一款运行于 iOS 设备上的网页浏览工具，向你提供网页浏览、书签、历史、下载、文件管理等功能。本应用基于系统 WebKit 渲染网页，不对所访问网站的内容负责。")

            ContentHeading(text: "二、用户行为规范")
            ContentBody("你应遵守所在地区的法律法规，不得利用本应用从事任何违法或侵害他人合法权益的活动。你访问的网页内容由相应网站提供，与本应用开发者无关。")

            ContentHeading(text: "三、知识产权")
            ContentBody("本应用的界面设计、图标与代码受相关法律保护。应用内品牌图标为原创简化标识，仅用于功能识别，不代表与相应品牌方存在关联或授权关系。")

            ContentHeading(text: "四、免责声明")
            ContentBody("本应用按「现状」提供，不对网页加载结果、第三方网站内容、网络可用性作任何明示或默示担保。在法律允许的范围内，因使用本应用导致的任何直接或间接损失，开发者不承担责任。")

            ContentHeading(text: "五、协议变更")
            ContentBody("我们可能不时更新本协议，更新内容会在应用更新日志中体现。若你不同意变更后的条款，应停止使用本应用。")

            ContentBody("最近更新日期：2026-06-22")
        }
    }
}
