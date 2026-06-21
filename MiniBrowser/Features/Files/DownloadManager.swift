import Foundation
import SwiftUI

/// 单个下载任务（引用类型，便于行视图实时观察进度）。
@MainActor
final class LiveDownload: ObservableObject, Identifiable {
    let id = UUID()
    /// 展示用文件名。下载开始时由地址推导，完成后回填为实际落盘名（可能取自服务器 `suggestedFilename`）。
    @Published var fileName: String
    let sourceURL: URL
    @Published var bytesWritten: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var state: State = .downloading
    @Published var localURL: URL?

    enum State: Equatable { case downloading, paused, completed, failed(String) }

    var taskIdentifier: Int?
    var task: URLSessionDownloadTask?
    var resumeData: Data?

    init(fileName: String, sourceURL: URL) {
        self.fileName = fileName
        self.sourceURL = sourceURL
    }

    var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesWritten) / Double(totalBytes)
    }
    var sizeText: String {
        let total = totalBytes > 0 ? ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) : "—"
        switch state {
        case .completed: return total
        case .downloading where totalBytes > 0:
            return "\(ByteCountFormatter.string(fromByteCount: bytesWritten, countStyle: .file)) / \(total)"
        default: return total
        }
    }
}

/// 下载管理：真实 URLSession 下载到 Documents/Downloads。
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var downloads: [LiveDownload] = []

    nonisolated static let downloadsDirectory: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private lazy var session: URLSession =
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    /// 由用户输入的地址归一化后开始下载
    func start(urlString: String) {
        let normalized = urlString.hasPrefix("http") ? urlString : "https://" + urlString
        guard let url = URL(string: normalized), url.host != nil else {
            assertionFailure("无效的下载地址: \(urlString)")
            return
        }
        let name = Self.fileName(for: url)
        let dl = LiveDownload(fileName: name, sourceURL: url)
        let task = session.downloadTask(with: url)
        dl.task = task
        dl.taskIdentifier = task.taskIdentifier
        downloads.insert(dl, at: 0)
        task.resume()
    }

    func pause(_ dl: LiveDownload) {
        guard dl.state == .downloading else { return }
        dl.task?.cancel(byProducingResumeData: { data in
            Task { @MainActor in dl.resumeData = data; dl.state = .paused }
        })
    }

    func resume(_ dl: LiveDownload) {
        guard dl.state == .paused else { return }
        let task: URLSessionDownloadTask
        if let data = dl.resumeData {
            task = session.downloadTask(withResumeData: data)
        } else {
            task = session.downloadTask(with: dl.sourceURL)
        }
        dl.task = task
        dl.taskIdentifier = task.taskIdentifier
        dl.state = .downloading
        task.resume()
    }

    func remove(_ dl: LiveDownload) {
        dl.task?.cancel()
        if let url = dl.localURL { try? FileManager.default.removeItem(at: url) }
        downloads.removeAll { $0.id == dl.id }
    }

    private func download(forTaskID id: Int) -> LiveDownload? {
        downloads.first { $0.taskIdentifier == id }
    }

    /// 由源地址推导文件名，缺省扩展名时给一个
    nonisolated static func fileName(for url: URL) -> String {
        let last = url.lastPathComponent
        if !last.isEmpty && last.contains(".") { return last }
        let host = url.host ?? "download"
        return "\(host)-\(Int(Date().timeIntervalSince1970)).html"
    }

    /// 目标已存在时生成不冲突的文件名（追加 ` (1)`/` (2)`…），避免同名下载相互覆盖造成数据丢失。
    nonisolated static func uniqueDestination(for name: String, in dir: URL) -> URL {
        let fm = FileManager.default
        let candidate = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 1
        while true {
            let next = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            let url = dir.appendingPathComponent(next)
            if !fm.fileExists(atPath: url.path) { return url }
            i += 1
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                               didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                               totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        Task { @MainActor in
            guard let dl = download(forTaskID: id) else { return }
            dl.bytesWritten = totalBytesWritten
            dl.totalBytes = totalBytesExpectedToWrite
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                               didFinishDownloadingTo location: URL) {
        // location 仅在本回调内有效，必须同步移动文件
        let suggested = downloadTask.response?.suggestedFilename
        let srcURL = downloadTask.originalRequest?.url
        let name = suggested ?? srcURL.map { DownloadManager.fileName(for: $0) } ?? "download.bin"
        // 唯一目标名，避免同名下载相互覆盖（dest 保证不存在，无需先 removeItem）。
        let dest = DownloadManager.uniqueDestination(for: name, in: DownloadManager.downloadsDirectory)
        let moveError: String?
        var finalSize: Int64 = 0
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            finalSize = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            moveError = nil
        } catch {
            moveError = error.localizedDescription
        }
        let id = downloadTask.taskIdentifier
        Task { @MainActor in
            guard let dl = download(forTaskID: id) else { return }
            if let moveError {
                dl.state = .failed(moveError)
            } else {
                if finalSize > 0 { dl.totalBytes = finalSize; dl.bytesWritten = finalSize }
                dl.localURL = dest
                dl.fileName = dest.lastPathComponent   // 回填实际落盘名，保证 UI 与磁盘一致
                dl.state = .completed
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        // 主动暂停（cancel by resume data）不算失败
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        let id = task.taskIdentifier
        let message = error.localizedDescription
        Task { @MainActor in
            guard let dl = download(forTaskID: id), dl.state != .completed else { return }
            dl.state = .failed(message)
        }
    }
}

// MARK: - 真实文件列表
enum FileStore {
    /// 读取目录下真实文件，映射为 UI 的 FileItem
    static func list(_ directory: URL = DownloadManager.downloadsDirectory) -> [FileItem] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]) else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            let isDir = values?.isDirectory ?? false
            let size = values?.fileSize ?? 0
            let date = values?.contentModificationDate ?? Date()
            let (symbol, color) = icon(for: url, isDir: isDir)
            return FileItem(
                name: url.lastPathComponent,
                size: isDir ? "—" : ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file),
                modified: formatter.string(from: date),
                symbol: symbol, color: color, isFolder: isDir
            )
        }
        .sorted { ($0.isFolder ? 0 : 1, $0.name) < ($1.isFolder ? 0 : 1, $1.name) }
    }

    static func delete(name: String, in directory: URL = DownloadManager.downloadsDirectory) {
        let url = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
    }

    /// 重命名（真实 moveItem）
    static func rename(_ name: String, to newName: String,
                       in directory: URL = DownloadManager.downloadsDirectory) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else { return }
        let src = directory.appendingPathComponent(name)
        let dest = directory.appendingPathComponent(trimmed)
        try FileManager.default.moveItem(at: src, to: dest)
    }

    /// 移动到子文件夹（folder 为 nil 表示移回根目录）
    static func move(_ name: String, toFolder folder: String?,
                     in directory: URL = DownloadManager.downloadsDirectory) throws {
        let src = directory.appendingPathComponent(name)
        let destDir = folder.map { directory.appendingPathComponent($0, isDirectory: true) } ?? directory
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dest = destDir.appendingPathComponent(name)
        guard src.standardizedFileURL != dest.standardizedFileURL else { return }
        try FileManager.default.moveItem(at: src, to: dest)
    }

    /// 列出子文件夹名
    static func folders(in directory: URL = DownloadManager.downloadsDirectory) -> [String] {
        list(directory).filter(\.isFolder).map(\.name)
    }

    /// 新建文件夹
    static func createFolder(_ name: String,
                             in directory: URL = DownloadManager.downloadsDirectory) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(trimmed, isDirectory: true),
                                                withIntermediateDirectories: true)
    }

    private static func icon(for url: URL, isDir: Bool) -> (String, Color) {
        if isDir { return ("folder.fill", Color(hex: 0x5AC8FA)) }
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "mkv", "avi": return ("play.rectangle.fill", Color(hex: 0xFF375F))
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return ("photo.fill", Color(hex: 0x34C759))
        case "mp3", "wav", "aac", "flac": return ("music.note", Color(hex: 0xFF9F0A))
        case "zip", "rar", "7z", "tar", "gz": return ("doc.zipper", Color(hex: 0xAF52DE))
        case "pdf": return ("doc.richtext.fill", Color(hex: 0xFF3B30))
        case "epub", "mobi", "azw3": return ("book.fill", Color(hex: 0xFF9500))
        case "html", "htm": return ("globe", Color(hex: 0x0A84FF))
        default: return ("doc.fill", Color(hex: 0x5AC8FA))
        }
    }
}
