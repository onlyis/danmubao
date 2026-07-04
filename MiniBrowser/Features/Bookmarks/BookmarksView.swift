import SwiftUI

/// 书签页：文件夹层级导航 + 搜索 + 新建/编辑/移动/删除。根目录由 `route = .bookmarks` 进入。
struct BookmarksView: View {
    var body: some View { BookmarkFolderView(folderID: nil, title: "书签", isRoot: true) }
}

/// 包一层让导出文件 URL 可作为 `.sheet(item:)` 的标识（URL 本身不是 Identifiable）。
private struct ExportedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// 某个文件夹（folderID == nil 为根目录）的书签列表，可递归进入子文件夹。
struct BookmarkFolderView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let folderID: UUID?
    let title: String
    var isRoot: Bool = false

    @State private var search = ""
    @State private var editing: Bookmark?
    @State private var moving: Bookmark?
    @State private var newFolderName = ""
    @State private var showNewFolder = false

    // 导入 / 导出
    @State private var showImporter = false
    @State private var exportedFile: ExportedFile?

    var body: some View {
        List {
            ForEach(items) { bm in
                if bm.isFolder {
                    NavigationLink {
                        BookmarkFolderView(folderID: bm.id, title: bm.title)
                    } label: {
                        BookmarkRowLabel(bookmark: bm, subtitle: "\(library.childCount(of: bm)) 个项目")
                    }
                    .rowActions(bookmark: bm, library: library,
                                onEdit: { editing = bm }, onMove: { moving = bm })
                } else {
                    Button {
                        vm.open(url: bm.url, title: bm.title)   // open() 内已收起全屏路由
                    } label: {
                        BookmarkRowLabel(bookmark: bm, subtitle: bm.url)
                    }
                    .rowActions(bookmark: bm, library: library,
                                onEdit: { editing = bm }, onMove: { moving = bm })
                }
            }

            if isRoot && search.isEmpty {
                Section {
                    Button { showImporter = true } label: { Label("导入书签", systemImage: "square.and.arrow.down") }
                    Button { exportBookmarks() } label: { Label("导出书签", systemImage: "square.and.arrow.up") }
                    Label { Text("iCloud 同步") } icon: { Image(systemName: "icloud") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索书签")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isRoot {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = Bookmark(title: "", url: "", glyph: "", colorHex: 0x0A84FF, parentID: folderID) } label: {
                        Label("新建书签", systemImage: "plus")
                    }
                    Button { showNewFolder = true } label: { Label("新建文件夹", systemImage: "folder.badge.plus") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: $editing) { bm in
            BookmarkEditSheet(draft: bm, parentID: bm.parentID ?? folderID)
        }
        .sheet(item: $moving) { bm in
            BookmarkMoveSheet(bookmark: bm)
        }
        .sheet(isPresented: $showImporter) {
            BookmarkImportPicker { url in
                showImporter = false
                importBookmarks(from: url)
            }
            .ignoresSafeArea()
        }
        // 导出成功后弹系统分享（用户可另存到「文件」/隔空投送等），文件已落地 Downloads。
        .sheet(item: $exportedFile) { file in
            ActivityView(items: [file.url])
        }
        .alert("新建文件夹", isPresented: $showNewFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) { newFolderName = "" }
            Button("创建") {
                library.addFolder(name: newFolderName, parentID: folderID)
                newFolderName = ""
            }
        }
    }

    private var items: [Bookmark] {
        let list = library.children(of: folderID)
        guard !search.isEmpty else { return list }
        return list.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    /// 导出全部书签为 Netscape HTML 到 Downloads，并弹分享面板。
    private func exportBookmarks() {
        guard let url = library.exportHTML() else {
            vm.showToast("导出失败", symbol: "exclamationmark.triangle.fill")
            return
        }
        vm.showToast("已导出到下载：\(url.lastPathComponent)", symbol: "square.and.arrow.up")
        exportedFile = ExportedFile(url: url)
    }

    /// 从选中的 HTML 文件导入书签。
    private func importBookmarks(from url: URL) {
        let count = library.importHTML(from: url)
        if count > 0 {
            vm.showToast("已导入 \(count) 个书签", symbol: "square.and.arrow.down")
        } else {
            vm.showToast("未找到可导入的书签", symbol: "exclamationmark.triangle.fill")
        }
    }
}

/// 行内容（图标 + 标题 + 副标题）
struct BookmarkRowLabel: View {
    let bookmark: Bookmark
    let subtitle: String
    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            if bookmark.isFolder {
                Image(systemName: "folder.fill")
                    .font(.system(size: 26)).foregroundStyle(Theme.Colors.accent).frame(width: 30)
            } else {
                SiteIconSmall(glyph: bookmark.glyph, color: bookmark.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.title.isEmpty ? bookmark.url : bookmark.title)
                    .font(.system(size: 15)).foregroundStyle(Theme.Colors.primaryText).lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12)).foregroundStyle(Theme.Colors.secondaryText).lineLimit(1)
            }
            Spacer()
        }
    }
}

/// 统一的滑动 / 长按菜单（删除 / 编辑 / 移动）
private struct RowActions: ViewModifier {
    let bookmark: Bookmark
    let library: LibraryStore
    let onEdit: () -> Void
    let onMove: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { library.removeBookmark(bookmark) } label: {
                    Label("删除", systemImage: "trash")
                }
                Button { onEdit() } label: { Label("编辑", systemImage: "pencil") }.tint(Theme.Colors.accent)
                Button { onMove() } label: { Label("移动", systemImage: "folder") }.tint(Color(hex: 0xFF9500))
            }
            .contextMenu {
                Button { onEdit() } label: { Label("编辑", systemImage: "pencil") }
                Button { onMove() } label: { Label("移动到…", systemImage: "folder") }
                Button(role: .destructive) { library.removeBookmark(bookmark) } label: { Label("删除", systemImage: "trash") }
            }
    }
}

private extension View {
    func rowActions(bookmark: Bookmark, library: LibraryStore,
                    onEdit: @escaping () -> Void, onMove: @escaping () -> Void) -> some View {
        modifier(RowActions(bookmark: bookmark, library: library, onEdit: onEdit, onMove: onMove))
    }
}

/// 新建 / 编辑书签（文件夹也可改名）
struct BookmarkEditSheet: View {
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: Bookmark
    let parentID: UUID?

    private var isNew: Bool { !library.bookmarks.contains { $0.id == draft.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $draft.title)
                    if !draft.isFolder {
                        TextField("网址", text: $draft.url)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                }
            }
            .navigationTitle(draft.isFolder ? "编辑文件夹" : (isNew ? "新建书签" : "编辑书签"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }.fontWeight(.semibold)
                        .disabled(draft.title.isEmpty && draft.url.isEmpty)
                }
            }
        }
    }

    private func save() {
        if draft.glyph.isEmpty && !draft.url.isEmpty { draft.glyph = String(draft.url.prefix(1)).uppercased() }
        if isNew {
            draft.parentID = parentID
            library.bookmarks.insert(draft, at: 0)
        } else {
            library.updateBookmark(draft)
        }
        dismiss()
    }
}

/// 移动到某文件夹
struct BookmarkMoveSheet: View {
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let bookmark: Bookmark

    var body: some View {
        NavigationStack {
            List {
                Button {
                    library.moveBookmark(bookmark, to: nil); dismiss()
                } label: {
                    Label("根目录", systemImage: "house").foregroundStyle(Theme.Colors.primaryText)
                }
                ForEach(destinations) { folder in
                    Button {
                        library.moveBookmark(bookmark, to: folder.id); dismiss()
                    } label: {
                        Label(folder.title, systemImage: "folder").foregroundStyle(Theme.Colors.primaryText)
                    }
                }
            }
            .navigationTitle("移动到…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    /// 可选目标：所有文件夹，排除自身（避免文件夹移入自己）
    private var destinations: [Bookmark] {
        library.allFolders.filter { $0.id != bookmark.id }
    }
}
