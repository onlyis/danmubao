import Foundation

/// 网页媒体嗅探命中项：从页面 <video>/<audio>（含其 <source> 子节点）收集到的一条可下载媒体地址。
/// - `id` 由 url 派生（去重锚点），保证同一地址只出现一次。
/// - `kind` 区分音/视频，仅用于展示图标与文案。
/// - `title` 为可读标题（取最近标题文本或文件名），用于列表展示。
struct MediaHit: Codable, Identifiable, Hashable {
    /// 媒体类型（音 / 视频）。
    enum Kind: String, Codable {
        case video
        case audio

        /// 列表图标（SF Symbol）。
        var symbol: String {
            switch self {
            case .video: return "film"
            case .audio: return "waveform"
            }
        }
        /// 中文标签。
        var label: String {
            switch self {
            case .video: return "视频"
            case .audio: return "音频"
            }
        }
    }

    let id: String
    let url: String
    let kind: Kind
    let title: String

    /// 以媒体地址作为去重主键构造（同地址 id 相同）。
    init(url: String, kind: Kind, title: String) {
        self.id = url
        self.url = url
        self.kind = kind
        self.title = title
    }
}
