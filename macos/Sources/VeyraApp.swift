import SwiftUI
import AppKit

@main
struct VeyraApp: App {
    @StateObject private var model = DesktopModel()
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("维律 Veyra",id:"main") { DesktopRoot(model:model) }
            .defaultSize(width:1190,height:800)
        MenuBarExtra("维律",systemImage:"circle.hexagongrid") {
            Text(model.serviceOnline ? "接收服务在线" : "接收服务离线")
            Button("打开维律") { openWindow(id:"main"); NSApplication.shared.activate(ignoringOtherApps:true) }
            Button("刷新数据") { Task { await model.refresh(); model.recordRefreshVersion += 1 } }
            Divider()
            Button("退出维律") { NSApplication.shared.terminate(nil) }
        }
    }
}
