import SwiftUI

/// 文件管理：iOS Files 风格。分类入口宫格 + 文件列表 + 网格/列表切换。
struct FilesView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @EnvironmentObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var isGrid = false
    @State private var search = ""
    @State private var files: [FileItem] = []
    @State private var errorMessage: String?
    @State private var renameTarget: FileItem?
    @State private var renameText: String = ""
    @State private var moveTarget: FileItem?
    @State private var newFolderPrompt = false
    @State private var newFolderName = ""

    private let categoryColumns = [GridItem(.flexible()), GridItem(.flexible())]

    private var filtered: [FileItem] {
        search.isEmpty ? files : files.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: categoryColumns, spacing: Theme.Spacing.m) {
                    ForEach(FileKind.allCases, id: \.self) { kind in
                        CategoryCard(kind: kind)
                    }
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section("下载目录 (\(files.count))") {
                if filtered.isEmpty {
                    Text("暂无文件").font(.system(size: 14)).foregroundStyle(Theme.Colors.tertiaryText)
                } else {
                    ForEach(filtered) { file in
                        FileRow(file: file,
                                onDelete: { delete(file) },
                                onCompress: { compress(file) },
                                onExtract: { extract(file) },
                                onRename: { renameText = file.name; renameTarget = file },
                                onMove: { moveTarget = file })
                    }
                }
            }

            Section {
                Button { } label: { Label("Wi-Fi 传输", systemImage: "wifi") }
                Button { } label: { Label("从相册导入", systemImage: "photo") }
                Button { } label: { Label("从系统文件导入", systemImage: "folder.badge.plus") }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: "搜索文件")
        .navigationTitle("文件")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: manager.downloads.count) { _, _ in reload() }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert("重命名", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("确定") { performRename() }
        }
        .alert("新建文件夹", isPresented: $newFolderPrompt) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) { newFolderName = "" }
            Button("创建") { createFolder() }
        }
        .sheet(item: $moveTarget) { file in
            MoveSheet(fileName: file.name, folders: FileStore.folders()) { folder in
                performMove(file, to: folder)
            }
            .presentationDetents([.medium])
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { isGrid.toggle() } label: {
                        Label(isGrid ? "列表视图" : "网格视图", systemImage: isGrid ? "list.bullet" : "square.grid.2x2")
                    }
                    Button(action: reload) { Label("刷新", systemImage: "arrow.clockwise") }
                    Button { newFolderName = ""; newFolderPrompt = true } label: { Label("新建文件夹", systemImage: "folder.badge.plus") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private func reload() { files = FileStore.list() }

    private func performRename() {
        guard let file = renameTarget else { return }
        do { try FileStore.rename(file.name, to: renameText); reload() }
        catch { errorMessage = "重命名失败：\(error.localizedDescription)" }
        renameTarget = nil
    }

    private func performMove(_ file: FileItem, to folder: String?) {
        do { try FileStore.move(file.name, toFolder: folder); reload(); vm.showToast("已移动") }
        catch { errorMessage = "移动失败：\(error.localizedDescription)" }
    }

    private func createFolder() {
        do { try FileStore.createFolder(newFolderName); reload() }
        catch { errorMessage = "创建失败：\(error.localizedDescription)" }
        newFolderName = ""
    }

    private func delete(_ file: FileItem) {
        FileStore.delete(name: file.name)
        reload()
    }

    private func compress(_ file: FileItem) {
        let dir = DownloadManager.downloadsDirectory
        let src = dir.appendingPathComponent(file.name)
        let base = file.isFolder ? file.name : (file.name as NSString).deletingPathExtension
        let dest = uniqueURL(dir.appendingPathComponent(base + ".zip"))
        do {
            try ArchiveStore.zip(item: src, to: dest)
            reload()
        } catch {
            errorMessage = "压缩失败：\(error.localizedDescription)"
        }
    }

    private func extract(_ file: FileItem) {
        let dir = DownloadManager.downloadsDirectory
        let src = dir.appendingPathComponent(file.name)
        let dest = uniqueURL(dir.appendingPathComponent((file.name as NSString).deletingPathExtension))
        do {
            try ArchiveStore.unzip(src, to: dest)
            reload()
        } catch {
            errorMessage = "解压失败：\(error.localizedDescription)"
        }
    }

    /// 避免覆盖：若已存在则追加序号
    private func uniqueURL(_ url: URL) -> URL {
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

private struct CategoryCard: View {
    let kind: FileKind
    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: kind.symbol).font(.system(size: 18)).foregroundStyle(kind.color).frame(width: 26)
            Text(kind.rawValue).font(.system(size: 14)).foregroundStyle(Theme.Colors.primaryText)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.m).frame(height: 46)
        .background(Theme.Colors.groupedBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
    }
}

private struct FileRow: View {
    let file: FileItem
    var onDelete: () -> Void
    var onCompress: () -> Void
    var onExtract: () -> Void
    var onRename: () -> Void
    var onMove: () -> Void

    private var fileURL: URL { DownloadManager.downloadsDirectory.appendingPathComponent(file.name) }
    private var isZip: Bool { file.name.lowercased().hasSuffix(".zip") }

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: file.symbol).font(.system(size: 24)).foregroundStyle(file.color).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.system(size: 15)).foregroundStyle(Theme.Colors.primaryText).lineLimit(1)
                Text(file.isFolder ? file.modified : "\(file.size) · \(file.modified)")
                    .font(.system(size: 12)).foregroundStyle(Theme.Colors.secondaryText)
            }
            Spacer()
            Menu {
                if !file.isFolder { ShareLink(item: fileURL) { Label("分享", systemImage: "square.and.arrow.up") } }
                Button(action: onRename) { Label("重命名", systemImage: "pencil") }
                Button(action: onMove) { Label("移动", systemImage: "folder") }
                if !file.isFolder {
                    if isZip {
                        Button(action: onExtract) { Label("解压到此处", systemImage: "archivebox") }
                    } else {
                        Button(action: onCompress) { Label("压缩为 zip", systemImage: "doc.zipper") }
                    }
                }
                Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16)).foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
        .swipeActions {
            Button(role: .destructive, action: onDelete) { Label("删除", systemImage: "trash") }
            if !file.isFolder {
                if isZip {
                    Button(action: onExtract) { Label("解压", systemImage: "archivebox") }.tint(Theme.Colors.accent)
                } else {
                    Button(action: onCompress) { Label("压缩", systemImage: "doc.zipper") }.tint(Theme.Colors.accent)
                }
            }
        }
    }
}

/// 移动到文件夹选择
private struct MoveSheet: View {
    let fileName: String
    let folders: [String]
    var onPick: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("移动「\(fileName)」到") {
                    Button { onPick(nil); dismiss() } label: {
                        Label("下载（根目录）", systemImage: "folder")
                    }
                    ForEach(folders, id: \.self) { folder in
                        Button { onPick(folder); dismiss() } label: {
                            Label(folder, systemImage: "folder.fill")
                        }
                    }
                    if folders.isEmpty {
                        Text("暂无子文件夹").font(.system(size: 13)).foregroundStyle(Theme.Colors.tertiaryText)
                    }
                }
            }
            .navigationTitle("移动到").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("取消") { dismiss() } } }
        }
    }
}
