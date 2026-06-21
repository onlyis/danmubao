import SwiftUI
import WebKit

/// 插件存储 + 引擎集成。
/// - 目录来自 `Plugin.catalog`（代码内），仅安装/启用状态持久化到 `plugins.json`。
/// - 内容规则类插件异步编译为 `WKContentRuleList` 缓存；用户脚本类插件生成 `WKUserScript`。
/// - `WebEngine` 在 init 时读取本 store（共享实例），故启用变更对**之后新建的标签**生效。
@MainActor
final class PluginStore: ObservableObject {
    static let shared = PluginStore()

    @Published private(set) var plugins: [Plugin]
    /// 已编译的内容拦截规则（供 WebEngine.init 同步取用）
    private(set) var compiledRuleLists: [WKContentRuleList] = []

    init() {
        let states = DiskStore.load([String: PluginState].self, from: "plugins.json") ?? [:]
        plugins = Plugin.catalog.map { base in
            var p = base
            if let s = states[p.id] { p.installed = s.installed; p.enabled = s.enabled }
            return p
        }
        recompileRules()
    }

    // MARK: - 查询
    var installed: [Plugin] { plugins.filter(\.installed) }
    func plugins(in category: Plugin.Category) -> [Plugin] { plugins.filter { $0.category == category } }
    var enabledAdblockCount: Int {
        plugins.filter { $0.installed && $0.enabled && $0.category == .adblock }.count
    }

    // MARK: - 安装 / 启用
    func install(_ plugin: Plugin)   { update(plugin.id) { $0.installed = true; $0.enabled = true } }
    func uninstall(_ plugin: Plugin) { update(plugin.id) { $0.installed = false; $0.enabled = false } }
    func setEnabled(_ plugin: Plugin, _ on: Bool) { update(plugin.id) { $0.enabled = on } }

    private func update(_ id: String, _ change: (inout Plugin) -> Void) {
        guard let i = plugins.firstIndex(where: { $0.id == id }) else { return }
        change(&plugins[i])
        persist()
        recompileRules()
    }

    private func persist() {
        let map = Dictionary(uniqueKeysWithValues:
            plugins.map { ($0.id, PluginState(installed: $0.installed, enabled: $0.enabled)) })
        DiskStore.save(map, to: "plugins.json")
    }

    // MARK: - 引擎集成
    /// 用户脚本类插件 → WKUserScript（复用 UserScriptStore 的网址守卫包装）
    func installableUserScripts() -> [WKUserScript] {
        plugins.compactMap { p in
            guard p.installed, p.enabled, case let .userScript(code, match, atEnd) = p.kind else { return nil }
            return WKUserScript(source: UserScriptStore.wrap(code: code, match: match),
                                injectionTime: atEnd ? .atDocumentEnd : .atDocumentStart,
                                forMainFrameOnly: false)
        }
    }

    /// 内容规则类插件 → 异步编译为 WKContentRuleList 并缓存。状态变更时重编译。
    private func recompileRules() {
        let rules: [(String, String)] = plugins.compactMap { p in
            guard p.installed, p.enabled, case let .contentRule(json) = p.kind else { return nil }
            return (p.id, json)
        }
        guard !rules.isEmpty, let store = WKContentRuleListStore.default() else {
            compiledRuleLists = []
            return
        }
        let group = DispatchGroup()
        let lock = NSLock()
        var compiled: [WKContentRuleList] = []
        for (id, json) in rules {
            group.enter()
            store.compileContentRuleList(forIdentifier: "plugin.\(id)", encodedContentRuleList: json) { list, error in
                if let list { lock.lock(); compiled.append(list); lock.unlock() }
                else if let error {
                    // 规则非法是可恢复的：跳过该插件规则，不影响其它插件与浏览
                    NSLog("[plugin] 规则编译失败 id=%@ error=%@", id, String(describing: error))
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in self?.compiledRuleLists = compiled }
    }
}
