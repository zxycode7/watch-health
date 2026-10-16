import SwiftUI

struct ContentView: View {
    @ObservedObject var model: SyncModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPairing = false
    @State private var pairingText = ""
    @State private var historyDays = 90

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BridgeTheme.spacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("健康桥").font(BridgeTheme.title)
                        Text("Apple 健康 → 你的 Mac").foregroundStyle(.secondary)
                    }.padding(.top, 12)

                    BridgeCard {
                        HStack(spacing: 16) {
                            Image(systemName: "iphone").font(.title)
                            Image(systemName: model.connection == nil ? "link.badge.plus" : "link").foregroundStyle(BridgeTheme.accent)
                            Image(systemName: "desktopcomputer").font(.title)
                            Spacer()
                            Text(model.connection == nil ? "待配对" : "已配对").font(.subheadline.weight(.semibold))
                        }.accessibilityElement(children: .combine)
                        if let connection = model.connection {
                            Text(connection.endpoint.host ?? "你的 Mac").font(BridgeTheme.utility).textSelection(.enabled)
                        } else {
                            Text("在 Mac 上生成配对码，用系统相机扫码，或粘贴配对链接。")
                                .foregroundStyle(.secondary)
                        }
                        Button(model.connection == nil ? "配对 Mac" : "更换 Mac") { showingPairing = true }
                            .buttonStyle(.bordered).disabled(model.isSyncing || model.isAuthorizing)
                    }

                    BridgeCard {
                        Label(model.isSyncing ? "同步中" : "同步状态", systemImage: model.isSyncing ? "arrow.triangle.2.circlepath" : "tray.and.arrow.up")
                            .font(.headline)
                        HStack(alignment: .top) {
                            if model.isSyncing { ProgressView().accessibilityLabel("正在同步") }
                            Text(model.message).foregroundStyle(model.isError ? Color.red : Color.primary)
                                .accessibilityLabel(model.isError ? "同步错误：\(model.message)" : model.message)
                        }.frame(minHeight: 48, alignment: .top)
                        if let last = model.lastSync {
                            LabeledContent("上次完成", value: last.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if model.isSyncing {
                            Text("已发送 \(model.transferred) 条变更").font(BridgeTheme.utility).monospacedDigit()
                        }
                        Button {
                            Task {
                                if model.authorizationConfigured { await model.sync() }
                                else { await model.authorizeAndSync() }
                            }
                        } label: {
                            Text(model.authorizationConfigured ? "立即同步" : "授权并同步")
                                .frame(maxWidth: .infinity).frame(height: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.connection == nil || model.isSyncing || model.isAuthorizing || model.paused || model.selected.isEmpty)
                        Toggle("暂停同步", isOn: Binding(get: { model.paused }, set: { model.setPaused($0) }))
                            .disabled(model.isSyncing || model.isAuthorizing)
                    }

                    BridgeCard {
                        Text("同步哪些数据").font(.headline)
                        ForEach(HealthMetric.allCases) { metric in
                            Toggle(metric.title, isOn: Binding(get: { model.selected.contains(metric) },
                                set: { model.select(metric, enabled: $0) }))
                        }.disabled(model.isSyncing || model.isAuthorizing)
                        Text("只请求读取权限。关闭某项会停止后续同步，Mac 上的已有数据保留。实际可读项目由 Apple 健康中的授权决定。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    BridgeCard {
                        Text("补录历史").font(.headline)
                        Picker("补录范围", selection: $historyDays) {
                            Text("最近 30 天").tag(30)
                            Text("最近 90 天").tag(90)
                            Text("最近一年").tag(365)
                            Text("全部历史").tag(0)
                        }.pickerStyle(.menu)
                        Button("补录并合并") { Task { await model.backfill(days: historyDays) } }
                            .disabled(model.isSyncing || !model.authorizationConfigured || model.connection == nil || model.paused)
                        Text("首次同步最近 30 天。补录会合并已有记录，较长历史建议保持 App 打开。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("数据仅发送到你配对的 Mac。自动同步需要 Mac 服务在线、手机可读取健康数据，运行时机由 iOS 决定。时间显示为北京时间。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(BridgeTheme.spacing)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingPairing) { pairingSheet }
        }
        .tint(BridgeTheme.accent)
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
        .onOpenURL { url in pairingText = url.absoluteString; showingPairing = true }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.resume() } }
        }
    }

    private var pairingSheet: some View {
        NavigationStack {
            Form {
                Section("Mac 配对链接") {
                    SecureField("粘贴 watchbridge:// 开头的链接", text: $pairingText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Mac 配对链接，包含一次性配对码")
                    PasteButton(payloadType: String.self) { strings in pairingText = strings.first ?? "" }
                    if let link = try? PairingLink(pairingText) {
                        LabeledContent("将连接", value: link.endpoint.host ?? "Mac")
                        Text("证书指纹：\(link.fingerprint.prefix(12))…\(link.fingerprint.suffix(12))")
                            .font(BridgeTheme.utility).textSelection(.enabled)
                    }
                }
                Section {
                    Button {
                        Task {
                            await model.pair(pairingText)
                            if !model.isError { pairingText = ""; showingPairing = false }
                        }
                    } label: {
                        HStack {
                            Text("确认配对")
                            Spacer()
                            if model.isPairing { ProgressView() }
                        }.frame(minHeight: 32)
                    }.disabled(model.isPairing || (try? PairingLink(pairingText)) == nil)
                    if model.isError { Text(model.message).foregroundStyle(.red) }
                } footer: {
                    Text("只使用你自己 Mac 生成的链接。配对码 5 分钟内有效，只能使用一次。确认后，所选健康数据会发送到这台 Mac。")
                }
            }
            .navigationTitle("配对 Mac").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("取消") { pairingText = ""; showingPairing = false }.disabled(model.isPairing)
            } }
            .interactiveDismissDisabled(model.isPairing)
        }
    }
}
