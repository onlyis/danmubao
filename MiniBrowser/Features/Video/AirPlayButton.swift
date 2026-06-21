import SwiftUI
import AVKit

/// AVRoutePickerView 的 SwiftUI 包装：点击后由系统弹出真实的 AirPlay 设备选择器。
/// 真机才会列出真实的投屏/音频设备；模拟器至少能弹出选择 UI、不会崩溃。
struct AirPlayRoutePicker: UIViewRepresentable {
    /// 图标主色（未激活时）
    var tintColor: UIColor = .label
    /// 激活（已连接到外部设备）时的高亮色
    var activeTintColor: UIColor = UIColor(Theme.Colors.accent)

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = tintColor
        picker.activeTintColor = activeTintColor
        // 视频路由：优先投屏画面而非仅音频
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
        uiView.activeTintColor = activeTintColor
    }
}

/// AirPlay 小弹层：展示一个大号的系统路由选择按钮 + 说明文案。
/// 由菜单「AirPlay」触发（vm.showAirPlay），点击中央按钮即弹出系统设备选择器。
struct AirPlaySheet: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Capsule()
                .fill(Theme.Colors.separator)
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Image(systemName: "airplayvideo")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Theme.Colors.accent)
                .padding(.top, 12)

            Text("隔空播放")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.Colors.primaryText)

            Text("选择附近的 Apple TV、智能电视或音频设备进行投屏。")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            // 系统路由选择按钮：自身处理点击并弹出设备列表
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .fill(Theme.Colors.background)
                AirPlayRoutePicker()
                    .frame(width: 56, height: 56)
            }
            .frame(width: 84, height: 84)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(Theme.Colors.separator, lineWidth: 1)
            }

            Text("点击上方按钮选择设备")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.secondaryText)

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                Text("完成")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.Colors.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.card)
    }
}
