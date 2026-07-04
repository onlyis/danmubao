import SwiftUI

/// 主页设置：控制主页第二屏「网址导航目录」是否显示（真实生效，HomeView 据此条件渲染）。
struct HomeSettingsView: View {
    @EnvironmentObject var vm: BrowserViewModel
    var body: some View {
        Form {
            Section {
                Toggle("显示网址导航第二屏", isOn: $vm.showNavDirectory)
            } footer: {
                Text("关闭后，主页只保留常用宫格那一屏，不再左右滑出网址导航目录。")
            }
            Section {
                Toggle("搜索框固定在顶部", isOn: $vm.searchBarAtTop)
            } header: {
                Text("搜索框位置")
            } footer: {
                Text("关闭（默认）时，点击搜索后输入框显示在键盘上方——就在自定义搜索图标条的上面；开启则固定在页面顶部。")
            }
        }
        .navigationTitle("主页设置").navigationBarTitleDisplayMode(.inline)
    }
}

/// 标签页设置：新建标签时是否直接打开主页地址（真实生效，newTab 据此加载）。
struct TabSettingsView: View {
    @EnvironmentObject var vm: BrowserViewModel
    var body: some View {
        Form {
            Section {
                Toggle("新标签页直接打开主页", isOn: $vm.newTabOpensHomepage)
            } footer: {
                Text("开启后，点「+」新建标签会直接加载下面的主页地址，而不是空白新标签页。")
            }
            if vm.newTabOpensHomepage {
                Section("主页地址") {
                    TextField("example.com", text: $vm.homepageURL)
                        .autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                }
            }
        }
        .navigationTitle("标签页").navigationBarTitleDisplayMode(.inline)
    }
}

/// 视频播放设置：默认倍速（真实生效，页面有视频且加载完成后自动套用）。
struct VideoSettingsView: View {
    @EnvironmentObject var vm: BrowserViewModel
    private let rates: [Double] = BrowserViewModel.videoRates   // 与悬浮播放器倍速档一致（最高 7×）
    var body: some View {
        Form {
            Section {
                Picker("默认播放倍速", selection: $vm.defaultVideoRate) {
                    ForEach(rates, id: \.self) { r in
                        Text(r == 1.0 ? "正常 (1.0×)" : String(format: "%.2g×", r)).tag(r)
                    }
                }
            } footer: {
                Text("网页加载完成后，若检测到视频则自动应用该倍速。部分站点可能在播放时覆盖此设置。")
            }
        }
        .navigationTitle("视频播放").navigationBarTitleDisplayMode(.inline)
    }
}
