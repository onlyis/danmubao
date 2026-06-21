import UIKit

/// 把远程图片下载后批量保存到系统相册。
/// 需 Info.plist 的 `NSPhotoLibraryAddUsageDescription`（已在 project.yml 配置）。
enum ImageSaver {
    /// 下载并保存到相册，完成后回主线程回调成功张数。
    static func saveToAlbum(_ urls: [URL], completion: @escaping (Int) -> Void) {
        guard !urls.isEmpty else { completion(0); return }
        let group = DispatchGroup()
        let lock = NSLock()
        var saved = 0
        for url in urls {
            group.enter()
            URLSession.shared.dataTask(with: url) { data, _, _ in
                defer { group.leave() }
                guard let data, let image = UIImage(data: data) else { return }
                // UIImageWriteToSavedPhotosAlbum 建议在主线程调用
                DispatchQueue.main.async { UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil) }
                lock.lock(); saved += 1; lock.unlock()
            }.resume()
        }
        group.notify(queue: .main) { completion(saved) }
    }
}
