import SwiftUI
import UIKit
import BackgroundTasks

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    static let refreshIdentifier = "local.watchbridge.refresh"
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        SyncModel.shared.restoreObservers()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            let work = Task { @MainActor in
                Self.scheduleRefresh()
                await SyncModel.shared.sync()
                refresh.setTaskCompleted(success: !Task.isCancelled && !SyncModel.shared.isError)
            }
            refresh.expirationHandler = { work.cancel() }
        }
        return true
    }
    static func scheduleRefresh() {
        let model = SyncModel.shared
        guard model.connection != nil, model.authorizationConfigured, !model.paused else { return }
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        // This is an earliest opportunity, never a promised interval.
        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("Veyra: background refresh requested; execution time is controlled by iOS")
            #endif
        } catch {
            #if DEBUG
            print("Veyra: background refresh request unavailable (\((error as NSError).code))")
            #endif
        }
    }
}

@main
@MainActor
struct WatchBridgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = SyncModel.shared
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup { ContentView(model: model).onChange(of: phase) { _, next in
            if next == .background { AppDelegate.scheduleRefresh() }
        } }
    }
}
