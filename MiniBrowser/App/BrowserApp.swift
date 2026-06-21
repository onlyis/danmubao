import SwiftUI

@main
struct BrowserApp: App {
    @StateObject private var vm = BrowserViewModel()
    @StateObject private var downloads = DownloadManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
                .environmentObject(vm.library)
                .onAppear { vm.downloadManager = downloads }   // 供 bindActiveEngine 统一绑定下载回调
                .environmentObject(vm.toasts)
                .environmentObject(UserScriptStore.shared)
                .environmentObject(PluginStore.shared)
                .environmentObject(downloads)
                .tint(Theme.Colors.accent)
        }
        // 进入后台时立即落盘标签，捕获最新标题/地址
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { vm.persistTabsNow() }
        }
    }
}
