import Foundation

/// 广告隐藏规则存储层：按站（host）持久化用户「标记广告」时选中的 CSS 选择器。
/// 每条规则形如 `host -> [selector...]`，下次访问同站时由 `WebEngine` 注入隐藏 CSS（display:none）。
/// 数据落 `adhide.json`（Documents），与用户脚本/插件等单例范式一致（见 UserScriptStore.shared）。
@MainActor
final class AdHideStore: ObservableObject {
    /// WebEngine 在 didFinish 重注入时需读取，故用共享单例；视图层亦可注入同一对象。
    static let shared = AdHideStore()

    /// host -> 选择器集合。host 已归一化（去端口、去 www. 前缀、小写）。
    @Published private(set) var rules: [String: [String]] = [:] {
        didSet { DiskStore.save(rules, to: "adhide.json") }
    }

    init() {
        // 启动恢复；首次或损坏回落空表（DiskStore.load 已自愈不崩溃）。
        rules = DiskStore.load([String: [String]].self, from: "adhide.json") ?? [:]
    }

    /// host 归一化：去掉端口与 `www.` 前缀并小写，保证 `www.A.com:443` 与 `a.com` 视为同站。
    static func normalize(_ host: String?) -> String? {
        guard var h = host?.lowercased(), !h.isEmpty else { return nil }
        if let colon = h.firstIndex(of: ":") { h = String(h[..<colon]) }   // 去端口
        if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }              // 去 www.
        return h.isEmpty ? nil : h
    }

    /// 当前 host 已隐藏的选择器列表（无规则返回空数组）。
    func selectors(for host: String?) -> [String] {
        guard let key = Self.normalize(host) else { return [] }
        return rules[key] ?? []
    }

    /// 新增一条隐藏规则（去重），返回该 host 更新后的完整选择器列表（供调用方立即注入）。
    @discardableResult
    func add(_ selector: String, for host: String?) -> [String] {
        let sel = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key = Self.normalize(host), !sel.isEmpty else { return selectors(for: host) }
        var list = rules[key] ?? []
        if !list.contains(sel) { list.append(sel) }
        rules[key] = list
        return list
    }

    /// 移除一条隐藏规则（撤销），返回该 host 更新后的完整选择器列表。
    @discardableResult
    func remove(_ selector: String, for host: String?) -> [String] {
        guard let key = Self.normalize(host) else { return [] }
        var list = rules[key] ?? []
        list.removeAll { $0 == selector }
        if list.isEmpty { rules.removeValue(forKey: key) } else { rules[key] = list }
        return list
    }
}
