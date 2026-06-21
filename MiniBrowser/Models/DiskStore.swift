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
                assertionFailure("DiskStore 写入失败 file=\(name) error=\(error)")
            }
        }
    }

    static func save<T: Encodable>(_ value: T, to name: String) {
        // 编码在调用线程完成（捕获当前值的快照，且 Data 可安全跨线程传递）；写盘放到后台队列。
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            assertionFailure("DiskStore 编码失败 file=\(name) error=\(error)")
            return
        }
        let target = url(name)
        ioQueue.async {
            do {
                try data.write(to: target, options: .atomic)
            } catch {
                // 持久化失败不应中断 UI，但需暴露问题上下文
                assertionFailure("DiskStore 写入失败 file=\(name) error=\(error)")
            }
        }
    }

    /// 首次启动文件不存在返回 nil（属正常情况，非错误）
    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let fileURL = url(name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            assertionFailure("DiskStore 读取失败 file=\(name) error=\(error)")
            return nil
        }
    }
}
