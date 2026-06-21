import SwiftUI

/// 阅读列表（稍后读 / 离线阅读）：
/// 列出已保存文章（标题 + 来源 + 段落数），点击进入离线正文渲染（自带 ScrollView + 可调字号），
/// 左滑删除，无内容时空状态占位。所有数据来自 `ReadingListStore`，完全离线。
struct ReadingListView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ReadingListStore.shared

    var body: some View {
        Group {
            if store.all.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("阅读列表").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("返回") { dismiss() } }
        }
    }

    private var list: some View {
        List {
            ForEach(store.all) { item in
                NavigationLink {
                    OfflineArticleView(item: item)
                } label: {
                    row(item)
                }
                .listRowBackground(Theme.Colors.card)
            }
            .onDelete { offsets in
                // 由展示顺序映射回条目后删除（store.all 已是最新在前）。
                offsets.map { store.all[$0] }.forEach(store.remove)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ item: ReadingListItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title.isEmpty ? "（无标题）" : item.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.primaryText)
                .lineLimit(2)
            HStack(spacing: 8) {
                if !item.host.isEmpty {
                    Text(item.host)
                        .lineLimit(1)
                }
                Text("共 \(item.paragraphs.count) 段")
                Spacer(minLength: 0)
                Text(Self.dateText(item.savedAt))
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.Colors.secondaryText)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "text.book.closed")
                .font(.system(size: 44)).foregroundStyle(Theme.Colors.tertiaryText)
            Text("阅读列表为空").font(.system(size: 16)).foregroundStyle(Theme.Colors.secondaryText)
            Text("在网页中通过菜单「稍后读」保存文章，即可在此离线阅读。")
                .font(.system(size: 13)).foregroundStyle(Theme.Colors.tertiaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }
}

/// 离线正文渲染：复用阅读模式的版式（标题 + 来源行 + 段落连续滚动 + 可调字号 / 背景）。
/// 数据来自已保存的 `ReadingListItem`，不依赖网络。
struct OfflineArticleView: View {
    let item: ReadingListItem
    @State private var showSettings = false
    @State private var fontSize: CGFloat = 18
    @State private var bg: ReadingModeView.ReadBG = .paper

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text(item.title.isEmpty ? "（无标题）" : item.title)
                    .font(.system(size: fontSize + 8, weight: .bold))
                    .foregroundStyle(bg.text)
                if !item.host.isEmpty {
                    Text("来源 · \(item.host)    共 \(item.paragraphs.count) 段")
                        .font(.system(size: 13)).foregroundStyle(bg.text.opacity(0.5))
                }
                ForEach(Array(item.paragraphs.enumerated()), id: \.offset) { _, para in
                    Text(para)
                        .font(.system(size: fontSize))
                        .lineSpacing(fontSize * 0.45)
                        .foregroundStyle(bg.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Theme.Spacing.xl)
        }
        .background(bg.color.ignoresSafeArea())
        .navigationTitle("离线阅读").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(bg.color, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "textformat.size") }
            }
        }
        .sheet(isPresented: $showSettings) {
            ReadingSettingsSheet(fontSize: $fontSize, bg: $bg)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
    }
}
