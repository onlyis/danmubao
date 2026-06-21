import Foundation

/// 稍后读 / 离线阅读列表的单条条目。
/// 抓取当前页正文后整篇保存（标题 / 来源 host / 原始 url / 段落 / 保存时间），
/// 之后可完全离线渲染，不再依赖网络。
struct ReadingListItem: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var host: String
    var url: String
    var paragraphs: [String]
    var savedAt: Date

    init(id: UUID = UUID(), title: String, host: String, url: String, paragraphs: [String], savedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.host = host
        self.url = url
        self.paragraphs = paragraphs
        self.savedAt = savedAt
    }
}

/// 稍后读条目的持久化存储（单例，主线程隔离）。
/// 条目保存到 Documents/readinglist.json；新增即落盘（`didSet`），启动恢复。
@MainActor
final class ReadingListStore: ObservableObject {
    static let shared = ReadingListStore()

    private static let fileName = "readinglist.json"

    /// 已保存的文章（最新在前）。变更即异步落盘。
    @Published private(set) var items: [ReadingListItem] {
        didSet { DiskStore.save(items, to: Self.fileName) }
    }

    private init() {
        // init 中属性观察器不触发，加载不会回写。文件不存在时回落空列表。
        items = DiskStore.load([ReadingListItem].self, from: Self.fileName) ?? []
    }

    /// 全部条目（最新在前）的只读快照。
    var all: [ReadingListItem] { items }

    /// 新增一篇文章到稍后读。空正文显式拒绝（避免存入无内容条目）。
    /// 同 url 视为同一篇：去重后置顶（更新为最新抓取的内容）。
    func add(_ item: ReadingListItem) throws {
        guard !item.paragraphs.isEmpty else {
            throw ReadingListError.emptyArticle(url: item.url)
        }
        var next = items.filter { $0.url != item.url || item.url.isEmpty }
        next.insert(item, at: 0)
        items = next
    }

    /// 删除指定条目。
    func remove(_ item: ReadingListItem) {
        items.removeAll { $0.id == item.id }
    }
}

/// 稍后读相关错误：显式抛出并携带调试上下文。
enum ReadingListError: LocalizedError {
    case emptyArticle(url: String)

    var errorDescription: String? {
        switch self {
        case .emptyArticle(let url):
            return "未能从该页面抽取到正文，无法加入稍后读（url=\(url)）"
        }
    }
}
