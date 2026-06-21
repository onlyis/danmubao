import SwiftUI

/// 漫画看图模式：纵向长图连续阅读、单页/双页切换、方向适配、缩放拖动。
struct ComicReaderView: View {
    @Environment(\.dismiss) private var dismiss

    enum Mode { case vertical, single, dual }
    @State private var mode: Mode = .vertical
    @State private var showChrome = true
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var page = 1

    private let pageCount = 12
    private let palette: [Color] = [0x2C3E50, 0x34495E, 0x46607A, 0x3A5068, 0x2E4055].map { Color(hex: $0) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            content
                .scaleEffect(zoom)
                .gesture(
                    MagnificationGesture()
                        .onChanged { v in zoom = min(max(lastZoom * v, 1), 4) }
                        .onEnded { _ in lastZoom = zoom }
                )

            if showChrome { chrome }
        }
        .navigationBarHidden(true)
        .statusBarHidden(!showChrome)
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() } }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .vertical:
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(0..<pageCount, id: \.self) { i in comicPage(i, height: 520) }
                }
            }
        case .single:
            TabView(selection: $page) {
                ForEach(0..<pageCount, id: \.self) { i in
                    comicPage(i, height: nil).tag(i + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        case .dual:
            TabView(selection: $page) {
                ForEach(0..<(pageCount / 2), id: \.self) { i in
                    HStack(spacing: 2) {
                        comicPage(i * 2, height: nil)
                        comicPage(i * 2 + 1, height: nil)
                    }.tag(i + 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    private func comicPage(_ i: Int, height: CGFloat?) -> some View {
        LinearGradient(colors: [palette[i % palette.count], palette[i % palette.count].opacity(0.7)],
                       startPoint: .top, endPoint: .bottom)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .frame(maxHeight: height == nil ? .infinity : nil)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo").font(.system(size: 30)).foregroundStyle(.white.opacity(0.5))
                    Text("第 \(i + 1) 页").font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                }
            }
    }

    private var chrome: some View {
        VStack {
            // 顶部
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                }
                Spacer()
                Text("漫画 · 第 \(page)/\(pageCount) 页").font(.system(size: 15, weight: .medium))
                Spacer()
                Menu {
                    Button { } label: { Label("方向：从右往左", systemImage: "arrow.left") }
                    Button { } label: { Label("方向：从左往右", systemImage: "arrow.right") }
                    Button { zoom = 1; lastZoom = 1 } label: { Label("重置缩放", systemImage: "arrow.up.left.and.arrow.down.right") }
                } label: { Image(systemName: "ellipsis").font(.system(size: 18)) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.l).padding(.vertical, Theme.Spacing.m)
            .background(.black.opacity(0.55))

            Spacer()

            // 底部：模式切换 + 进度
            VStack(spacing: Theme.Spacing.m) {
                Picker("模式", selection: $mode) {
                    Text("纵向").tag(Mode.vertical)
                    Text("单页").tag(Mode.single)
                    Text("双页").tag(Mode.dual)
                }
                .pickerStyle(.segmented)
                .colorScheme(.dark)

                HStack(spacing: Theme.Spacing.m) {
                    Text("1").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    Slider(value: Binding(get: { Double(page) }, set: { page = Int($0) }), in: 1...Double(pageCount), step: 1)
                        .tint(.white)
                    Text("\(pageCount)").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, Theme.Spacing.l).padding(.vertical, Theme.Spacing.m)
            .background(.black.opacity(0.55))
        }
        .transition(.opacity)
    }
}
