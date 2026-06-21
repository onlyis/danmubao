import SwiftUI

/// 二维码扫描：真实相机预览 + 中央扫描框 + 底部相册识别/手电筒。
struct QRScannerView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var torch = false
    @State private var cameraUnavailable = false
    @State private var result: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 真实相机预览
            CodeScannerView(torchOn: torch,
                            onFound: { code in if result == nil { result = code } },
                            onUnavailable: { cameraUnavailable = true })
                .ignoresSafeArea()

            if cameraUnavailable {
                LinearGradient(colors: [Color(hex: 0x1C1C28), Color(hex: 0x2A2A38)],
                               startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            }

            VStack {
                Spacer()
                // 扫描框
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                        .frame(width: 240, height: 240)
                    ScanCorners().frame(width: 240, height: 240)
                    Rectangle().fill(Theme.Colors.safe).frame(width: 220, height: 2)
                        .shadow(color: Theme.Colors.safe, radius: 6).offset(y: -60)
                }
                Text(cameraUnavailable ? "当前设备无可用相机" : "将二维码放入框内，自动扫描")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
                    .padding(.top, Theme.Spacing.l)
                Spacer()

                HStack(spacing: 80) {
                    scanButton("相册识别", "photo.on.rectangle")
                    Button { torch.toggle() } label: {
                        VStack(spacing: 6) {
                            Image(systemName: torch ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.system(size: 22)).foregroundStyle(torch ? .yellow : .white)
                                .frame(width: 56, height: 56).background(Circle().fill(.white.opacity(0.12)))
                            Text("手电筒").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .navigationTitle("扫一扫").navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() }.foregroundStyle(.white) } }
        .alert("扫描结果", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            if let r = result, r.hasPrefix("http") {
                Button("打开") { vm.open(url: r); dismiss() }
            }
            Button("复制") { UIPasteboard.general.string = result; dismiss() }
            Button("取消", role: .cancel) { result = nil }
        } message: { Text(result ?? "") }
    }

    private func scanButton(_ t: String, _ s: String) -> some View {
        Button { } label: {
            VStack(spacing: 6) {
                Image(systemName: s).font(.system(size: 22)).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(Circle().fill(.white.opacity(0.12)))
                Text(t).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

/// 扫描框四角
private struct ScanCorners: View {
    var body: some View {
        GeometryReader { geo in
            let len: CGFloat = 26, w: CGFloat = 3
            let W = geo.size.width, H = geo.size.height
            ForEach(0..<4, id: \.self) { i in
                let isRight = i % 2 == 1
                let isBottom = i >= 2
                Path { p in
                    let x = isRight ? W : 0
                    let y = isBottom ? H : 0
                    p.move(to: CGPoint(x: x, y: isBottom ? y - len : y + len))
                    p.addLine(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: isRight ? x - len : x + len, y: y))
                }
                .stroke(Theme.Colors.safe, style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
        }
    }
}
