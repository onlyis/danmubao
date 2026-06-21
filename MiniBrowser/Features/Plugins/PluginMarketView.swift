import SwiftUI

/// 插件市场：按分类浏览内置插件，安装 / 启用 / 卸载。
struct PluginMarketView: View {
    @EnvironmentObject var store: PluginStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(store.installed) { plugin in
                    NavigationLink { PluginDetailView(plugin: plugin) } label: { PluginRow(plugin: plugin) }
                }
                if store.installed.isEmpty {
                    Text("还没有安装插件，从下方市场添加")
                        .font(.system(size: 13)).foregroundStyle(Theme.Colors.secondaryText)
                }
            } header: { Text("已安装") }

            ForEach(Plugin.Category.allCases) { category in
                let items = store.plugins(in: category)
                if !items.isEmpty {
                    Section {
                        ForEach(items) { plugin in
                            NavigationLink { PluginDetailView(plugin: plugin) } label: { PluginRow(plugin: plugin) }
                        }
                    } header: {
                        Label(category.rawValue, systemImage: category.symbol)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("插件市场")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { dismissDoneIfRoot() }
    }
}

/// 市场 / 已安装 列表行
struct PluginRow: View {
    @EnvironmentObject var store: PluginStore
    let plugin: Plugin

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            SiteIcon(glyph: "", color: plugin.color, symbol: plugin.symbol, size: 36, corner: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.Colors.primaryText).lineLimit(1)
                Text(plugin.summary).font(.system(size: 12)).foregroundStyle(Theme.Colors.secondaryText).lineLimit(1)
            }
            Spacer()
            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if plugin.installed {
            Toggle("", isOn: Binding(
                get: { plugin.enabled },
                set: { store.setEnabled(plugin, $0) }
            )).labelsHidden()
        } else {
            Button("获取") { store.install(plugin) }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}

/// 插件详情
struct PluginDetailView: View {
    @EnvironmentObject var store: PluginStore
    let plugin: Plugin

    /// 取 store 中的最新状态（安装/启用会变）
    private var current: Plugin { store.plugins.first { $0.id == plugin.id } ?? plugin }

    var body: some View {
        List {
            Section {
                HStack(spacing: Theme.Spacing.m) {
                    SiteIcon(glyph: "", color: plugin.color, symbol: plugin.symbol, size: 52, corner: 12)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plugin.name).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.Colors.primaryText)
                        Text("\(plugin.author) · v\(plugin.version)").font(.system(size: 12)).foregroundStyle(Theme.Colors.secondaryText)
                        Text(plugin.category.rawValue).font(.system(size: 11))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(plugin.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(plugin.color)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("简介") {
                Text(plugin.detail).font(.system(size: 14)).foregroundStyle(Theme.Colors.primaryText)
            }

            Section {
                if current.installed {
                    Toggle("启用", isOn: Binding(
                        get: { current.enabled },
                        set: { store.setEnabled(plugin, $0) }
                    ))
                    Button("卸载插件", role: .destructive) { store.uninstall(plugin) }
                } else {
                    Button { store.install(plugin) } label: {
                        Label("获取并启用", systemImage: "arrow.down.circle.fill")
                    }
                }
            } footer: {
                Text("插件的启用/安装变更会在下次打开网页的新标签中生效。")
            }
        }
        .navigationTitle(plugin.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
