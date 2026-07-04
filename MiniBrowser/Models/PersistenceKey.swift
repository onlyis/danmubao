import Foundation

/// 集中式持久化文件名常量。
///
/// 所有通过 `DiskStore.save/saveAsync/load/write` 落盘到 Documents 目录的 JSON
/// 文件名统一在此声明，避免散落在各处的 "xxx.json" 硬编码字符串导致拼写漂移、
/// 难以检索与重命名。新增持久化项时只需在此添加一个语义化常量。
///
/// 约定：常量名表达「存什么」，常量值即真实文件名（保持与历史落盘文件一致，
/// 不可随意更改值，否则旧用户数据将无法读取）。
enum PersistenceKey {
    // MARK: 浏览器主视图模型(BrowserViewModel)

    /// 快速链接(首页九宫格)
    static let quickLinks = "quicklinks.json"
    /// 夜间模式开关
    static let nightMode = "night.json"
    /// 手势配置
    static let gestures = "gestures.json"
    /// 工具栏按钮配置
    static let toolbar = "toolbar.json"
    /// 菜单项配置
    static let menu = "menu.json"
    /// 面板项配置
    static let panel = "panel.json"
    /// 导航目录展开状态
    static let navExpanded = "nav_expanded.json"
    /// 当前搜索引擎
    static let searchEngine = "search_engine.json"
    /// 自定义搜索引擎列表
    static let customEngines = "custom_engines.json"
    /// 搜索历史
    static let searchHistory = "search_history.json"
    /// 拦截重定向开关
    static let blockRedirects = "block_redirects.json"
    /// 是否显示导航目录
    static let showNavDirectory = "show_nav_directory.json"
    /// 新标签页是否打开主页
    static let newTabOpensHomepage = "new_tab_opens_homepage.json"
    /// 主页地址
    static let homepageURL = "homepage_url.json"
    /// 默认视频播放倍速
    static let defaultVideoRate = "default_video_rate.json"
    /// 搜索框位置（顶部 / 键盘上方）
    static let searchBarAtTop = "search_bar_at_top.json"
    /// App 语言（跟随系统 / 中文 / English）
    static let appLanguage = "app_language.json"
    /// 标签页状态(用于恢复)
    static let tabs = "tabs.json"

    // MARK: 各功能存储

    /// 广告元素隐藏规则(AdHideStore)
    static let adHide = "adhide.json"
    /// 书签(LibraryStore)
    static let bookmarks = "bookmarks.json"
    /// 浏览历史(LibraryStore)
    static let history = "history.json"
    /// 插件状态(PluginStore)
    static let plugins = "plugins.json"
    /// 稍后读列表(ReadingListStore)
    static let readingList = "readinglist.json"
    /// 用户脚本(UserScriptStore)
    static let userScripts = "userscripts.json"
}
