import AVFoundation

/// 后台播放音频会话助手。
///
/// 独立成文件的原因：WebEngine.swift 没有 `import AVFoundation`，而本功能只能向 WebEngine
/// 追加方法、无法给它补 import；故把所有 AVFoundation 依赖隔离到这里，
/// `WebEngine.enableBackgroundPlayback()` 仅转发到 `BackgroundAudio.enable()`，
/// WebEngine.swift 内不出现任何 AVFoundation 符号。
///
/// 注意：要在 App 被挂起（切后台/锁屏）后仍持续出声，除本会话配置外，
/// 还需在 Info.plist 的 `UIBackgroundModes` 加入 `audio`（见 project.yml，交接说明已注明）。
@MainActor
enum BackgroundAudio {
    /// 把共享音频会话置为 `.playback` 并激活：
    /// 即便 App 进入后台或锁屏，WKWebView 内正在播放的网页媒体音频也会继续。
    /// 显式抛错由调用方决定是否上抛；这里把错误带上下文向上传递。
    static func enable() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback 类别允许后台/静音键开关下继续出声；mixWithOthers 让网页音频与其它 App 共存。
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // 带上当前会话类别等上下文，便于调试（不静默吞错）。
            throw BackgroundAudioError.activationFailed(
                category: session.category.rawValue,
                underlying: error
            )
        }
    }
}

/// 后台播放会话配置错误（携带调试上下文）。
enum BackgroundAudioError: LocalizedError {
    case activationFailed(category: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .activationFailed(category, underlying):
            return "激活后台音频会话失败（当前类别 \(category)）：\(underlying.localizedDescription)"
        }
    }
}
