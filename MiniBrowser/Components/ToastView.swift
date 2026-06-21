import SwiftUI

/// 轻量全局提示：居中胶囊 + 图标 + 文案，自动消失。
struct ToastView: View {
    let message: ToastStore.ToastMessage
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Text(message.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.82), in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}
