import SwiftUI

/// 书签 + 历史的独立存储层（从 BrowserViewModel 拆出）。
/// 拆分目的：书签/历史的写入只触发本 store 的刷新，不再让整个 ViewModel 失效、连带重绘无关视图。
@MainActor
final class LibraryStore: ObservableObject {

    @Published var bookmarks: [Bookmark] = [] {
        didSet { rebuildChildrenIndex(); persist(bookmarks, key: "bookmarks") }
    }
    @Published var history: [HistorySection] = [] { didSet { persist(history, key: "history") } }

    /// parentID → 直接子项 的索引。书签变更时 O(N) 重建一次，
    /// 使 `children(of:)`/`childCount(of:)` 降为 O(1)——否则文件夹树渲染是 O(文件夹数 × 书签总数)。
    private var childrenIndex: [UUID?: [Bookmark]] = [:]
    private func rebuildChildrenIndex() {
        var idx: [UUID?: [Bookmark]] = [:]
        for b in bookmarks { idx[b.parentID, default: []].append(b) }   // 保序：与原 filter 结果顺序一致
        childrenIndex = idx
    }

    enum AddResult { case added, duplicate, empty }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    /// 「今天」分组保留的最大条数，避免历史无上限增长 → 每次记录都整表重序列化越来越慢。
    private static let maxTodayItems = 200

    /// 应用 iCloud 远程变更时为 true，阻止把刚拉下来的数据又推回 iCloud（防回写环）。
    private var applyingRemote = false

    init() {
        // 属性观察器不在 init 中触发，加载已存数据不会回写
        bookmarks = DiskStore.load([Bookmark].self, from: "bookmarks.json") ?? SampleData.bookmarks
        history = DiskStore.load([HistorySection].self, from: "history.json") ?? SampleData.history

        // iCloud：接收远程变更；启动时若云端已有数据则拉取（last-writer-wins 简化策略）
        CloudSync.shared.onRemoteChange = { [weak self] key, data in self?.applyRemote(key: key, data: data) }
        if let d = CloudSync.shared.pull("bookmarks"),
           let v = try? JSONDecoder().decode([Bookmark].self, from: d) { bookmarks = v }
        if let d = CloudSync.shared.pull("history"),
           let v = try? JSONDecoder().decode([HistorySection].self, from: d) { history = v }
        rebuildChildrenIndex()   // init 中赋值不触发 didSet，显式建一次索引
    }

    /// 编码一次 → 本地落盘 + 推送 iCloud（应用远程变更时不回推）
    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            assertionFailure("LibraryStore 编码失败 key=\(key)")
            return
        }
        DiskStore.write(data, to: "\(key).json")
        if !applyingRemote { CloudSync.shared.push(data, for: key) }
    }

    /// 应用 iCloud 远程数据（覆盖本地）。didSet 仍会落地本地，但被 applyingRemote 阻止回推。
    private func applyRemote(key: String, data: Data) {
        applyingRemote = true
        defer { applyingRemote = false }
        switch key {
        case "bookmarks":
            if let v = try? JSONDecoder().decode([Bookmark].self, from: data) { bookmarks = v }
        case "history":
            if let v = try? JSONDecoder().decode([HistorySection].self, from: data) { history = v }
        default: break
        }
    }

    // MARK: - 书签
    @discardableResult
    func addBookmark(title: String, url: String) -> AddResult {
        guard !url.isEmpty else { return .empty }
        if bookmarks.contains(where: { $0.url == url && !$0.isFolder }) { return .duplicate }
        bookmarks.insert(
            Bookmark(title: title.isEmpty ? url : title, url: url,
                     glyph: String(url.prefix(1)).uppercased(), colorHex: 0x0A84FF),
            at: 0)
        return .added
    }

    /// 新建文件夹（置顶于目标父目录）
    @discardableResult
    func addFolder(name: String, parentID: UUID? = nil) -> Bookmark {
        let folder = Bookmark(title: name.isEmpty ? "新建文件夹" : name, url: "",
                              glyph: "", colorHex: 0x0A84FF, isFolder: true, parentID: parentID)
        bookmarks.insert(folder, at: 0)
        return folder
    }

    /// 编辑书签/文件夹（按 id 整体替换）
    func updateBookmark(_ bookmark: Bookmark) {
        if let i = bookmarks.firstIndex(where: { $0.id == bookmark.id }) { bookmarks[i] = bookmark }
    }

    /// 移动到某文件夹（parentID 为 nil = 根目录）。禁止移入自身。
    func moveBookmark(_ bookmark: Bookmark, to parentID: UUID?) {
        guard bookmark.id != parentID,
              let i = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[i].parentID = parentID
    }

    /// 某文件夹下的直接子项（parentID == nil 表示根目录）。走索引，O(1)。
    func children(of parentID: UUID?) -> [Bookmark] {
        childrenIndex[parentID] ?? []
    }

    /// 直接子项数量。走索引，O(1)（替代原先每个文件夹行各扫一遍全表）。
    func childCount(of folder: Bookmark) -> Int {
        childrenIndex[folder.id]?.count ?? 0
    }

    /// 全部文件夹（用于「移动到…」选择）
    var allFolders: [Bookmark] { bookmarks.filter(\.isFolder) }

    /// 删除：若为文件夹，子项上移到它所在的父目录，避免成为孤儿（一次性赋值，单次落盘）
    func removeBookmark(_ bookmark: Bookmark) {
        var list = bookmarks
        if bookmark.isFolder {
            let newParent = bookmark.parentID
            for i in list.indices where list[i].parentID == bookmark.id { list[i].parentID = newParent }
        }
        list.removeAll { $0.id == bookmark.id }
        bookmarks = list
    }

    // MARK: - 历史
    func recordHistory(title: String, url: String) {
        guard !url.isEmpty else { return }
        let item = HistoryItem(title: title.isEmpty ? url : title, url: url,
                               time: Self.timeFormatter.string(from: Date()),
                               glyph: String(url.prefix(1)).uppercased(), colorHex: 0x0A84FF)
        // 在本地副本上一次性改完再赋值，避免多次 didSet 触发多次落盘。
        var sections = history
        if let idx = sections.firstIndex(where: { $0.title == "今天" }) {
            // 同一地址重复访问/刷新只保留最新一条并置顶，防止历史膨胀与整表重复。
            sections[idx].items.removeAll { $0.url == url }
            sections[idx].items.insert(item, at: 0)
            if sections[idx].items.count > Self.maxTodayItems {
                sections[idx].items.removeLast(sections[idx].items.count - Self.maxTodayItems)
            }
        } else {
            sections.insert(HistorySection(title: "今天", items: [item]), at: 0)
        }
        history = sections
    }

    /// 页面加载完成后用真实网页标题回填「今天」里该地址的历史条目（地址栏/搜索打开时先以地址占位）。
    func updateHistoryTitle(url: String, title: String) {
        guard !url.isEmpty, !title.isEmpty,
              let s = history.firstIndex(where: { $0.title == "今天" }),
              let i = history[s].items.firstIndex(where: { $0.url == url }),
              history[s].items[i].title != title else { return }
        history[s].items[i].title = title
    }

    func removeHistory(_ item: HistoryItem) {
        for s in history.indices { history[s].items.removeAll { $0.id == item.id } }
        history.removeAll { $0.items.isEmpty }
    }

    func clearToday() { history.removeAll { $0.title == "今天" } }
    func clearAllHistory() { history = [] }
}
