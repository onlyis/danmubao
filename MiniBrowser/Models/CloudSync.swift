import Foundation

/// 基于 NSUbiquitousKeyValueStore 的轻量 iCloud 同步（书签 / 历史等小体量 JSON）。
/// 未登录 iCloud 或缺少 entitlement 时静默降级：set/data/synchronize 均无副作用，不影响本地持久化。
/// 注意：KVS 总量上限约 1MB、1024 个键，仅适合书签/历史这类小数据。
@MainActor
final class CloudSync {
    static let shared = CloudSync()
    private let store = NSUbiquitousKeyValueStore.default

    /// 远程数据到达时回调（key, 解码用的原始 Data）。由存储层接管合并。
    var onRemoteChange: ((String, Data) -> Void)?

    /// 待推送的最新值（按 key 合并，只保留最后一次）+ 合并写定时器。
    /// 历史/书签每次导航都变更，逐次 `set + synchronize` 既浪费又会被系统限流；故合并一段时间一次推。
    private var pending: [String: Data] = [:]
    private var flushWork: DispatchWorkItem?
    private let flushDelay: TimeInterval = 2

    /// 远程变更通知的观察者 token，保存以便 deinit 时移除，避免观察者泄漏。
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { [weak self] note in
            let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
            // queue: .main 保证回调在主线程
            MainActor.assumeIsolated { self?.handleRemote(keys) }
        }
        store.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// 推送本地变更到 iCloud（合并写：同 key 多次变更只保留最后一次，延迟 `flushDelay` 统一落库）。
    func push(_ data: Data, for key: String) {
        pending[key] = data
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + flushDelay, execute: work)
    }

    /// 把合并的待推送值一次性写入 KVS 并同步。
    private func flush() {
        guard !pending.isEmpty else { return }
        for (key, data) in pending { store.set(data, forKey: key) }
        pending.removeAll()
        store.synchronize()
    }

    /// 读取 iCloud 上的当前值（启动时拉取用）
    func pull(_ key: String) -> Data? { store.data(forKey: key) }

    private func handleRemote(_ keys: [String]) {
        for key in keys {
            if let data = store.data(forKey: key) { onRemoteChange?(key, data) }
        }
    }
}
