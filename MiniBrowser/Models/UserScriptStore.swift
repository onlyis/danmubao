import SwiftUI
import WebKit

/// 用户脚本（油猴式）：在匹配网址上自动注入运行的一段 JavaScript。
struct UserScript: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// 匹配网址（glob，如 `*://*.youtube.com/*`）
    var match: String
    var code: String
    /// 运行时机：true = 页面结束（DOM 就绪），false = 页面开始
    var atDocumentEnd: Bool = true
    var enabled: Bool = true
}

/// 用户脚本存储层 + 注入器。
/// 注：`WebEngine` 在 init 时（首次访问标签前）从本 store 读取脚本写入 `WKUserContentController`，
/// 因此**新建标签**会用到最新脚本；编辑脚本不会影响已创建的引擎，直至该标签重建。
@MainActor
final class UserScriptStore: ObservableObject {
    /// WebEngine 在 init 阶段无法走环境注入，故用共享实例；视图层仍可 `@EnvironmentObject` 注入同一对象。
    static let shared = UserScriptStore()

    @Published var scripts: [UserScript] = [] { didSet { DiskStore.save(scripts, to: "userscripts.json") } }

    init() {
        scripts = DiskStore.load([UserScript].self, from: "userscripts.json") ?? Self.samples
    }

    func add(_ script: UserScript) { scripts.append(script) }
    func remove(_ script: UserScript) { scripts.removeAll { $0.id == script.id } }

    /// 生成可注入的 WKUserScript：每条启用脚本按 match 包一层网址守卫，仅在匹配页面运行。
    func installable() -> [WKUserScript] {
        scripts.filter(\.enabled).map { s in
            WKUserScript(source: Self.wrap(code: s.code, match: s.match),
                         injectionTime: s.atDocumentEnd ? .atDocumentEnd : .atDocumentStart,
                         forMainFrameOnly: false)
        }
    }

    // MARK: - 注入包装
    /// 用 `location.href` 对 match 做正则守卫；脚本自身异常被捕获，不影响页面与其它脚本。
    /// 供 PluginStore 复用（用户脚本类插件共用同一注入包装）。
    static func wrap(code: String, match: String) -> String {
        let pattern = jsStringLiteral(globToRegex(match))
        return """
        (function(){try{if(!(new RegExp(\(pattern))).test(location.href))return;
        \(code)
        }catch(e){console.error('[userscript]',e)}})();
        """
    }

    /// glob → 正则：转义正则元字符，`*` → `.*`，整串锚定。
    private static func globToRegex(_ glob: String) -> String {
        var out = "^"
        for ch in glob {
            if ch == "*" { out += ".*" }
            else if ".+?()[]{}^$|\\/".contains(ch) { out += "\\" + String(ch) }
            else { out += String(ch) }
        }
        return out + "$"
    }

    /// 把字符串编码成合法的 JS 字符串字面量（含外层引号），借 JSON 编码保证转义正确。
    private static func jsStringLiteral(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s) else { return "\"\"" }
        return String(decoding: data, as: UTF8.self)
    }

    static let samples: [UserScript] = [
        .init(name: "页面信息打印",
              match: "*://*/*",
              code: "console.log('[userscript] 已加载:', location.host);",
              atDocumentEnd: true, enabled: true),
        .init(name: "去除页面悬浮广告（示例）",
              match: "*://*.example.com/*",
              code: "document.querySelectorAll('[class*=float],[class*=popup]').forEach(function(e){e.style.display='none'});",
              atDocumentEnd: true, enabled: false),
        .init(name: "B站默认宽屏（示例）",
              match: "*://*.bilibili.com/video/*",
              code: "// 在此编写脚本\n(function(){\n  console.log('hello bilibili');\n})();",
              atDocumentEnd: true, enabled: false),
    ]
}
