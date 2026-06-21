# MiniBrowser 项目交接文档

> 仿 Alook 浏览器的 iOS App（SwiftUI）。本文件供下一会话 / 其他账号接手时阅读。
> 最后更新：2026-06-21

---

## 1. 一句话现状

一个 **可真实多标签浏览网页** 的 Alook 风格极简浏览器，UI 精细、29 个模块界面与流程齐备；
网页（WKWebView）、下载（URLSession）、文件系统、zip 压缩解压、书签/历史持久化、壁纸/OLED 主题均为**真实实现**，其余高级功能为 UI + 流程占位。
当前 `xcodebuild` **BUILD SUCCEEDED**，模拟器可正常运行。

原始需求：模仿 Alook 浏览器、尽量 UI 一致、Swift、iOS 手机端。第一阶段「只要 UI、功能可不实现、流程要有、UI 是重点且精细」，后续逐步把功能做真。

---

## 2. 环境与构建

- **Xcode 26.0 / Swift 6.2**（Swift 6 并发模式，注意 actor 隔离）
- 工程由 **xcodegen** 从 `project.yml` 生成（`MiniBrowser.xcodeproj` 已被 `.gitignore` 忽略，可随时重建）
- Bundle id：`com.example.minibrowser`，部署目标 iOS 17.0，仅 iPhone
- `Info.plist` 由 `project.yml` 的 `info.properties` 生成（含 `NSAppTransportSecurity.NSAllowsArbitraryLoads=true` 以便加载任意网页）
- **轻量**：零第三方依赖（纯 SwiftUI + WebKit），无大图资源。`project.yml` Release 配置开启 `-Osize` + strip 符号 + `DEAD_CODE_STRIPPING` + 资源 space 优化：Release 二进制 9.1MB→3.0MB（fat），真机单架构约 1.4MB。改体积相关只动 `project.yml`，勿直接改 pbxproj。

### 构建 / 运行

```bash
cd /Users/onn/Documents/workSpace/browser-claude
xcodegen generate                 # 修改了文件结构/project.yml 后重建工程
xcodebuild -project MiniBrowser.xcodeproj -scheme MiniBrowser \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO

# 模拟器（当前用的是 iPhone 16e）
DEV=F4DF90F3-6C6B-4C3A-B9C7-22C5FBEC7F15     # 用 `xcrun simctl list devices available` 查实际 ID
APP=$(find ~/Library/Developer/Xcode/DerivedData/MiniBrowser-*/Build/Products/Debug-iphonesimulator -name "MiniBrowser.app" -maxdepth 1 | head -1)
xcrun simctl boot "$DEV"; open -a Simulator
xcrun simctl install "$DEV" "$APP"
xcrun simctl launch "$DEV" com.example.minibrowser
xcrun simctl io "$DEV" screenshot /tmp/shot.png   # 截图验证 UI
```

### 真机运行（已加配置）

`project.yml` 已开启自动签名（`CODE_SIGN_STYLE: Automatic` + `CODE_SIGN_IDENTITY: Apple Development`），并生成了**共享 scheme**（`schemes:` 段，避免再出现「no schemes」）。真机跑两步：

1. 填 Team：把 `project.yml` 里 `DEVELOPMENT_TEAM: ""` 填成你的 Team ID（或 `xcodegen generate` 后在 Xcode 里选 Signing & Capabilities 的 Team）。
2. Bundle id `com.example.minibrowser` 多半已被占用，改成你自己的唯一 id（如 `com.<yourname>.minibrowser`）。
然后 `xcodegen generate`，Xcode 选真机设备 ⌘R。

> 模拟器命令行构建仍传 `CODE_SIGNING_ALLOWED=NO` 跳过签名；真机走 Xcode 自动签名。

### 验证技巧（无法点击模拟器时）

- **截图验证 UI**：`xcrun simctl io <DEV> screenshot`，再用 Read 工具看图。
- **驱动到某状态**：临时在 `BrowserApp.swift` 的 `.onAppear` 里设置 `vm.route = .xxx` / `vm.open(url:)` / `vm.wallpaper = .ocean` 等，截图后**务必还原**（历史上每次都这样验证 menu/browser/comic/selection/download/zip）。
- **文件系统验证**：`xcrun simctl get_app_container <DEV> com.example.minibrowser data` 拿到容器路径，检查 `Documents/Downloads`、`Documents/*.json`。

---

## 3. 架构总览

```
MiniBrowser/
  App/
    BrowserApp.swift        @main，注入 vm(BrowserViewModel) 与 downloads(DownloadManager)
    BrowserViewModel.swift  全局状态中枢（@MainActor ObservableObject）+ SampleData
    RootView.swift          根协调：主页/网页主体 + 底部工具栏 + 所有 sheet/cover/overlay
  DesignSystem/Theme.swift  颜色/间距/圆角/尺寸令牌；颜色随系统深浅自适应
  Components/               SiteIcon, BrandIcon(品牌图标), ToastView
  Models/                   Models(Bookmark/History/QuickLink/FileItem/MenuAction),
                            Tab(每标签独立引擎), DiskStore(JSON 持久化)
  Features/<模块>/          各功能界面
```

### 关键设计

- **状态中枢**：`BrowserViewModel` 持有几乎所有 UI 状态（路由、各种 `show*` 弹层开关、数据）。
  - 路由用 `enum Route` + `@Published var route: Route?` + `RootView.routeView(_:)` 的 `.fullScreenCover(item:)`。
  - 弹层（菜单/标签/网站设置/搜索/下载确认）各用一个 `Bool` 开关 + sheet/cover。
- **多标签独立引擎**：`Tab` 是**引用类型**（`@MainActor ObservableObject`），每个 Tab 拥有自己的 `WebEngine`（封装 `WKWebView`）。
  - `vm.currentTab` / `vm.engine`（= currentTab.engine）。切换标签 = 改 `currentTabID`。`currentTab` 走 `tabIndex: [UUID: Tab]` 做 **O(1)** 查找（海量标签防卡顿）。
  - **引擎 LRU 池**（`EnginePool`，maxLive 按设备内存自适应 3/5/8/10）：标签很多时只保留最近用的 N 个 WKWebView，后台引擎 `Tab.evictEngine()` 回收（存 `interactionState`），重新激活时 `Tab.engine` 惰性恢复。当前标签永不回收。
  - 视图通过 `@ObservedObject` 观察具体 `Tab` / `WebEngine`（因为嵌套 ObservableObject 不会自动透传）。`BottomToolbar` 的前进键用 `ForwardButton` 包一层 `@ObservedObject engine` 才能响应 `canGoForward`。
- **WebEngine**：KVO 观察 `estimatedProgress/title/url/canGoBack/canGoForward`，`WKNavigationDelegate` 管理 loading；`setDesktop`(切 UA 重载) / `applyNight`(注入反色 CSS) 联动网站设置。
- **持久化**：`DiskStore`（Documents 下 JSON）。`bookmarks`/`history` 用 `didSet` 自动落盘，`init` 启动恢复（属性观察器在 init 中不触发，故加载不会回写）。颜色以 `colorHex: UInt` 存储（Color 不可 Codable）。
- **下载/文件**：`DownloadManager`（@MainActor + `URLSessionDownloadDelegate`，delegate 回调 `nonisolated` 后 `Task { @MainActor }` 回主线程）。下载落地 `Documents/Downloads`。`FileStore` 读真实目录、删除/重命名/移动/建文件夹。
- **zip**：`ArchiveStore` 用系统 API 自研最小 ZIP 读写 + `Compression` 框架原始 DEFLATE（`COMPRESSION_ZLIB` 即 RFC1951 raw deflate，正好对应 zip method 8）。自实现 CRC32。生成的 zip 被系统 `unzip` 认可，亦能解标准 zip。

### 分层 / 性能（已做的优化）

- **LibraryStore 拆分**：书签/历史从 `BrowserViewModel` 移到独立的 `Models/LibraryStore.swift`（`@EnvironmentObject var library`，App 里 `.environmentObject(vm.library)` 注入）。好处：记录历史/增删书签只刷新该 store，不再让整个 god ViewModel 失效连带重绘 HomeView/工具栏等。`vm.addBookmark` 仍是薄封装（调 `library.addBookmark` 再 Toast）。
- **WebEngine 惰性创建**：`Tab.engine` 改为按需创建（`_engine` + 计算属性 + `hasEngine`）。启动不再为 3 个标签建 3 个 WKWebView；标签网格 `displayTitle/displayURL` 用 `hasEngine` 守卫，不会为未访问标签建引擎。`RootView` 仅浏览态把 `currentTab?.engine` 传给 `BrowserView`/工具栏（主页态传 nil，不创建）。
- **去除抛弃式分配**：`BrowserView` 原来 `vm.engine ?? WebEngine()` 每次渲染可能新建 WKWebView，已改为从 `RootView` 传入确定的 engine。
- **手势路径抽稀**：`GestureButton` 笔画中忽略 <4pt 的移动点，避免 points 膨胀和 `recognize` 的 O(n²) 重复计算。
- **磁盘写入移出主线程**：`DiskStore.save` 原来在 `@MainActor` 同步 `encode + 原子写盘（fsync）`，被 `history/bookmarks` 的 `didSet` 触发——**每次打开/刷新网页**（`vm.open → recordHistory`）都阻塞主线程整表序列化落盘。现改为：编码仍在调用线程（拿值快照、`Data` 可跨线程），写盘 dispatch 到 `utility` 级**串行**后台队列（`com.minibrowser.diskstore`，串行保证同名文件写入有序不互相覆盖）。
- **历史去重 + 上限**：`LibraryStore.recordHistory` 原来无上限插入、刷新同一地址会累积大量重复条目（放大上面那次整表序列化）。现改为同地址**去重置顶**、「今天」分组上限 `maxTodayItems = 200`，且在本地副本一次性改完再赋值（单次 `didSet` → 单次落盘，不再因一次记录触发多次写盘）。
- **海量标签扩展性（1 万+ 标签）**：
  - `currentTab` 由 O(n) 线性扫描改 **O(1) 索引**（`BrowserViewModel.tabIndex: [UUID: Tab]`，在 newTab/close/closeAllActive 维护）。实测 1 万标签下旧式线性扫描 ~0.48ms/次、每帧多次 → 卡顿；O(1) ~0.34µs/次基本免费。
  - **活跃引擎 LRU 上限池**（`Models/EnginePool.swift`，默认 maxLive=10）：绝不为每个标签常驻 WKWebView，后台引擎被回收释放内存；当前标签永不回收。`open`/`select`/`toggleIncognito` 时 `enginePool.touch`，`close` 时 `remove`。
  - **前进/后退/切回标签不重载**：活跃标签 `goBack/goForward` 走 WebKit bfcache 本就不重载；引擎被回收时用 `WKWebView.interactionState` 存完整会话（前进后退列表+滚动），`Tab.evictEngine`/重建（`Tab.engine` 惰性恢复 `savedSession`）实现无损还原。
  - 实测：1 万标签启动建表 5.5ms、标签网格（LazyVGrid 惰性）流畅渲染、无崩溃。
  - **标签持久化**：普通标签（无痕不存）以轻量快照 `TabSnapshot`（id/isHome/title/url/tintHex，每条约百字节）存 `tabs.json`，重启恢复且**不建引擎**（选中再惰性加载）。写入合并防抖（`scheduleTabPersist`，0.5s 合并）+ 进入后台立即落盘（`scenePhase`→`persistTabsNow`）。不存 `interactionState`（海量标签下体积考虑）。实测写入/恢复闭环通过（来源 sample→disk）。
- 删除死状态 `loadProgress`、示例下载/文件数据等。

- **ToastStore 拆分**：toast 从 `BrowserViewModel` 移到独立 `Models/ToastStore.swift`（`@EnvironmentObject var toasts`，App 里 `.environmentObject(vm.toasts)`）。原因：toast 几乎每个动作都触发，挂在 god VM 上时一次提示会让所有观察 vm 的视图重新求值；独立后只刷新 ToastView。`vm.showToast(...)` 保留为薄转发（`toasts.show`），既有调用点不变。

仍可继续的分层：把 `gesture`/`appearance` 也拆成独立 store——但二者只在「设置页编辑 / 拖动悬浮按钮重定位」时变化，频率极低、重绘收益几乎为零，按 YAGNI **暂不拆**（拆了只增加间接层）。VM 仍偏大但可控。

### 手势按钮（仿 BetterAndBetter，`Features/Gesture/`）

层次：**触发**（按住右下角悬浮按钮）→ **手势**（笔画 = 8 向 `GestureDirection` 的有序序列，连续同向合并；另支持**圆形** `circleClockwise/circleCounterClockwise`，由转角和识别）→ **功能**（`GestureAction`）。规则 `GestureRule` = 手势→功能。`GestureConfig` 含放置方式/直线容差/按钮大小/圆形开关/触觉等可配置项（`GestureSettingsView` 的「放置方式」「手势控制」区）。设置页里手势按钮置顶为「特色功能」单独分组。
  - **放置方式** `GesturePlacement`：`floating`（悬浮可拖，拖到左右边缘**贴边停靠**只露一部分、半透明）/ `bottomDock`（固定底部工具栏上方居中、小尺寸像图标、不可移动）。
  - **直线容差** `straightness`（取代原灵敏度）：识别器按转角和容差 `toleranceDeg=25+straightness*50`，把画得弯一点的线吸收为一段直线，不易被拆成多段。

- `GestureModels.swift`：方向/功能/规则/`GestureConfig`(启用+归一化位置+规则数组) + `GestureRecognizer.recognize(points)`（按段长阈值把路径切成方向 token）。
- `GestureButton.swift`：全屏 ZStack 承载笔画轨迹（命名坐标空间 `gestureRoot`）；状态机 `idle→deciding→gesturing/moving`：拖动>12pt 进笔画模式（画 Canvas 轨迹 + 实时识别 + 命中功能 HUD），按住 0.45s 进移动模式（重定位按钮并存归一化位置），轻点打开配置页。
- `GestureSettingsView.swift`：启用开关 + 规则列表（箭头字形→功能，逐条开关/删除）+ 恢复默认；`GestureRuleEditView` 含 `DrawPad` 绘制录制 + 8 向手动微调 + 功能 Picker。
- 持久化：`gestures.json`（`vm.gesture` 的 `didSet`）；执行入口 `vm.matchGesture(_:)` / `vm.perform(_:)`。
- 入口：设置 → 功能 → 手势按钮；或轻点悬浮按钮。默认位置右下（posX 0.93 / posY 0.80）。
- 默认规则：← 后退 / → 前进 / ↑ 新建标签 / ↓ 关闭标签 / ↑↓ 刷新 / ↑→ 标签管理 / ↑← 菜单 / ↓↑ 回顶部。

### 代码约定（来自用户 CLAUDE.md，务必遵守）

- DRY / KISS / YAGNI；文件超 ~1000 行要拆分（目前最大文件远未到）。
- **显式抛错，不静默吞**；错误信息要带上下文（见 `ArchiveStore.ArchiveError`、`DiskStore` 的 assertionFailure）。
- 终端用非交互命令；`git --no-pager diff`；搜索用 `rg`。
- 改动最小化、匹配现有仓库风格；注释用中文（与现有一致）。
- 中文注释 + 中文 UI 文案。

---

## 4. 已完成（真实实现）

| 模块 | 状态 | 关键文件 |
|---|---|---|
| 主页/新标签页（搜索框+盾牌+二维码+品牌宫格+下拉搜索） | ✅ | `Home/HomeView.swift` |
| 搜索输入态（建议/剪贴板/历史，URL vs 关键词识别） | ✅ | `Home/SearchOverlay.swift`, `WebEngine.normalize` |
| 网页浏览（真实 WKWebView、地址栏、进度、刷新/停止） | ✅ 真实 | `Browser/BrowserView.swift`, `Browser/WebEngine.swift` |
| 底部工具栏（后退/前进/菜单/标签/主页，真实前进后退历史） | ✅ | `Browser/BottomToolbar.swift` |
| 底部主菜单（三屏宫格 60 项 + 快捷操作行 + 状态行） | ✅ | `Menu/MainMenuSheet.swift` |
| 多标签管理（卡片缩略图、普通/无痕、独立引擎） | ✅ 真实 | `Tabs/TabsView.swift`, `Models/Tab.swift` |
| 书签 + 历史（持久化、真实记录、删除/清除/收藏） | ✅ 真实 | `Bookmarks/*`, `DiskStore` |
| 下载（URLSession 真实下载/暂停/续传/删除/分享） | ✅ 真实 | `Files/DownloadManager.swift`, `Files/DownloadsView.swift` |
| 文件管理（真实列目录/删除/重命名/移动/建文件夹/分享） | ✅ 真实 | `Files/FilesView.swift`, `FileStore` |
| zip 压缩 / 解压 | ✅ 真实 | `Files/ArchiveStore.swift` |
| 设置中心（7 大分组 + 大量二级页） | ✅ | `Settings/SettingsView.swift`, `Settings/SettingsSubpages.swift` |
| 沉浸式壁纸（7 种）+ 外观模式 + OLED 纯黑 | ✅ 真实 | `Home/Wallpaper.swift`, `Settings/AppearanceSettings.swift` |
| 网站设置面板（盾牌弹出，桌面版/夜间真实联动引擎） | ✅ 部分真实 | `WebsiteSettings/WebsiteSettingsSheet.swift` |
| 品牌图标矢量绘制（原创简化标识，非商标复刻） | ✅ | `Components/BrandIcon.swift` |
| 划词浮层 BigBang（复制/翻译/搜索/文本选取分词） | ✅ UI | `Browser/SelectionToolbar.swift` |
| 标记广告流程（元素选择高亮 + 确认屏蔽 toast） | ✅ UI | `Browser/MarkAdsOverlay.swift` |
| 漫画看图（纵向/单页/双页、缩放、页码滑块） | ✅ UI | `ImageViewer/ComicReaderView.swift` |
| 阅读模式 / 看图模式 / 电子书阅读器 / 视频悬浮窗 | ✅ UI | `Reading/`, `ImageViewer/`, `Reader/`, `Video/` |
| 二维码扫描/生成、翻译、广告拦截、JS 扩展、开发者工具、Cookie、工具箱 | ✅ UI | `QRCode/`, `Tools/`, `Reader/` |
| 全局 Toast 反馈 | ✅ | `Components/ToastView.swift`, `vm.showToast` |
| 手势按钮（仿 BetterAndBetter：笔画→功能，可配置/录制/移动） | ✅ 真实 | `Features/Gesture/*` |
| 二维码（CoreImage 生成 + AVFoundation 扫描，无相机降级） | ✅ 真实 | `Features/QRCode/QRCode.swift`, `QRScannerView.swift` |
| 看图模式（JS 提取页面 img + AsyncImage 真实展示 + 存相册/分享） | ✅ 真实 | `WebEngine.fetchImageURLs`, `ImageViewer/ImageGridView.swift`, `Models/ImageSaver.swift`, `vm.openImageMode` |
| JS 扩展（用户脚本真实注入，匹配 glob + 时机） | ✅ 真实 | `Models/UserScriptStore.swift`, `Browser/WebEngine.swift`, `Tools/FeatureViews.swift` |
| 书签文件夹（层级 parentID + 新建/编辑/移动/删除） | ✅ 真实 | `Models/Models.swift`, `Models/LibraryStore.swift`, `Bookmarks/BookmarksView.swift` |
| 网页内长按链接下载（原生上下文菜单） | ✅ 真实 | `Browser/WebEngine.swift`(WKUIDelegate), `Browser/BrowserView.swift` |
| 插件体系 + 插件市场（广告拦截=真实 WKContentRuleList 插件） | ✅ 真实 | `Models/Plugin.swift`, `Models/PluginStore.swift`, `Plugins/PluginMarketView.swift` |

> 「✅ UI」= 界面与流程完整、可交互，但底层为占位/示例数据。

---

## 5. 未完成 / 占位（明确告知用户的待办）

- **无图模式**：✅ 已真实化，做成内容规则插件 `noimage.block`（拦截 image 资源 + `css-display-none` 隐藏 img/picture）。`vm.isNoImageMode` 派生镜像该插件、`toggleNoImage()` 驱动；切换后内容规则重编译完成会 `refreshContentRules(reload:)` 重载当前页立即生效（广告拦截切换同此机制）。
- **插件体系 / 插件市场**：✅ 已搭框架（`Models/Plugin.swift` 内置目录 + `Models/PluginStore.swift` 状态持久化/引擎集成 + `Features/Plugins/PluginMarketView.swift`）。两类插件：`contentRule`（编译为 `WKContentRuleList`）与 `userScript`（复用 `UserScriptStore.wrap`）。`WebEngine.init` 注入。入口：设置 → 功能 → 插件市场（已取代原「广告拦截」单独入口）。**广告拦截现为插件**（`adblock.basic`，真实 `WKContentRuleList`，默认安装启用）。注意：① 规则编译是**异步**的，仅对之后新建标签生效；② WKContentRuleList 仅支持受限正则子集（交替组等会编译失败），失败只记录并跳过、不崩溃；③ 目录在代码内，仅安装/启用状态持久化到 `plugins.json`。后续可扩展：把更多内置功能收编为插件、接远程目录。
- **iCloud 同步**：代码已实现（`Models/CloudSync.swift` + `LibraryStore.persist/applyRemote`，`NSUbiquitousKeyValueStore`，含防回写守卫与 last-writer-wins），但 **entitlement 已暂时从 `project.yml` 移除**（个人 Team 真机签名过不去）。无 entitlement 时 CloudSync **静默降级**、不影响本地。恢复办法：把 `project.yml` 注释里的 `entitlements` 段加回 + 真机勾选 iCloud → Key-value storage。
- **JS 扩展**：✅ 已真实注入（`Models/UserScriptStore.swift` + `WebEngine` 在 init 写入 `WKUserContentController`，按 match glob 包网址守卫）。编辑界面接真实存储。限制：编辑只对**之后新建的标签**生效（已创建引擎不热更新）。
- **翻译**：UI 完整，未接真实翻译 API。**待决策**：选定翻译服务 + API Key，或用 iOS 17.4+ 系统 `TranslationSession`（部署目标 17.0，需 `@available` 降级）。
- **搜索引擎**：✅ 已真实化（`SearchEngine` 模型 + 内置 6 家 + 自定义引擎，`vm.searchEngine` 持久化 `search_engine.json`/`custom_engines.json`，`WebEngine.normalize` 支持 `%s` 与追加两种模板）。入口：设置→搜索引擎 / 菜单→搜索引擎（route `.searchEngine`）。「搜索建议/AI 搜索/清除搜索历史」仍占位。
- **二维码**：✅ 已真实化（生成 `CIQRCodeGenerator`、扫描 `AVCaptureMetadataOutput`）。仅「相册识别」按钮仍为占位（未接 `PHPicker` + `CIDetector`）。
- **视频悬浮/画中画/投屏/倍速**：悬浮窗 UI 可拖拽吸附，但未接真实 `AVPlayer`/`AVPictureInPictureController`。
- **看图模式**：✅ 已真实提取网页图片（`WebEngine.fetchImageURLs` + `AsyncImage`），✅ 批量保存到相册（`Models/ImageSaver.swift`，下载远程图后 `UIImageWriteToSavedPhotosAlbum`）+ 分享（`ShareLink`）。**漫画/电子书** 仍为渐变/书页占位，未解析真实长图或 epub/pdf。
- **阅读模式**：示例正文，未做正文抽取（Readability）。
- **文件**：解压/压缩仅 zip；rar/7z 未支持。「Wi-Fi 传输」「从相册/系统导入」为占位按钮。「以纯文本打开/编码选择/文本编辑」未实现。
- **网站设置**：仅桌面版、夜间模式真实联动引擎；其余开关为本地 @State 占位。
- **长按快捷操作 / 自定义菜单顺序 / 工具栏按钮自定义**：选择界面完整，但未真正改变按钮行为。
- **下载触发**：✅ 网页内长按链接已可下载（`WebEngine` 的 `WKUIDelegate` 上下文菜单「下载链接」→ `DownloadManager.start`）；划词浮层改为读取真实选中文本（`fetchSelectedText`），无选中时让位给原生菜单，两者不再冲突。菜单「下载资源」入口仍保留。
- **大量设置项**：`PlaceholderSettings` 占位（主页设置、标签页、User-Agent、视频播放、文件管理、主题子项、导入导出书签、默认浏览器、添加到主屏幕、更新日志/隐私政策/用户协议等）。

---

## 6. 推荐后续路线（用户曾认可的方向）

按价值/依赖排序，供参考（✅ = 已完成）：

1. ✅ **书签文件夹归类 + 编辑/新建/移动**（`Bookmark.parentID` 层级；`LibraryStore` 增删改 + `BookmarkFolderView` 递归导航）。
2. ✅ **二维码真实化**（`CIQRCodeGenerator` + `AVCaptureMetadataOutput`）。
3. ✅ **网页图片提取 + 存相册/分享**（`fetchImageURLs` + `ImageSaver`）。
4. ✅ **JS 扩展真实注入**（`UserScriptStore` + `WKUserContentController`）。
5. ✅ **网页内长按下载**（`WebEngine` 的 `WKUIDelegate` 上下文菜单）。
6. ✅ **iCloud 同步**（书签/历史，`NSUbiquitousKeyValueStore`）。
7. **翻译接 API**：选定服务 + Key，或 iOS 17.4+ 系统 `TranslationSession`——**用户已暂缓**。
8. ✅ **插件体系 + 插件市场**（广告拦截已做成真实 `WKContentRuleList` 插件）。
9. **rar/7z 解压**（需第三方库，确认是否允许依赖）。
10. **插件体系扩展**：把夜间/无图/划词等更多功能收编为插件；接远程插件目录（需 URL）。

---

## 7. 易踩坑 / 注意事项

- **Swift 6 并发**：`Tab`/`WebEngine`/`DownloadManager`/`BrowserViewModel` 都是 `@MainActor`。URLSession/KVO/FileCoordinator 回调是 `nonisolated`，回主线程要 `Task { @MainActor in }`。`DownloadManager.fileName(for:)` 必须 `nonisolated`（被 delegate 调用）。
- **嵌套 ObservableObject 不透传**：VM 里放 ObservableObject（如 Tab/WebEngine）时，视图必须直接 `@ObservedObject` 那个对象才会刷新，不能只观察外层 VM。
- **`NSFileCoordinator .forUploading` 只压缩目录**，对单文件原样返回——所以 `ArchiveStore.zip` 改成了自研 ZIP 写入器（这是历史上踩过的真实坑）。
- **临时验证代码务必还原**：每次用 `BrowserApp.onAppear` 注入临时状态截图后都要删掉，别提交。
- **xcodegen 会重写 Info.plist**：改 plist 要改 `project.yml` 的 `info.properties`，不要直接改生成的 plist。
- **颜色持久化**：凡是要存盘的模型，颜色用 `colorHex: UInt`，不要直接存 `Color`。
- **菜单动作分发**：`MainMenuSheet.handle(_:)` 用功能**标题字符串** switch 分发；新增菜单项要在 `MenuCatalog` 加项并在 `handle` 加 case，否则只是 dismiss。

---

## 8. 数据与持久化位置

- 书签：`Documents/bookmarks.json`
- 历史：`Documents/history.json`
- 下载文件：`Documents/Downloads/`（`DownloadManager.downloadsDirectory`）
- 标签：`Documents/tabs.json`（`TabsState`，普通标签快照 + 当前 id；无痕不存）
- 用户脚本：`Documents/userscripts.json`；插件状态：`Documents/plugins.json`
- 首次启动无文件时回落到 `SampleData`（在 `BrowserViewModel.swift` 底部）。

---

## 9. git 状态

仓库初始只有两张参考图（`cover-phones.png`、`Snipaste_*.png`）和现在的全部源码。
尚未提交（用户未要求 commit）。如需提交：在非默认分支操作，commit message 结尾加
`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
