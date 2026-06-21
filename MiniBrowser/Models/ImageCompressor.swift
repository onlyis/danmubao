import UIKit

/// 图片压缩：把下载目录里的图片文件重新解码后按质量 JPEG 编码，写回下载目录。
/// 用于减小图片体积（如截图、相册导出图）。仅处理常见图片格式（jpg/png/heic 等）。
enum ImageCompressor {
    /// 压缩出错的具体类型（显式抛错，不静默吞）。
    enum CompressError: LocalizedError {
        case fileNotFound(URL)
        case notAnImage(URL)
        case encodeFailed(URL, quality: CGFloat)
        case writeFailed(URL, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "找不到图片文件：\(url.lastPathComponent)"
            case .notAnImage(let url):
                return "无法解码为图片：\(url.lastPathComponent)"
            case .encodeFailed(let url, let quality):
                return "重新编码失败：\(url.lastPathComponent)（质量 \(quality)）"
            case .writeFailed(let url, let underlying):
                return "写入失败：\(url.lastPathComponent)（\(underlying.localizedDescription)）"
            }
        }
    }

    /// 压缩结果：新文件地址 + 前后字节数，供调用方做 toast/列表刷新。
    struct Result {
        let outputURL: URL
        let originalBytes: Int64
        let compressedBytes: Int64

        /// 节省比例（0…1），原始为 0 时返回 0。
        var savedRatio: Double {
            guard originalBytes > 0 else { return 0 }
            return max(0, Double(originalBytes - compressedBytes) / Double(originalBytes))
        }
    }

    /// 支持压缩的图片扩展名（与 FileStore.icon 的图片判定保持一致）。
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"]

    /// 判断某文件名是否为可压缩的图片类型。
    static func isImage(_ fileName: String) -> Bool {
        imageExtensions.contains((fileName as NSString).pathExtension.lowercased())
    }

    /// 压缩下载目录里指定名字的图片。
    /// - Parameters:
    ///   - fileName: 下载目录内的文件名（如 "photo.png"）。
    ///   - quality: JPEG 压缩质量（0…1），默认 0.5。
    ///   - directory: 所在目录，默认下载目录。
    /// - Returns: 新文件地址与前后大小。新文件命名为 `<原名>-compressed.jpg`（冲突时追加序号）。
    @discardableResult
    static func compress(fileName: String,
                         quality: CGFloat = 0.5,
                         in directory: URL = DownloadManager.downloadsDirectory) throws -> Result {
        let src = directory.appendingPathComponent(fileName)
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path) else { throw CompressError.fileNotFound(src) }

        guard let data = fm.contents(atPath: src.path), let image = UIImage(data: data) else {
            throw CompressError.notAnImage(src)
        }
        let originalBytes = Int64(data.count)

        guard let jpeg = image.jpegData(compressionQuality: quality) else {
            throw CompressError.encodeFailed(src, quality: quality)
        }

        let base = (fileName as NSString).deletingPathExtension
        let dest = uniqueURL(directory.appendingPathComponent("\(base)-compressed.jpg"))
        do {
            try jpeg.write(to: dest, options: .atomic)
        } catch {
            throw CompressError.writeFailed(dest, underlying: error)
        }

        return Result(outputURL: dest, originalBytes: originalBytes, compressedBytes: Int64(jpeg.count))
    }

    /// 目标已存在时追加序号，避免覆盖（与 FilesView.uniqueURL 同策略）。
    private static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var i = 2
        while true {
            let candidate = dir.appendingPathComponent(ext.isEmpty ? "\(stem)-\(i)" : "\(stem)-\(i).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}
