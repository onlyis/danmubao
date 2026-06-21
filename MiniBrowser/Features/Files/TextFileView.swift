import SwiftUI

/// 让 URL 可直接用于 `.sheet(item:)`（以路径作为标识）。
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// 文件「以纯文本打开 / 编辑保存」：读取文本文件内容显示，可编辑并写回原文件。
/// 支持 txt/html/json/log 等纯文本类型；大文件（> 2MB）只提示不读取，避免卡顿/爆内存。
struct TextFileView: View {
    /// 目标文件的真实磁盘地址。
    let url: URL
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    /// 单次读取上限：超过则拒绝以纯文本打开。
    private static let maxBytes = 2 * 1024 * 1024

    @State private var text: String = ""
    /// 载入时的原始内容，用于判断是否有未保存改动。
    @State private var original: String = ""
    @State private var loadError: String?
    @State private var tooLarge = false
    @State private var saveError: String?
    @State private var isLoaded = false

    private var isDirty: Bool { isLoaded && text != original }

    var body: some View {
        NavigationStack {
            Group {
                if tooLarge {
                    notice(symbol: "exclamationmark.triangle.fill",
                           color: Theme.Colors.danger,
                           text: "文件过大（超过 2 MB），无法以纯文本打开。")
                } else if let loadError {
                    notice(symbol: "xmark.octagon.fill",
                           color: Theme.Colors.danger,
                           text: loadError)
                } else {
                    TextEditor(text: $text)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Theme.Colors.primaryText)
                        .padding(.horizontal, Theme.Spacing.s)
                        .scrollContentBackground(.hidden)
                        .background(Theme.Colors.background)
                        .disabled(!isLoaded)
                }
            }
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isDirty)
                }
            }
            .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("好", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "") }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder
    private func notice(symbol: String, color: Color, text: String) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(color)
            Text(text).font(.system(size: 15)).foregroundStyle(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center).padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 读取文件：先查体积，再按 UTF-8（失败回退系统编码）解码。
    private func load() {
        guard !isLoaded, !tooLarge, loadError == nil else { return }
        let fm = FileManager.default
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Self.maxBytes else { tooLarge = true; return }
        guard fm.fileExists(atPath: url.path) else {
            loadError = "文件不存在：\(url.lastPathComponent)"
            return
        }
        do {
            let data = try Data(contentsOf: url)
            // 优先 UTF-8；非 UTF-8 文本回退到系统默认编码，仍失败则按非纯文本拒绝。
            guard let decoded = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
                loadError = "无法以纯文本解码该文件（可能为二进制文件）。"
                return
            }
            text = decoded
            original = decoded
            isLoaded = true
        } catch {
            loadError = "读取失败：\(error.localizedDescription)"
        }
    }

    /// 写回原文件（UTF-8 Data 原子写入）。
    private func save() {
        guard isLoaded else { return }
        guard let data = text.data(using: .utf8) else {
            saveError = "无法编码为 UTF-8 文本。"
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            original = text
            vm.showToast("已保存", symbol: "checkmark.circle.fill")
            dismiss()
        } catch {
            saveError = "写入失败：\(error.localizedDescription)"
        }
    }
}
