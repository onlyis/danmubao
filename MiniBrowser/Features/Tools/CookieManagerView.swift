import SwiftUI
import WebKit

// MARK: - Cookie 管理（真实读写全局 Cookie 存储）
//
// 数据源：WKWebsiteDataStore.default().httpCookieStore —— 即普通（持久化）标签共享的 Cookie 仓库。
// 无痕标签使用独立的 nonPersistent 存储、不在此处展示（符合无痕语义）。
// WKHTTPCookieStore 的 getAllCookies / delete 均为异步回调，且回调不保证在主线程，
// 故所有回调都显式 Task { @MainActor } 回主线程后再改 @State。
struct CookieManagerView: View {
    @EnvironmentObject var vm: BrowserViewModel

    /// 按域名分组：domain -> 该域名下的 cookie 列表。
    @State private var groups: [String: [HTTPCookie]] = [:]
    @State private var loaded = false

    /// 全局持久化 Cookie 存储（与普通浏览标签共享）。
    private var cookieStore: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }

    /// 当前网页的 host，用于把当前站点分组置顶并标记。
    private var currentHost: String? {
        guard let h = URL(string: vm.currentURL)?.host, !h.isEmpty else { return nil }
        return h
    }

    /// 排序后的域名：当前站点（含其父域）优先，其余按字母序。
    private var sortedDomains: [String] {
        let host = currentHost
        return groups.keys.sorted { a, b in
            let aCur = matchesCurrent(a, host: host)
            let bCur = matchesCurrent(b, host: host)
            if aCur != bCur { return aCur }            // 当前站点置顶
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    /// 域名是否与当前站点匹配（cookie domain 常带前导点，做后缀兜底）。
    private func matchesCurrent(_ domain: String, host: String?) -> Bool {
        guard let host else { return false }
        let d = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        return host == d || host.hasSuffix("." + d) || d.hasSuffix(host)
    }

    var body: some View {
        List {
            if loaded && groups.isEmpty {
                Section {
                    Text("暂无 Cookie")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Theme.Spacing.l)
                }
            }
            ForEach(sortedDomains, id: \.self) { domain in
                domainSection(domain)
            }
        }
        .navigationTitle("Cookie 管理").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            dismissDoneIfRoot()
            ToolbarItem(placement: .topBarTrailing) {
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .onAppear { if !loaded { reload() } }
    }

    // MARK: 单个域名分组
    @ViewBuilder
    private func domainSection(_ domain: String) -> some View {
        let cookies = groups[domain] ?? []
        Section {
            ForEach(cookies, id: \.cookieID) { c in
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.Colors.primaryText)
                    Text(c.value).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.Colors.secondaryText).lineLimit(1)
                }
                .swipeActions {
                    Button(role: .destructive) { delete(c) } label: { Label("删除", systemImage: "trash") }
                    Button {
                        UIPasteboard.general.string = "\(c.name)=\(c.value)"
                        vm.showToast("已复制 Cookie", symbol: "doc.on.doc")
                    } label: { Label("复制", systemImage: "doc.on.doc") }.tint(Theme.Colors.accent)
                }
            }
            Button(role: .destructive) { clear(domain: domain) } label: {
                Label("清空此域名 Cookie", systemImage: "trash")
            }
            .font(.system(size: 13))
        } header: {
            HStack(spacing: Theme.Spacing.s) {
                Text(domain)
                if matchesCurrent(domain, host: currentHost) {
                    Text("当前网站")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.Colors.accent.opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.Colors.accent)
                }
                Spacer()
                Text("\(cookies.count)").foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }

    // MARK: 读取 / 刷新（异步回调回主线程）
    private func reload() {
        cookieStore.getAllCookies { all in
            // getAllCookies 回调不保证在主线程：显式回主线程后再更新 @State。
            Task { @MainActor in
                groups = Dictionary(grouping: all) { $0.domain }
                loaded = true
            }
        }
    }

    // MARK: 删除单条（删除后刷新列表）
    private func delete(_ cookie: HTTPCookie) {
        cookieStore.delete(cookie) {
            Task { @MainActor in
                vm.showToast("已删除 Cookie", symbol: "trash")
                reload()
            }
        }
    }

    // MARK: 清空某域名全部 cookie（逐条删除，全部完成后刷新一次）
    private func clear(domain: String) {
        let cookies = groups[domain] ?? []
        guard !cookies.isEmpty else { return }
        let group = DispatchGroup()
        for c in cookies {
            group.enter()
            cookieStore.delete(c) { group.leave() }
        }
        group.notify(queue: .main) {
            Task { @MainActor in
                vm.showToast("已清空 \(domain) 的 Cookie", symbol: "trash")
                reload()
            }
        }
    }
}

// HTTPCookie 不是 Identifiable，且无稳定 id；用关键字段拼出唯一标识供 ForEach 使用。
private extension HTTPCookie {
    var cookieID: String { "\(domain)|\(path)|\(name)" }
}
