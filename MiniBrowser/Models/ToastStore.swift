import SwiftUI

/// 轻提示的独立存储层（从 BrowserViewModel 拆出）。
/// 拆分目的：toast 几乎每个用户动作都会触发，若挂在 god ViewModel 上，一次提示会让所有观察 vm 的视图重新求值；
/// 独立后只有 ToastView 随之刷新。
@MainActor
final class ToastStore: ObservableObject {
    struct ToastMessage: Equatable { var text: String; var symbol: String }

    @Published var toast: ToastMessage?
    private var dismissWork: DispatchWorkItem?

    func show(_ text: String, symbol: String = "checkmark.circle.fill") {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            toast = ToastMessage(text: text, symbol: symbol)
        }
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }
}
