import SwiftUI
import Charts

struct ContentView: View {
    @ObservedObject var model: SyncModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var pairingPresentation: PairingPresentation?
    @State private var tab = 0
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { OverviewView(model: model, pair: showPairing) }
                .tabItem { Label("概览", systemImage: "circle.hexagongrid") }.tag(0)
            NavigationStack { PhoneDataView(model: model) }
                .tabItem { Label("数据", systemImage: "chart.xyaxis.line") }.tag(1)
            NavigationStack { PhoneSettingsView(model: model, pair: showPairing) }
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }.tag(2)
        }
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .tint(BridgeTheme.accent)
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
        .sheet(item: $pairingPresentation) { PairingSheet(model: model, initialText: $0.text) }
        .onOpenURL { pairingPresentation = PairingPresentation(text: $0.absoluteString) }
        .task {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "--pairing-link"), arguments.indices.contains(index + 1) {
                pairingPresentation = PairingPresentation(text: arguments[index + 1])
            } else if arguments.contains("--request-health-access"), model.connection != nil { await model.authorizeAndSync() }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.resume() } }
        }
    }
    private func showPairing() { pairingPresentation = PairingPresentation(text: "") }
}

private struct PairingPresentation: Identifiable { let id = UUID(); let text: String }

private struct OverviewView: View {
    @ObservedObject var model: SyncModel
    let pair: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    BrandMark()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("维律").font(.title2.bold())
                        Text("VEYRA · 你的身体，自有脉络").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.top, 8)
                VStack(alignment: .leading, spacing: 22) {
                    Label("个人数据空间", systemImage: "point.3.connected.trianglepath.dotted").font(.subheadline)
                    Text(model.connection == nil ? "把每一次记录，\n留在自己手中。" : "你的节律，\n正在这里汇合。")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Label("Apple Watch", systemImage: "applewatch")
                        Image(systemName: "chevron.right").font(.caption2)
                        Text("iPhone")
                        Image(systemName: "chevron.right").font(.caption2)
                        Text("Mac")
                    }.font(.caption).foregroundStyle(.white.opacity(0.85)).accessibilityElement(children: .combine)
                    Divider().overlay(.white.opacity(0.2))
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("同步范围").font(.caption).foregroundStyle(.white.opacity(0.7))
                            Text("\(model.selected.count) 项").font(.title3.weight(.semibold)).monospacedDigit()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Text("上次完成").font(.caption).foregroundStyle(.white.opacity(0.7))
                            Text(model.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "尚未同步").font(.subheadline.weight(.medium))
                        }
                    }
                }.foregroundStyle(.white).padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BridgeTheme.ink, in: RoundedRectangle(cornerRadius: 28))
                BridgeCard {
                    HStack {
                        Label(model.paused ? "已暂停" : model.isSyncing ? "同步中" : "同步状态", systemImage: model.isError ? "exclamationmark.circle" : "arrow.triangle.2.circlepath")
                            .font(.headline)
                        Spacer()
                        if model.busy { ProgressView().accessibilityLabel("正在处理") }
                    }
                    Text(model.message).foregroundStyle(model.isError ? BridgeTheme.danger : Color.primary).frame(minHeight: 44, alignment: .top)
                        .accessibilityIdentifier("sync.status")
                    if model.isSyncing {
                        Text("已完成 \(model.completedMetrics.count)/\(model.selected.count) 项 · \(model.transferred) 条变更")
                            .font(BridgeTheme.utility).foregroundStyle(.secondary).monospacedDigit()
                        Button(model.stopRequested ? "正在保存进度…" : "停止本次同步") { model.requestStop() }
                            .disabled(model.stopRequested).buttonStyle(.bordered)
                    } else {
                        Button(action: syncAction) {
                            Text(actionTitle).frame(maxWidth: .infinity).padding(.vertical, 9)
                        }.buttonStyle(.borderedProminent).tint(BridgeTheme.actionFill).disabled(model.busy || model.paused || model.selected.isEmpty)
                            .accessibilityIdentifier("sync.primary")
                        if model.paused { Text("在设置中恢复同步后即可继续。").font(.footnote).foregroundStyle(.secondary) }
                        if model.selected.isEmpty { Text("请先在设置中选择至少一项数据。").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                BridgeCard {
                    HStack {
                        Label("你的 Mac", systemImage: "desktopcomputer").font(.headline)
                        Spacer()
                        Text(model.connection == nil ? "待配对" : "已配对").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Text(model.connection?.endpoint.host ?? "先配对，再选择健康读取权限。")
                        .font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    Button(model.connection == nil ? "配对 Mac" : "更换 Mac", action: pair).disabled(model.busy)
                }
                Text("同步到你的 Mac。记录保留来源，空数据不会被当成零。")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
            }.padding(20)
        }
        .background(BridgeTheme.background).toolbar(.hidden, for: .navigationBar)
    }
    private var actionTitle: String {
        model.connection == nil ? "配对 Mac" : model.authorizationConfigured ? "立即同步" : "授权并同步"
    }
    private func syncAction() {
        if model.connection == nil { pair(); return }
        Task {
            if model.authorizationConfigured { await model.sync(); await model.refreshPreviews() }
            else { await model.authorizeAndSync() }
        }
    }
}

private struct PhoneDataView: View {
    @ObservedObject var model: SyncModel
    var body: some View {
        List {
            Section {
                Text("直接读取此 iPhone 的健康记录。这里显示最近样本，Mac 中的入库记录以 Mac 客户端为准。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !model.authorizationConfigured {
                ContentUnavailableView("先完成健康授权", systemImage: "heart.text.clipboard", description: Text("在概览中点“授权并同步”，选择你愿意读取的项目。"))
            } else if model.selected.isEmpty {
                ContentUnavailableView("还未选择数据", systemImage: "checklist", description: Text("前往设置选择需要同步的项目。"))
            } else {
                ForEach(HealthMetric.groups, id: \.self) { group in
                    let metrics = HealthMetric.allCases.filter { $0.group == group && model.selected.contains($0) }
                    if !metrics.isEmpty {
                        Section(group) {
                            ForEach(metrics) { metric in
                                NavigationLink { PhoneMetricDetail(metric: metric, records: model.previews[metric] ?? [], error: model.previewErrors[metric]) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: metric.symbol).foregroundStyle(BridgeTheme.accent).frame(width: 26)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(metric.title)
                                            Text(model.previewErrors[metric] ?? (model.previews[metric]?.first?.start.bridgeDate?.formatted(date: .abbreviated, time: .shortened) ?? "尚无可读样本"))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if let value = model.previews[metric]?.first?.value {
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text(metric.displayValue(value)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                                Text(metric.displayUnit).font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                    }.padding(.vertical, 5)
                                }
                            }
                        }
                    }
                }
            }
            Section { Text("没有记录可能表示尚未授权、设备未生成或尚未同步。维律无法据此判定具体的读取权限。")
                .font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("数据")
        .overlay { if model.isRefreshing && model.previews.isEmpty { ProgressView("正在读取健康记录") } }
        .task { await model.refreshPreviews() }
        .refreshable { await model.refreshPreviews() }
        .toolbar { Button { Task { await model.refreshPreviews() } } label: { Image(systemName: "arrow.clockwise") }
            .accessibilityLabel("刷新健康记录").disabled(model.isRefreshing) }
    }
}

private struct PhoneMetricDetail: View {
    let metric: HealthMetric
    let records: [HealthRecord]
    let error: String?
    var body: some View {
        List {
            Section { Text(metric.explanation).font(.subheadline).foregroundStyle(.secondary) }
            if let error { Section { Label(error, systemImage: "exclamationmark.circle") } }
            if !records.isEmpty {
                Section(metric.isInterval ? "最近记录区间" : "最近原始采样") {
                    Chart(records, id: \.id) { record in
                        if metric.isInterval {
                            RectangleMark(xStart: .value("开始", record.start.bridgeDate ?? .distantPast), xEnd: .value("结束", record.end.bridgeDate ?? .distantPast), y: .value("来源", record.source_name))
                                .foregroundStyle(by: .value("来源", record.source_name)).opacity(0.7)
                        } else {
                            PointMark(x: .value("时间", record.start.bridgeDate ?? .distantPast), y: .value(metric.displayUnit, record.value))
                                .foregroundStyle(by: .value("来源", record.source_name)).symbolSize(25)
                        }
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.hour().minute()) } }
                    .frame(height: 180)
                    if let first = records.last?.start.bridgeDate, let last = records.first?.start.bridgeDate {
                        Text(first.formatted(date: .abbreviated, time: .shortened) + " → " + last.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("只展示最近样本，保留独立来源，未作跨来源累加。").font(.caption).foregroundStyle(.secondary)
                }
            }
            if records.isEmpty { ContentUnavailableView("没有可读记录", systemImage: metric.symbol, description: Text("检查健康 App 中是否已有记录，以及是否向维律开放了读取权限。")) }
            Section("最近 \(records.count) 条原始记录") {
                ForEach(records, id: \.id) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(metric.displayValue(record.value)).font(.title3.weight(.semibold)).monospacedDigit()
                            Text(metric.displayUnit).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(record.start.bridgeDate?.formatted(date: .abbreviated, time: .shortened) ?? record.start).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(record.source_name + (record.device_model.isEmpty ? "" : " · " + record.device_model)).font(.caption).foregroundStyle(.secondary)
                        if metric.isInterval { Text("结束：" + (record.end.bridgeDate?.formatted(date: .abbreviated, time: .shortened) ?? record.end)).font(.caption).foregroundStyle(.secondary) }
                        DisclosureGroup("来源与原始信息") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.source_bundle)
                                Text("UUID：\(record.id)")
                                if let product = record.metadata.source_product_type { Text("设备代号：\(product)") }
                                if let os = record.metadata.source_os { Text("来源系统：\(os)") }
                                if let version = record.metadata.source_version { Text("来源版本：\(version)") }
                            }.font(.caption.monospaced()).textSelection(.enabled)
                        }.font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
        }.navigationTitle(metric.title).navigationBarTitleDisplayMode(.inline)
    }
}

private struct PhoneSettingsView: View {
    @ObservedObject var model: SyncModel
    let pair: () -> Void
    @AppStorage("appearance") private var appearance = "system"
    @State private var historyDays = 90
    @State private var confirmHistory = false
    var body: some View {
        Form {
            Section("连接与同步") {
                LabeledContent("Mac", value: model.connection?.endpoint.host ?? "尚未配对")
                Button(model.connection == nil ? "配对 Mac" : "更换 Mac", action: pair).disabled(model.busy)
                Toggle("暂停同步", isOn: Binding(get: { model.paused }, set: { model.setPaused($0) })).disabled(model.busy)
            }
            Section {
                Text("\(model.selected.count) / \(HealthMetric.allCases.count) 项已选择。新增项目默认关闭，选择后需重新确认健康读取权限。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("同步范围") }
            ForEach(HealthMetric.groups, id: \.self) { group in
                Section(group) {
                    ForEach(HealthMetric.allCases.filter { $0.group == group }) { metric in
                        Toggle(isOn: Binding(get: { model.selected.contains(metric) }, set: { model.select(metric, enabled: $0) })) {
                            Label(metric.title, systemImage: metric.symbol)
                        }.disabled(model.busy || !model.supports(metric))
                    }
                }
            }
            Section {
                Picker("补录范围", selection: $historyDays) {
                    Text("最近 30 天").tag(30); Text("最近 90 天").tag(90); Text("最近一年").tag(365); Text("全部历史").tag(0)
                }.disabled(model.busy)
                Button("补录并合并") { confirmHistory = true }
                    .disabled(model.busy || !model.authorizationConfigured || model.connection == nil || model.paused || model.selected.isEmpty)
                Text("重新读取所选范围，以 UUID 合并。已有记录不会重复计入；较长历史建议保持 App 打开。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("补录历史") }
            Section("外观") {
                Picker("显示模式", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
            }
            Section("了解数据") {
                NavigationLink("数据能力与边界") { CapabilityView() }
                Link("打开 Apple 健康", destination: URL(string: "x-apple-health://")!)
                Text("只申请读取权限。更改授权请前往 Apple 健康 → 个人资料 → App → 维律。后台时机由系统决定；保持 Mac 服务在线并处于同一网络。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                HStack { BrandMark(size: 36); VStack(alignment: .leading) { Text("维律 Veyra").font(.headline); Text("0.2 · 个人健康数据空间").font(.caption).foregroundStyle(.secondary) } }
                Text("本地存储，来源可溯。通过 AI 查询的记录会进入所用模型服务；请只向你信任的客户端开放 MCP。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("设置")
        .confirmationDialog("补录所选历史数据？", isPresented: $confirmHistory, titleVisibility: .visible) {
            Button("补录并合并") { Task { await model.backfill(days: historyDays) } }
            Button("取消", role: .cancel) {}
        } message: { Text("将重新读取当前选择的 \(model.selected.count) 项。不会删除 Mac 上的记录。") }
    }
}

private struct CapabilityView: View {
    var body: some View {
        List {
            Section("已接入 · 28 项") {
                Text("除心率、睡眠和活动外，还可读取心率恢复、最大摄氧量、步态、日照、噪声与睡眠呼吸紊乱。能否读到取决于设备、系统、已有记录和你授予的权限。")
            }
            Section("下一层 · 需要独立接入") {
                Label("逐搏心跳间隔与已有 ECG 波形", systemImage: "waveform.path.ecg")
                Text("Apple 提供读取既有序列的接口。当前版本尚未同步这些序列；不会把 SDNN 冒充为逐搏数据。")
                Label("手表实时运动传感器", systemImage: "applewatch")
                Text("需要开发 watchOS 采集端，主动会话中获取加速度、旋转等数据，并评估耗电。iPhone App 无法替代这一步。")
            }
            Section("受平台限制") {
                Text("原始光电容积波、研究级传感数据通常需要 Apple 的 SensorKit 研究授权。普通个人签名与 HealthKit 读取权限不能替代它。")
                Text("设备有传感器，不等于系统已向第三方生成或开放相应数据。地区功能也在持续变化，请以设备中的实际设置和 Apple 最新清单为准。")
                Link("查看 Apple 功能可用性", destination: URL(string: "https://www.apple.com.cn/watchos/feature-availability/")!)
            }
        }.navigationTitle("数据能力").navigationBarTitleDisplayMode(.inline)
    }
}
