import SwiftUI

/// 主题 / 外观设置：外观模式 + OLED 纯黑。
struct AppearanceSettingsView: View {
    @EnvironmentObject var vm: BrowserViewModel
    var body: some View {
        List {
            Section("外观") {
                Picker("外观模式", selection: $vm.appearanceMode) {
                    ForEach(BrowserViewModel.AppearanceMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                Toggle(isOn: $vm.oledBlack) {
                    Label("OLED 纯黑", systemImage: "moonphase.new.moon")
                }
            } footer: {
                Text("深色模式下使用纯黑背景，在 OLED 屏幕上更省电、对比更强。")
            }
            Section {
                NavigationLink {
                    WallpaperSettingsView()
                } label: { Label("沉浸式壁纸", systemImage: "photo.artframe") }
            }
        }
        .navigationTitle("主题").navigationBarTitleDisplayMode(.inline)
    }
}

/// 沉浸式壁纸选择。
struct WallpaperSettingsView: View {
    @EnvironmentObject var vm: BrowserViewModel
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Wallpaper.allCases) { wp in
                    Button {
                        Haptics.light()
                        vm.wallpaper = wp
                    } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: .topTrailing) {
                                wp.thumbnail
                                    .frame(height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                                            .strokeBorder(vm.wallpaper == wp ? Theme.Colors.accent : Color.black.opacity(0.06),
                                                          lineWidth: vm.wallpaper == wp ? 3 : Theme.Size.hairline)
                                    )
                                if vm.wallpaper == wp {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.white, Theme.Colors.accent)
                                        .padding(8)
                                }
                            }
                            Text(wp.rawValue).font(.system(size: 13)).foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("沉浸式壁纸").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { } label: { Label("从相册选择", systemImage: "photo") }
                    Button { } label: { Label("模糊当前壁纸", systemImage: "drop") }
                } label: { Image(systemName: "plus") }
            }
        }
    }
}
