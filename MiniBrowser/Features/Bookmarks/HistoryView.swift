import SwiftUI

/// 历史页：按日期分组（今天/昨天/更早）+ 搜索 + 清除选项。
struct HistoryView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    /// 按搜索词过滤历史（标题或网址命中），丢掉过滤后为空的分组。O(总条数)。
    private var sections: [HistorySection] {
        guard !search.isEmpty else { return library.history }
        return library.history.compactMap { section in
            let items = section.items.filter {
                $0.title.localizedCaseInsensitiveContains(search) || $0.url.localizedCaseInsensitiveContains(search)
            }
            return items.isEmpty ? nil : HistorySection(id: section.id, title: section.title, items: items)
        }
    }

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        Button { vm.open(url: item.url, title: item.title) } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                SiteIconSmall(glyph: item.glyph, color: item.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.system(size: 15))
                                        .foregroundStyle(Theme.Colors.primaryText).lineLimit(1)
                                    Text(item.url).font(.system(size: 12))
                                        .foregroundStyle(Theme.Colors.secondaryText).lineLimit(1)
                                }
                                Spacer()
                                Text(item.time).font(.system(size: 12)).foregroundStyle(Theme.Colors.tertiaryText)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { delete(item) } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索历史")
        .navigationTitle("历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { library.clearToday() } label: { Label("清除今天", systemImage: "trash") }
                    Button(role: .destructive) { library.clearAllHistory() } label: { Label("清除全部", systemImage: "trash.fill") }
                } label: { Text("清除") }
            }
        }
    }

    private func delete(_ item: HistoryItem) { library.removeHistory(item) }
}
