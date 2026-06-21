import SwiftUI
import LocalAuthentication

// MARK: - 应用锁状态管理
/// 应用锁：基于 LocalAuthentication 做生物识别 / 设备密码解锁。
/// - 设计：@MainActor 单一可观察对象，UI 直接读 isLocked / appLockEnabled。
/// - 持久化：是否启用通过 @AppStorage("appLockEnabled") 存 UserDefaults。
/// - 容错：生物识别不可用回退设备密码；密码也不可用（如模拟器未设密码）直接放行，不崩溃。
@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    /// 是否启用应用锁（持久化）。关闭时立即解锁。
    @AppStorage("appLockEnabled") var appLockEnabled: Bool = false {
        didSet {
            // didSet 在 @AppStorage 下不会因外部写入触发，仅响应本类内赋值；保持状态同步即可。
            if appLockEnabled { isLocked = true } else { isLocked = false }
        }
    }

    /// 当前是否处于锁定遮挡状态。
    @Published var isLocked: Bool = false
    /// 最近一次解锁失败的提示文案（nil 表示无错误）。
    @Published var lastError: String?
    /// 是否正在进行系统验证（避免重复弹出系统 UI）。
    @Published private(set) var isAuthenticating: Bool = false

    private init() {
        // 启动时若启用了应用锁，则初始为锁定。
        isLocked = appLockEnabled
    }

    /// 当前设备可用的解锁方式描述（用于设置页展示与按钮文案）。
    var biometryLabel: String {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            // 无生物识别时，若可用设备密码也算可用
            if LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
                return "设备密码"
            }
            return "不可用"
        }
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "设备密码"
        }
    }

    /// 进入后台 / 切到前台时调用：若启用应用锁则重新上锁，等待用户解锁。
    func lockIfEnabled() {
        guard appLockEnabled else { return }
        isLocked = true
    }

    /// 触发系统验证。成功则解锁，失败保留锁定并记录错误。
    /// 若设备既无生物识别也无设备密码（如模拟器未设密码），直接放行，避免把用户永久锁死。
    func authenticate() {
        guard appLockEnabled, isLocked, !isAuthenticating else { return }

        let context = LAContext()
        context.localizedFallbackTitle = "输入设备密码"
        context.localizedCancelTitle = "取消"

        var policyError: NSError?
        // 优先生物识别+密码兜底的复合策略；不可用则退回纯设备密码策略。
        var policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics
        if !context.canEvaluatePolicy(policy, error: &policyError) {
            policy = .deviceOwnerAuthentication
            policyError = nil
            if !context.canEvaluatePolicy(policy, error: &policyError) {
                // 设备无任何可用解锁手段：放行，避免死锁。
                lastError = nil
                isLocked = false
                return
            }
        }

        isAuthenticating = true
        lastError = nil
        let reason = "解锁以使用浏览器"
        context.evaluatePolicy(policy, localizedReason: reason) { [weak self] success, error in
            // 回调可能在非主线程，统一切回主线程更新可观察状态。
            Task { @MainActor in
                guard let self else { return }
                self.isAuthenticating = false
                if success {
                    self.isLocked = false
                    self.lastError = nil
                } else {
                    let code = (error as? LAError)?.code
                    switch code {
                    case .userCancel, .systemCancel, .appCancel:
                        // 用户主动取消：不报错，保留锁定等待再次点击。
                        self.lastError = nil
                    default:
                        self.lastError = error?.localizedDescription ?? "验证失败，请重试"
                    }
                }
            }
        }
    }
}

// MARK: - 锁屏遮挡视图
/// 覆盖在 App 内容之上：未启用或已解锁时透传内容；锁定时用毛玻璃遮挡并提供解锁入口。
struct LockGateView<Content: View>: View {
    @StateObject private var lock = AppLockManager.shared
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            content
                // 锁定时给内容打码，防止后台截图泄露。
                .blur(radius: showOverlay ? 24 : 0)
                .allowsHitTesting(!showOverlay)

            if showOverlay {
                LockScreen(lock: lock)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showOverlay)
        .onChange(of: showOverlay) { _, locked in
            // 进入锁定态时自动尝试唤起系统验证（首次进入 / 回前台）。
            if locked { lock.authenticate() }
        }
        .onAppear {
            if showOverlay { lock.authenticate() }
        }
    }

    private var showOverlay: Bool { lock.appLockEnabled && lock.isLocked }
}

/// 锁屏内容：图标 + 解锁按钮 + 错误提示。
private struct LockScreen: View {
    @ObservedObject var lock: AppLockManager

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Theme.Colors.background.opacity(0.4).ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)

                Text("浏览器已锁定")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.Colors.primaryText)

                if let err = lock.lastError {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.xl)
                }

                Button {
                    lock.authenticate()
                } label: {
                    Label("使用 \(lock.biometryLabel) 解锁", systemImage: "faceid")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.vertical, Theme.Spacing.m)
                        .background(Theme.Colors.accent, in: Capsule())
                }
                .disabled(lock.isAuthenticating)
            }
            .padding(Theme.Spacing.xl)
        }
    }
}

// MARK: - 应用锁设置子页（供设置页 NavigationLink 接入）
struct AppLockSettingsView: View {
    @StateObject private var lock = AppLockManager.shared

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { lock.appLockEnabled },
                    set: { on in
                        Haptics.light()
                        lock.appLockEnabled = on
                        // 刚开启时立即上锁，便于用户验证流程是否生效。
                        if on { lock.isLocked = true; lock.authenticate() }
                    }
                )) {
                    SettingRowLabel(title: "启用应用锁", symbol: "lock.fill", color: Color(hex: 0x34C759))
                }
            } header: {
                Text("应用锁")
            } footer: {
                Text("开启后，每次回到浏览器都需要通过 \(lock.biometryLabel) 验证。设备未设置生物识别或密码时将自动放行。")
            }

            Section("当前可用方式") {
                LabeledContent("解锁方式", value: lock.biometryLabel)
            }
        }
        .navigationTitle("应用锁").navigationBarTitleDisplayMode(.inline)
    }
}
