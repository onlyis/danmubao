import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

/// 文件导入：系统文件 App 选取 + 相册选取，均落盘到 DownloadManager.downloadsDirectory（唯一命名，避免覆盖）。
/// 两个 UIViewControllerRepresentable 都通过 onComplete(成功导入数量) 回调，由调用方刷新列表。

// MARK: - 从系统文件 App 导入

/// UIDocumentPickerViewController 包装：以 .copy 模式选取任意类型文件，拷贝到下载目录。
struct DocumentImportPicker: UIViewControllerRepresentable {
    /// 导入完成回调（参数为成功导入的文件数量）。
    var onComplete: (Int) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // asCopy: true → 系统把文件拷贝到 App 沙盒临时区，我们再移动到下载目录，无需安全作用域访问。
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: (Int) -> Void
        init(onComplete: @escaping (Int) -> Void) { self.onComplete = onComplete }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            let fm = FileManager.default
            let dir = DownloadManager.downloadsDirectory
            var success = 0
            for url in urls {
                let dest = DownloadManager.uniqueDestination(for: url.lastPathComponent, in: dir)
                do {
                    // asCopy 模式下 url 已在沙盒内，直接移动即可（dest 由 uniqueDestination 保证不存在）。
                    try fm.moveItem(at: url, to: dest)
                    success += 1
                } catch {
                    // 移动失败时退而拷贝，仍失败则跳过该文件，不影响其余导入。
                    do { try fm.copyItem(at: url, to: dest); success += 1 }
                    catch { continue }
                }
            }
            onComplete(success)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete(0)
        }
    }
}

// MARK: - 从相册导入

/// PHPickerViewController 包装：选取图片/视频，写入下载目录（唯一命名）。
struct PhotoImportPicker: UIViewControllerRepresentable {
    /// 导入完成回调（参数为成功导入的资源数量）。
    var onComplete: (Int) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0          // 0 = 不限数量
        config.filter = .any(of: [.images, .videos])
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onComplete: (Int) -> Void
        init(onComplete: @escaping (Int) -> Void) { self.onComplete = onComplete }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { onComplete(0); return }

            // 逐个把选中资源的底层文件拷贝到下载目录；全部异步完成后回调一次总数。
            Task { @MainActor in
                var success = 0
                for result in results {
                    if await Self.importResult(result) { success += 1 }
                }
                self.onComplete(success)
            }
        }

        /// 取出单个 PHPickerResult 的文件表示并落盘；成功返回 true。
        private static func importResult(_ result: PHPickerResult) async -> Bool {
            let provider = result.itemProvider
            // 优先用首个可用类型标识符获取文件表示，保留原始扩展名。
            guard let typeID = provider.registeredTypeIdentifiers.first(where: {
                UTType($0) != nil
            }) else { return false }

            return await withCheckedContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: typeID) { tempURL, error in
                    guard let tempURL, error == nil else {
                        continuation.resume(returning: false); return
                    }
                    // 回调在后台线程，且 tempURL 仅在本闭包内有效，必须同步拷出。
                    let fm = FileManager.default
                    let suggested = provider.suggestedName ?? tempURL.deletingPathExtension().lastPathComponent
                    let ext = tempURL.pathExtension.isEmpty
                        ? (UTType(typeID)?.preferredFilenameExtension ?? "dat")
                        : tempURL.pathExtension
                    let name = "\(suggested).\(ext)"
                    let dest = DownloadManager.uniqueDestination(for: name, in: DownloadManager.downloadsDirectory)
                    do {
                        try fm.copyItem(at: tempURL, to: dest)
                        continuation.resume(returning: true)
                    } catch {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }
}
