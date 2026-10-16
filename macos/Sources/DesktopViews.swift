import SwiftUI
import Charts
import CoreImage.CIFilterBuiltins
import AppKit

struct DesktopRoot: View {
    @ObservedObject var model: DesktopModel
    @State private var section: String? = "overview"
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) { BrandMark(size: 42); VStack(alignment: .leading, spacing: 2) { Text("维律").font(.title2.bold()); Text("VEYRA").font(.caption.monospaced()).foregroundStyle(.secondary) } }.padding(.horizontal, 18).padding(.top, 18)
                List(selection: $section) {
                    Section("个人数据空间") {
                        Label("概览", systemImage: "circle.hexagongrid").tag("overview")
                        Label("原始记录", systemImage: "chart.xyaxis.line").tag("data")
                        Label("设备与配对", systemImage: "point.3.connected.trianglepath.dotted").tag("devices")
                    }
                    Section("本机集成") {
                        Label("MCP 控制台", systemImage: "terminal").tag("mcp")
                        Label("存储与服务", systemImage: "externaldrive").tag("storage")
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Label(model.serviceOnline ? "接收服务在线" : "接收服务离线", systemImage: model.serviceOnline ? "checkmark.circle.fill" : "pause.circle")
                        .font(.caption).foregroundStyle(model.serviceOnline ? Color.green : .secondary)
                    Text("数据保存在这台 Mac").font(.caption).foregroundStyle(.secondary)
                }.padding(18)
            }.navigationSplitViewColumnWidth(min: 210, ideal: 235)
        } detail: {
            Group {
                switch section {
                case "data": RecordExplorer(model: model)
                case "devices": DevicePanel(model: model)
                case "mcp": MCPPanel(model: model)
                case "storage": StoragePanel(model: model)
                default: DesktopOverview(model: model, explore: { section = "data" })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BridgeTheme.background)
            .toolbar {
                ToolbarItem { Button { Task { await model.refresh(); model.recordRefreshVersion += 1 } } label: { Label("刷新", systemImage: "arrow.clockwise") }.disabled(model.loading).help("刷新本机数据与服务状态").keyboardShortcut("r") }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .tint(BridgeTheme.accent)
        .frame(minWidth: 940, minHeight: 650)
        .sheet(isPresented: Binding(get: { model.pairingLink != nil }, set: { if !$0 { model.closePairing() } })) { PairingPanel(model: model) }
        .task {
            await model.refresh(); await model.checkMCP()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
                await model.refresh()
            }
        }
    }
}

private struct PanelTitle: View {
    let title: String; let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(BridgeTheme.title); Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DesktopOverview: View {
    @ObservedObject var model: DesktopModel
    let explore: () -> Void
    var total: Int { model.snapshot?.inventory.reduce(0) { $0 + $1.count } ?? 0 }
    var available: [MetricInventory] { model.snapshot?.inventory.filter { $0.count > 0 } ?? [] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PanelTitle(title: "你的节律，尽在本机。", subtitle: "个人健康记录的长期空间 · 来源清晰，连接可见")
                if let error = model.error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(BridgeTheme.danger) }
                HStack(alignment: .top, spacing: 30) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("已归档原始记录").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                        Text(total.formatted()).font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit().accessibilityIdentifier("desktop.records.total")
                        Text("\(available.count) 类已有数据 · \(model.snapshot?.sources.count ?? 0) 个来源").font(.subheadline).foregroundStyle(.white.opacity(0.8))
                        Button("浏览原始记录", action: explore).buttonStyle(.bordered).tint(.white)
                    }
                    Spacer()
                    BrandMark(size: 142)
                }.foregroundStyle(.white).padding(30).frame(maxWidth: .infinity, alignment: .leading)
                    .background(BridgeTheme.ink, in: RoundedRectangle(cornerRadius: 26))
                HStack(alignment: .top, spacing: 18) {
                    BridgeCard {
                        Label("iPhone → Mac", systemImage: "iphone.and.arrow.forward").font(.headline)
                        Text(model.serviceOnline ? "接收服务在线" : "接收服务离线").font(.title3.weight(.medium))
                        Text(model.snapshot?.devices.first(where: { !$0.revoked })?.lastSync?.bridgeDate?.formatted(date: .abbreviated, time: .shortened) ?? "尚未收到同步")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    BridgeCard {
                        Label("只读 MCP", systemImage: "terminal").font(.headline)
                        Text(model.tools.isEmpty ? "尚未检测" : "\(model.tools.count) 个查询工具").font(.title3.weight(.medium))
                        Text(model.mcpConfigured ? "已注册到 Codex" : "可在 MCP 控制台查看").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("数据目录").font(.title3.weight(.semibold))
                    if available.isEmpty {
                        ContentUnavailableView("等待第一批记录", systemImage: "tray.and.arrow.down", description: Text("在设备与配对中生成二维码，然后打开 iPhone 上的维律授权并同步。"))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 215), alignment: .leading)], alignment: .leading, spacing: 14) {
                            ForEach(available) { item in
                                BridgeCard {
                                    Label(item.metric.title, systemImage: item.metric.symbol).font(.subheadline.weight(.medium))
                                    Text(item.count.formatted() + " 条").font(.title2.weight(.semibold)).monospacedDigit()
                                    Text(item.latest?.bridgeDate?.formatted(date: .abbreviated, time: .shortened) ?? "—").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Text("条数表示原始记录的数量，不是健康评分或每日总量。不同设备的重叠记录会被保留。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(30)
        }.navigationTitle("概览")
    }
}

private struct RecordExplorer: View {
    @ObservedObject var model: DesktopModel
    @State private var metric: HealthMetric = .heart_rate
    @State private var days = 30
    @State private var source = ""
    @State private var offset = 0
    @State private var selectedID: String?
    @State private var end = Calendar.bridge.date(byAdding: .day, value: 1, to: Calendar.bridge.startOfDay(for: Date()))!
    var beginning: Date { days == 0 ? Date(timeIntervalSince1970: 0) : Calendar.bridge.date(byAdding: .day, value: -days, to: end)! }
    var queryKey: String { "\(metric.rawValue)|\(days)|\(source)|\(offset)" }
    var selected: DesktopRecord? { model.page.rows.first { $0.id == selectedID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PanelTitle(title: "原始记录", subtitle: "筛选来源与时间，查看每条记录的值、时间及设备。")
            HStack(spacing: 16) {
                Picker("指标", selection: $metric) { ForEach(HealthMetric.allCases) { Text($0.title).tag($0) } }.frame(maxWidth: 240)
                Picker("范围", selection: $days) { Text("最近 7 天").tag(7); Text("最近 30 天").tag(30); Text("最近 90 天").tag(90); Text("最近一年").tag(365); Text("全部历史").tag(0) }.frame(maxWidth: 210)
                Picker("来源", selection: $source) { Text("全部来源").tag(""); ForEach(model.snapshot?.sources ?? []) { Text($0.name).tag($0.bundle) } }.frame(maxWidth: 260)
            }.controlSize(.regular)
            if let error = model.pageError { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(BridgeTheme.danger) }
            chart
            HStack {
                Text("\(model.page.total.formatted()) 条符合条件 · 当前页按时间从新到旧").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.loadingPage { ProgressView().controlSize(.small) }
                Button("上一页") { offset = max(0,offset - 100) }.disabled(offset == 0 || model.loadingPage)
                Text("\(model.page.total == 0 ? 0 : offset + 1)–\(min(offset + model.page.rows.count,model.page.total))").font(.caption.monospacedDigit())
                Button("下一页") { offset += 100 }.disabled(offset + 100 >= model.page.total || model.loadingPage)
            }
            Table(model.page.rows, selection: $selectedID) {
                TableColumn("时间") { Text($0.date.formatted(date: .abbreviated, time: .standard)).font(.caption.monospacedDigit()) }.width(min: 145, ideal: 175)
                TableColumn("值") { Text(metric.displayValue($0.value) + " " + metric.displayUnit).monospacedDigit() }.width(min: 100, ideal: 125)
                TableColumn("来源", value: \.source).width(min: 120, ideal: 160)
                TableColumn("设备", value: \.model).width(min: 70, ideal: 90)
            }
            .disabled(model.loadingPage)
            .overlay {
                if !model.loadingPage && model.page.rows.isEmpty && model.pageError == nil {
                    ContentUnavailableView("该范围内没有记录", systemImage: "line.3.horizontal.decrease.circle", description: Text("试试其他指标、来源或更长时间范围。空数据不代表没有活动或未授权。"))
                }
            }
            if let selected {
                DisclosureGroup("所选记录详情") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("UUID：\(selected.id)")
                        Text("来源：\(selected.sourceBundle)")
                        Text("区间：\(selected.start) → \(selected.end)")
                        Text("元数据：\(selected.metadata)")
                    }.font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(12).background(BridgeTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }.padding(26).navigationTitle("原始记录")
        .task(id: queryKey + "|\(model.recordRefreshVersion)") { selectedID = nil; await model.load(metric: metric, start: beginning, end: end, source: source, offset: offset) }
        .onChange(of: metric) { _, _ in offset = 0 }
        .onChange(of: days) { _, _ in offset = 0 }
        .onChange(of: source) { _, _ in offset = 0 }
    }
    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(metric.isInterval ? "当前页记录区间" : "当前页原始采样").font(.subheadline.weight(.semibold)); Spacer(); Text("\(model.page.rows.count) 条 · 未跨来源合并").font(.caption).foregroundStyle(.secondary) }
            Chart(model.page.rows) { row in
                if metric.isInterval {
                    RectangleMark(xStart: .value("开始", row.date), xEnd: .value("结束",row.end.bridgeDate ?? row.date), y: .value("来源", row.source))
                        .foregroundStyle(by: .value("来源", row.source)).opacity(0.65)
                } else {
                    PointMark(x: .value("时间", row.date), y: .value(metric.displayUnit,row.value))
                        .foregroundStyle(by: .value("来源",row.source)).symbolSize(17)
                }
            }.chartLegend(position: .bottom).frame(height: 150)
            Text(metric.explanation).font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(BridgeTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MCPPanel: View {
    @ObservedObject var model: DesktopModel
    @State private var copied = false
    var configuration: String {
        "[mcp_servers.watchbridge]\ncommand = \(String(reflecting: model.python))\nargs = [\(String(reflecting: model.runtime.appendingPathComponent("scripts/run.py").path)), \"mcp\"]\n\n[mcp_servers.watchbridge.env]\nWATCHBRIDGE_HOME = \(String(reflecting: model.directory.path))"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PanelTitle(title: "MCP 控制台", subtitle: "查看本机集成，让你信任的 AI 客户端只读访问这些记录。")
                BridgeCard {
                    HStack { Label("watchbridge · stdio", systemImage: "terminal").font(.headline); Spacer(); Button("检测连接") { Task { await model.checkMCP() } }.disabled(model.runningAction) }
                    Text(model.mcpResult).foregroundStyle(.secondary).accessibilityIdentifier("desktop.mcp.status")
                    Text("接收服务和查询服务相互独立。停止网络接收后，已有数据仍可通过 MCP 查询。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(model.tools) { tool in
                    BridgeCard {
                        Label(title(tool.name), systemImage: "chevron.left.forwardslash.chevron.right").font(.headline)
                        Text(tool.name).font(.body.monospaced()).textSelection(.enabled)
                        Text(detail(tool.name)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                BridgeCard {
                    HStack { Text("客户端配置").font(.headline); Spacer(); Button(copied ? "已复制" : "复制配置") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(configuration,forType:.string); copied = true } }
                    Text(configuration).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Text("这里只展示维律的配置，不显示其他 MCP 的密钥。工具名保留 watchbridge，以兼容已有客户端。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("AI 查询的健康记录会进入当前对话和模型服务。这里不会把数据自动上传给模型；请在可信客户端中按需查询。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(30)
        }.navigationTitle("MCP 控制台")
    }
    private func title(_ name: String) -> String { switch name { case "watchbridge_status": "数据清单与状态"; case "watchbridge_day": "按日查看原始记录"; default: "按时间范围查询" } }
    private func detail(_ name: String) -> String { switch name { case "watchbridge_status": "指标、条数、来源时间及设备最近同步状态。"; case "watchbridge_day": "按北京时间读取某一天；跨午夜的睡眠区间仍保留。"; default: "按指标、来源、起止时间分页查询，每页最多 500 条。" } }
}

private struct DevicePanel: View {
    @ObservedObject var model: DesktopModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PanelTitle(title: "设备与配对", subtitle: "让你的 iPhone 通过本地网络连接这台 Mac。")
                BridgeCard {
                    HStack { Label("添加 iPhone", systemImage: "qrcode").font(.headline); Spacer(); Button("生成配对二维码") { Task { await model.pair() } }.buttonStyle(.borderedProminent).disabled(model.runningAction || !model.serviceOnline) }
                    Text("连接同一 Wi‑Fi，在 iPhone 系统相机中扫描，再在维律中核对目标 Mac 并确认。二维码 5 分钟有效，只可使用一次。")
                        .foregroundStyle(.secondary)
                    if !model.serviceOnline { Text("先在存储与服务中启动接收服务。").font(.footnote).foregroundStyle(.secondary) }
                    if let action = model.actionMessage { Text(action).font(.footnote) }
                }
                ForEach(model.snapshot?.devices.filter { !$0.revoked } ?? []) { device in
                    BridgeCard {
                        Label(device.name, systemImage: "iphone").font(.headline)
                        LabeledContent("最近接收", value: device.lastSync?.bridgeDate?.formatted(date: .abbreviated, time: .shortened) ?? "尚未同步")
                        Text("只接收已配对设备的加密上传。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if model.snapshot?.devices.contains(where: { !$0.revoked }) != true {
                    ContentUnavailableView("尚未配对设备", systemImage: "iphone.slash", description: Text("生成上方二维码开始连接。"))
                }
            }.padding(30)
        }.navigationTitle("设备与配对")
    }
}

private struct PairingPanel: View {
    @ObservedObject var model: DesktopModel
    @State private var qrImage: NSImage?
    private func makeQR() -> NSImage? {
        guard let link = model.pairingLink else { return nil }
        let filter = CIFilter.qrCodeGenerator(); filter.message = Data(link.utf8); filter.correctionLevel = "M"
        guard let image = filter.outputImage, let cg = CIContext().createCGImage(image.transformed(by: CGAffineTransform(scaleX: 8,y: 8)),from: image.extent.applying(CGAffineTransform(scaleX: 8,y: 8))) else { return nil }
        return NSImage(cgImage: cg,size: NSSize(width: 280,height: 280))
    }
    var body: some View {
        VStack(spacing: 20) {
            HStack { BrandMark(size: 38); Text("连接到维律").font(.title2.bold()); Spacer(); Button("完成") { model.closePairing(); Task { await model.refresh(); model.recordRefreshVersion += 1 } } }
            TimelineView(.periodic(from: .now,by: 1)) { context in
                if let expiry = model.pairingExpiry, expiry > context.date, let qr = qrImage {
                    Image(nsImage: qr).interpolation(.none).resizable().scaledToFit().frame(width: 280,height: 280).padding(16).background(.white,in:RoundedRectangle(cornerRadius:18))
                    Text("用 iPhone 系统相机扫码 · 剩余 \(max(0,Int(expiry.timeIntervalSince(context.date)))) 秒").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                } else { ContentUnavailableView("二维码已过期",systemImage:"clock",description:Text("关闭后重新生成即可。")) }
            }
            Text("二维码包含一次性配对信息，请只在自己的手机上使用。手机确认后才会建立连接。")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding(28).frame(width:450)
            .task(id: model.pairingLink) { qrImage = makeQR() }
    }
}

private struct StoragePanel: View {
    @ObservedObject var model: DesktopModel
    @State private var stopConfirmation = false
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                PanelTitle(title:"存储与服务",subtitle:"文件在本机，接收与查询由你控制。")
                BridgeCard {
                    Label("数据仓库",systemImage:"externaldrive").font(.headline)
                    Text(model.directory.path).font(.caption.monospaced()).textSelection(.enabled)
                    LabeledContent("数据库文件",value:ByteCountFormatter.string(fromByteCount:model.snapshot?.size ?? 0,countStyle:.file))
                    Button("在访达中显示") { NSWorkspace.shared.open(model.directory) }
                    Text("SQLite 只读浏览；没有自动清理或删除原始数据。备份应包含数据库、证书和私钥，并妥善保管。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                BridgeCard {
                    Label(model.serviceOnline ? "HTTPS 接收服务在线" : "HTTPS 接收服务离线",systemImage:"network").font(.headline)
                    Text("本地网络 · TCP 8765 · 固定证书校验").font(.subheadline).foregroundStyle(.secondary)
                    if model.serviceOnline { Button("停止接收服务") { stopConfirmation = true }.disabled(model.runningAction) }
                    else { Button("启动接收服务") { Task { await model.service(start:true) } }.disabled(model.runningAction) }
                    Button("安装 / 更新本机服务") { Task { await model.installService() } }.disabled(model.runningAction)
                    Text("更新会先备份现有运行文件和数据库，保留配对与客户端配置。").font(.footnote).foregroundStyle(.secondary)
                    if let message = model.actionMessage { Text(message).font(.footnote) }
                }
                BridgeCard {
                    Label("维律 Veyra 0.2",systemImage:"info.circle").font(.headline)
                    Picker("显示模式", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }
                    Text("原生 SwiftUI 客户端。接收服务与 MCP 沿用 watchbridge 标识，兼容已有配对和数据目录。")
                        .foregroundStyle(.secondary)
                    Text("iPhone 个人开发签名需要定期重签；后台同步运行时机由 iOS 决定。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(30)
        }.navigationTitle("存储与服务")
        .confirmationDialog("停止接收新记录？",isPresented:$stopConfirmation,titleVisibility:.visible) {
            Button("停止接收服务") { Task { await model.service(start:false) } }
            Button("取消",role:.cancel) {}
        } message: { Text("iPhone 将暂时无法上传，已有记录和只读 MCP 查询保留。") }
    }
}
