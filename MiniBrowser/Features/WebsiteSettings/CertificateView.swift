import SwiftUI
import Security

/// 站点 TLS 证书信息：从 WKWebView 在 `didReceive challenge` 缓存的 SecTrust 解析得到。
/// 字段均为可选 / 空串友好，无法解析时上层会提示「无证书信息」。
struct CertificateInfo: Identifiable {
    let id = UUID()
    let host: String                 // 关联站点（当前页 host）
    let subjectSummary: String       // 证书主体摘要（CN 或整体摘要）
    let issuerSummary: String        // 颁发者摘要
    let notBefore: Date?             // 有效期起
    let notAfter: Date?             // 有效期止
    let serialNumber: String         // 序列号（十六进制）
    let chainLength: Int             // 证书链长度

    /// 是否在有效期内（缺失日期时按未知 → 不标记过期）。
    var isCurrentlyValid: Bool {
        let now = Date()
        if let nb = notBefore, now < nb { return false }
        if let na = notAfter, now > na { return false }
        return true
    }
}

/// 站点证书详情视图。通过 sheet 呈现，纯只读展示，不做信任决策。
struct CertificateView: View {
    @Environment(\.dismiss) private var dismiss
    let info: CertificateInfo

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "未知" }
        return Self.dateFormatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            List {
                // 站点头部 + 有效性
                Section {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: info.isCurrentlyValid ? "lock.shield.fill" : "exclamationmark.shield.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(info.isCurrentlyValid ? Theme.Colors.safe : Theme.Colors.danger)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(info.host.isEmpty ? "当前站点" : info.host)
                                .font(.system(size: 16, weight: .semibold)).lineLimit(1)
                            Text(info.isCurrentlyValid ? "证书当前有效" : "证书已过期或尚未生效")
                                .font(.system(size: 12))
                                .foregroundStyle(info.isCurrentlyValid ? Theme.Colors.safe : Theme.Colors.danger)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("主体") {
                    detailRow("通用名称 / 主体", info.subjectSummary)
                }

                Section("颁发者") {
                    detailRow("颁发机构", info.issuerSummary)
                }

                Section("有效期") {
                    detailRow("生效时间", dateText(info.notBefore))
                    detailRow("失效时间", dateText(info.notAfter))
                }

                Section("详情") {
                    detailRow("序列号", info.serialNumber.isEmpty ? "未知" : info.serialNumber)
                    detailRow("证书链长度", "\(info.chainLength)")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("站点证书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    /// 标题在上、值可换行在下的只读行。
    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.primaryText)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}
