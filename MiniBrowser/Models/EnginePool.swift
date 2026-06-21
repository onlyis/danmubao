import Foundation

/// 活跃 WKWebView 引擎的 LRU 上限池。
///
/// 海量标签（如 1 万+）时绝不能为每个标签都常驻一个 WKWebView——内存会爆。
/// 本池只保留最近使用的 `maxLive` 个引擎，其余后台标签的引擎被回收（保存会话状态，
/// 重新激活时由 `Tab` 无损恢复）。当前标签永不回收。
@MainActor
final class EnginePool {
    private let maxLive: Int
    private var order: [Tab] = []   // 队尾 = 最近使用

    /// 默认按设备物理内存自适应上限：低端机保留更少活引擎，进一步压低内存占用。
    init(maxLive: Int? = nil) {
        self.maxLive = maxLive ?? Self.adaptiveMaxLive()
    }

    private static func adaptiveMaxLive() -> Int {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        switch gb {
        case ..<2:  return 3
        case ..<4:  return 5
        case ..<6:  return 8
        default:    return 10
        }
    }

    /// 标记某标签引擎为最近使用，并按需回收最久未用的后台引擎。
    func touch(_ tab: Tab, current: Tab?) {
        order.removeAll { $0 === tab }
        order.append(tab)
        evictIfNeeded(current: current)
    }

    /// 标签关闭时从池中移除。
    func remove(_ tab: Tab) { order.removeAll { $0 === tab } }

    private func evictIfNeeded(current: Tab?) {
        guard order.count > maxLive else { return }
        var i = 0
        while order.count > maxLive && i < order.count {
            let candidate = order[i]
            if candidate === current { i += 1; continue }   // 跳过当前标签
            candidate.evictEngine()
            order.remove(at: i)
        }
    }
}
