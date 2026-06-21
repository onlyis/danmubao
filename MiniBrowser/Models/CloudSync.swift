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

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { [weak self] note in
            let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
            // queue: .main 保证回调在主线程
            MainActor.assumeIsolated { self?.handleRemote(keys) }
        }
        store.synchronize()
    }

    /// 推送本地变更到 iCloud
    func push(_ data: Data, for key: String) {
        store.set(data, forKey: key)
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
