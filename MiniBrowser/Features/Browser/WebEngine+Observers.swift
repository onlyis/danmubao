import SwiftUI
import WebKit
import Security

/// WebEngine 的状态观察职责：KVO 绑定（estimatedProgress / title / url / canGoBack / canGoForward）
/// 与站点证书解析（基于 didReceive challenge 缓存的 SecTrust）。
extension WebEngine {
    func setupObservers() {
        func bind<T>(_ keyPath: KeyPath<WKWebView, T>, _ apply: @escaping @MainActor (WKWebView) -> Void) -> NSKeyValueObservation {
            webView.observe(keyPath, options: [.new]) { wv, _ in
                // WKWebView 的 KVO 通知本就在主线程派发：直接同步执行，省掉每次进度更新的 Task 调度开销。
                // 兜底——万一不在主线程，回主线程异步执行。
                if Thread.isMainThread { MainActor.assumeIsolated { apply(wv) } }
                else { Task { @MainActor in apply(wv) } }
            }
        }
        observations = [
            bind(\.estimatedProgress) { [weak self] wv in self?.progress = wv.estimatedProgress },
            bind(\.title) { [weak self] wv in if let t = wv.title, !t.isEmpty { self?.title = t } },
            bind(\.url) { [weak self] wv in self?.displayURL = wv.url?.host ?? wv.url?.absoluteString ?? "" },
            bind(\.canGoBack) { [weak self] wv in self?.canGoBack = wv.canGoBack },
            bind(\.canGoForward) { [weak self] wv in self?.canGoForward = wv.canGoForward },
        ]
    }

    // MARK: - 站点证书：解析最近缓存的 SecTrust（仅用 iOS 可用 API）
    func certificateInfo(host: String) -> CertificateInfo? {
        guard let trust = latestServerTrust else { return nil }
        let chain: [SecCertificate]
        if #available(iOS 15.0, *) {
            chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        } else {
            var arr: [SecCertificate] = []
            for i in 0..<SecTrustGetCertificateCount(trust) {
                if let c = SecTrustGetCertificateAtIndex(trust, i) { arr.append(c) }
            }
            chain = arr
        }
        guard let leaf = chain.first else { return nil }
        let subject = (SecCertificateCopySubjectSummary(leaf) as String?) ?? "未知"
        // iOS 不暴露 SecCertificateCopyValues：用证书链上一级主体摘要近似「颁发者」。
        let issuer = chain.count > 1 ? ((SecCertificateCopySubjectSummary(chain[1]) as String?) ?? "未知") : "未知"
        return CertificateInfo(host: host, subjectSummary: subject, issuerSummary: issuer,
                               notBefore: nil, notAfter: nil, serialNumber: "", chainLength: chain.count)
    }
}
