import SwiftUI

@main
struct BrowserApp: App {
    @StateObject private var vm = BrowserViewModel()
    @StateObject private var downloads = DownloadManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // 仅 appLockEnabled 时生效：未解锁则遮挡 RootView 内容
            LockGateView {
                RootView()
                    .environmentObject(vm)
                    .environmentObject(vm.library)
                    .onAppear { vm.downloadManager = downloads }   // 供 bindActiveEngine 统一绑定下载回调
                    .environmentObject(vm.toasts)
                    .environmentObject(UserScriptStore.shared)
                    .environmentObject(PluginStore.shared)
                    .environmentObject(downloads)
            }
            .tint(Theme.Colors.accent)
            // 多语言：按设置的语言本地化（跟随系统 = 用户设备语言）。SwiftUI Text/Label 据此查本地化表。
            .environment(\.locale, vm.appLanguage.resolvedLocale)
            .id(vm.appLanguage)   // 切换语言即刻重建视图树，立即生效
        }
        // 进入后台时立即落盘标签，捕获最新标题/地址；前后台切换时按需重新上锁
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                vm.persistTabsNow()
                AppLockManager.shared.lockIfEnabled()
            } else if phase == .inactive {
                AppLockManager.shared.lockIfEnabled()
            }
        }
    }
}
