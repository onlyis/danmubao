import SwiftUI

@main
struct BrowserApp: App {
    @StateObject private var vm = BrowserViewModel()
    @StateObject private var downloads = DownloadManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vm)
                .environmentObject(vm.library)
                .environmentObject(vm.toasts)
                .environmentObject(UserScriptStore.shared)
                .environmentObject(downloads)
                .tint(Theme.Colors.accent)
        }
    }
}
