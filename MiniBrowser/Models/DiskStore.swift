import Foundation

/// 轻量 JSON 文件持久化（Documents 目录）。
enum DiskStore {
    private static let directory = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]

    /// 串行后台队列：把磁盘写入（含 fsync/原子替换）移出主线程，避免每次历史/书签变更阻塞 UI。
    /// 串行保证同名文件的多次写入按调用顺序落盘，不会相互覆盖。
    private static let ioQueue = DispatchQueue(label: "com.minibrowser.diskstore", qos: .utility)

    private static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// 直接写入已编码的 Data（供已自行编码的调用方复用，避免二次编码）。后台串行写盘。
    static func write(_ data: Data, to name: String) {
        let target = url(name)
        ioQueue.async {
            do {
                try data.write(to: target, options: .atomic)
            } catch {
                // 写盘失败必须暴露：Release 下 assertionFailure 是 no-op 会导致静默丢数据。
                NSLog("[DiskStore] 写入失败 file=%@ error=%@", name, String(describing: error))
            }
        }
    }

    /// 编码 + 写盘都放到后台队列（值类型需 Sendable 以安全跨线程）。
    /// 用于体量可能较大的快照（如海量标签的 tabs.json），避免在主线程整表编码造成尖峰。
    static func saveAsync<T: Encodable & Sendable>(_ value: T, to name: String) {
        let target = url(name)
        ioQueue.async {
            do {
                let data = try JSONEncoder().encode(value)
                try data.write(to: target, options: .atomic)
            } catch {
                // 编码或写盘失败必须暴露：Release 下 assertionFailure 是 no-op 会导致静默丢数据。
                NSLog("[DiskStore] 异步保存失败 file=%@ error=%@", name, String(describing: error))
            }
        }
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        // 编码在调用线程完成（捕获当前值的快照，且 Data 可安全跨线程传递）；写盘放到后台队列。
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            // 编码失败必须暴露：Release 下 assertionFailure 是 no-op 会导致静默丢数据。
            NSLog("[DiskStore] 编码失败 file=%@ error=%@", name, String(describing: error))
            return
        }
        let target = url(name)
        ioQueue.async {
            do {
                try data.write(to: target, options: .atomic)
            } catch {
                // 持久化失败不应中断 UI，但需暴露问题上下文；
                // Release 下 assertionFailure 是 no-op 会导致静默丢数据。
                NSLog("[DiskStore] 写入失败 file=%@ error=%@", name, String(describing: error))
            }
        }
    }

    /// 首次启动文件不存在返回 nil（属正常情况，非错误）。
    /// 解码失败（旧格式 / 损坏）也返回 nil 让调用方回落到默认值——**绝不崩溃**：
    /// 数据 schema 会随版本演进，读到不兼容文件应自愈，而非 assertionFailure 中断 App 启动。
    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let fileURL = url(name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // 仅记录上下文，回落到默认值；不中断 UI。
            NSLog("[DiskStore] 读取失败（回落默认）file=%@ error=%@", name, String(describing: error))
            return nil
        }
    }
}
