import SwiftUI
import PhotosUI
import CoreImage

/// 二维码扫描：真实相机预览 + 中央扫描框 + 底部相册识别/手电筒。
struct QRScannerView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var torch = false
    @State private var cameraUnavailable = false
    @State private var result: String?
    @State private var showPhotoPicker = false
    /// 相册里未识别到二维码的提示
    @State private var noCodeFound = false

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
                    scanButton("相册识别", "photo.on.rectangle") { showPhotoPicker = true }
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
        // 相册选图识别
        .sheet(isPresented: $showPhotoPicker) {
            QRPhotoPicker { image in
                if let code = QRCode.decode(from: image) {
                    result = code
                } else {
                    noCodeFound = true
                }
            }
            .ignoresSafeArea()
        }
        .alert("扫描结果", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            if let r = result, r.hasPrefix("http") {
                Button("打开") { vm.open(url: r); dismiss() }
            }
            Button("复制") { UIPasteboard.general.string = result; dismiss() }
            Button("取消", role: .cancel) { result = nil }
        } message: { Text(result ?? "") }
        .alert("未识别到二维码", isPresented: $noCodeFound) {
            Button("好", role: .cancel) {}
        } message: { Text("所选图片中未发现可识别的二维码，请换一张试试。") }
        // 从菜单「识别图中码」进入时自动弹出相册
        .onAppear {
            if vm.qrAutoPickPhoto {
                vm.qrAutoPickPhoto = false
                showPhotoPicker = true
            }
        }
    }

    private func scanButton(_ t: String, _ s: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

// MARK: - 相册选图（PHPicker 包装）
/// 单选一张图片用于二维码识别。回调始终回到主线程。
struct QRPhotoPicker: UIViewControllerRepresentable {
    /// 选中后回调 UIImage；用户取消则不回调。
    var onPicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: (UIImage) -> Void
        init(onPicked: @escaping (UIImage) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [onPicked] object, _ in
                guard let image = object as? UIImage else { return }
                Task { @MainActor in onPicked(image) }
            }
        }
    }
}
