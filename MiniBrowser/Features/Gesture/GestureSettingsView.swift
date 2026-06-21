import SwiftUI

/// 手势配置页：启用开关 + 规则列表（手势 → 功能），可增删改。
struct GestureSettingsView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: GestureRule?
    @State private var addingNew = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: $vm.gesture.enabled) {
                    Label("启用手势按钮", systemImage: "hand.draw.fill")
                }
            } footer: {
                Text("按住右下角悬浮按钮拖出笔画即可触发；长按可移动按钮，轻点打开本页。")
            }

            if vm.gesture.enabled {
                Section {
                    Picker(selection: $vm.gesture.placement) {
                        ForEach(GesturePlacement.allCases) { Text($0.rawValue).tag($0) }
                    } label: {
                        Label("放置方式", systemImage: "square.grid.2x2")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("放置方式")
                } footer: {
                    Text(vm.gesture.placement == .floating
                         ? "悬浮按钮可拖动；拖到屏幕左右边缘会贴边停靠，只露出一部分。"
                         : "固定在底部工具栏上方居中，像一个图标。")
                }

                Section("手势控制") {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Label("直线容差", systemImage: "scribble.variable")
                            Spacer()
                            Text(straightnessText).font(.system(size: 13)).foregroundStyle(Theme.Colors.secondaryText)
                        }
                        Slider(value: $vm.gesture.straightness, in: 0...1, step: 0.1)
                        Text("越大，画得弯一点的线也会被识别成一条直线，不易被拆成多段。")
                            .font(.system(size: 12)).foregroundStyle(Theme.Colors.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Label("按钮大小", systemImage: "circle.circle")
                            Spacer()
                            Text("\(Int(vm.gesture.buttonSize * 100))%").font(.system(size: 13)).foregroundStyle(Theme.Colors.secondaryText)
                        }
                        Slider(value: $vm.gesture.buttonSize, in: 0.8...1.4, step: 0.1)
                    }
                    Toggle(isOn: $vm.gesture.enableCircle) { Label("识别圆形手势 ↻ ↺", systemImage: "circle.dashed") }
                    Toggle(isOn: $vm.gesture.haptics) { Label("触觉反馈", systemImage: "waveform") }
                }
            }

            Section("手势规则") {
                ForEach(vm.gesture.rules) { rule in
                    Button { editing = rule } label: { RuleRow(rule: rule) }
                        .swipeActions {
                            Button(role: .destructive) { remove(rule) } label: { Label("删除", systemImage: "trash") }
                        }
                }
            }

            Section {
                Button { addingNew = true } label: {
                    Label("添加手势", systemImage: "plus.circle")
                }
                Button(role: .destructive) { vm.gesture.rules = GestureRule.defaults } label: {
                    Label("恢复默认手势", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("手势按钮").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } } }
        .sheet(item: $editing) { rule in
            GestureRuleEditView(rule: rule) { updated in update(updated) }
        }
        .sheet(isPresented: $addingNew) {
            GestureRuleEditView(rule: GestureRule(directions: [], action: .newTab)) { created in
                if !created.directions.isEmpty { vm.gesture.rules.append(created) }
            }
        }
    }

    private var straightnessText: String {
        switch vm.gesture.straightness {
        case ..<0.34: return "精确"
        case ..<0.67: return "标准"
        default: return "宽松"
        }
    }

    private func remove(_ rule: GestureRule) { vm.gesture.rules.removeAll { $0.id == rule.id } }
    private func update(_ rule: GestureRule) {
        if let i = vm.gesture.rules.firstIndex(where: { $0.id == rule.id }) { vm.gesture.rules[i] = rule }
    }
}

private struct RuleRow: View {
    @EnvironmentObject var vm: BrowserViewModel
    let rule: GestureRule
    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(rule.directions.glyphs.isEmpty ? "—" : rule.directions.glyphs)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 70, alignment: .leading)
            Image(systemName: "arrow.right").font(.system(size: 12)).foregroundStyle(Theme.Colors.tertiaryText)
            Label(rule.action.title, systemImage: rule.action.symbol)
                .font(.system(size: 15)).foregroundStyle(Theme.Colors.primaryText)
            Spacer()
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { v in if let i = vm.gesture.rules.firstIndex(where: { $0.id == rule.id }) { vm.gesture.rules[i].enabled = v } }
            )).labelsHidden()
        }
    }
}

/// 规则编辑：绘制录制手势 + 选择功能。
struct GestureRuleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: GestureRule
    var onSave: (GestureRule) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("绘制手势") {
                    DrawPad(directions: $rule.directions)
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                    HStack {
                        Text("当前：").foregroundStyle(Theme.Colors.secondaryText)
                        Text(rule.directions.glyphs.isEmpty ? "未录制" : rule.directions.glyphs)
                            .font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.Colors.accent)
                        Spacer()
                        Button("清除") { rule.directions = [] }.font(.system(size: 14))
                    }
                }

                Section("手动微调") {
                    LazyVGrid(columns: Array(repeating: GridItem(), count: 4), spacing: 10) {
                        ForEach(GestureDirection.allCases, id: \.self) { dir in
                            Button { rule.directions.append(dir) } label: {
                                Text(dir.glyph).font(.system(size: 20, weight: .bold))
                                    .frame(maxWidth: .infinity).frame(height: 40)
                                    .background(Theme.Colors.groupedBackground, in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(Theme.Colors.primaryText)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("触发功能") {
                    Picker("功能", selection: $rule.action) {
                        ForEach(GestureAction.allCases) { a in
                            Label(a.title, systemImage: a.symbol).tag(a)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .navigationTitle("编辑手势").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { onSave(rule); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(rule.directions.isEmpty)
                }
            }
        }
    }
}

/// 绘制板：拖动绘制，实时识别为方向序列。
private struct DrawPad: View {
    @Binding var directions: [GestureDirection]
    @State private var points: [CGPoint] = []

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0).fill(Theme.Colors.groupedBackground)
            if points.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "hand.draw").font(.system(size: 30)).foregroundStyle(Theme.Colors.tertiaryText)
                    Text("在此拖动绘制手势").font(.system(size: 13)).foregroundStyle(Theme.Colors.tertiaryText)
                }
            }
            Canvas { ctx, _ in
                guard points.count > 1 else { return }
                var path = Path(); path.move(to: points[0])
                for p in points.dropFirst() { path.addLine(to: p) }
                ctx.stroke(path, with: .color(Theme.Colors.accent),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if !directions.isEmpty {
                Text(directions.glyphs).font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent.opacity(0.35))
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if points.isEmpty { points = [v.startLocation] }
                    points.append(v.location)
                    directions = GestureRecognizer.recognize(points)
                }
                .onEnded { _ in points = [] }
        )
    }
}
