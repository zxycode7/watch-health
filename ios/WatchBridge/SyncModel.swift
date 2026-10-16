import SwiftUI
import HealthKit
import UIKit

@MainActor
final class SyncModel: ObservableObject {
    static let shared = SyncModel()
    @Published private(set) var connection = CredentialStore.load()
    @Published private(set) var isSyncing = false
    @Published private(set) var isPairing = false
    @Published private(set) var isAuthorizing = false
    @Published private(set) var message = "配对你的 Mac，开始同步。"
    @Published private(set) var isError = false
    @Published private(set) var transferred = 0
    @Published private(set) var lastSync: Date?
    @Published private(set) var selected: Set<HealthMetric>
    @Published private(set) var authorizationConfigured: Bool
    @Published private(set) var paused: Bool
    @Published private(set) var previews: [HealthMetric: [HealthRecord]] = [:]
    @Published private(set) var previewErrors: [HealthMetric: String] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var completedMetrics: Set<HealthMetric> = []
    @Published private(set) var currentMetric: HealthMetric?
    @Published private(set) var stopRequested = false
    private let reader = HealthReader()
    private let defaults = UserDefaults.standard
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var needsAnotherPass = false
    private var observing = false

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: "selectedMetrics")
        selected = saved.map { Set($0.compactMap(HealthMetric.init(rawValue:))) } ?? HealthMetric.defaults
        authorizationConfigured = UserDefaults.standard.bool(forKey: "authorizationConfigured")
        paused = UserDefaults.standard.bool(forKey: "paused")
        let timestamp = UserDefaults.standard.double(forKey: "lastSync")
        lastSync = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        if connection != nil { message = "已配对。连接同一 Wi‑Fi 后即可同步。" }
    }

    private var deviceID: String {
        if let saved = defaults.string(forKey: "deviceID") { return saved }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: "deviceID")
        return id
    }

    func pair(_ text: String) async {
        guard !isPairing, !isSyncing, !isAuthorizing else { return }
        isPairing = true
        defer { isPairing = false }
        do {
            let link = try PairingLink(text)
            let next = try await BridgeClient.pair(link, deviceID: deviceID, name: UIDevice.current.name)
            try CredentialStore.save(next)
            connection = next
            resetAnchors(days: 30)
            lastSync = nil
            defaults.removeObject(forKey: "lastSync")
            message = "Mac 已配对。下一步：选择数据，授权并同步。"
            isError = false
        } catch { fail(error.localizedDescription) }
    }

    func select(_ metric: HealthMetric, enabled: Bool) {
        guard !isSyncing, !isAuthorizing else { return }
        if enabled { selected.insert(metric) } else { selected.remove(metric) }
        defaults.set(selected.map(\.rawValue).sorted(), forKey: "selectedMetrics")
        authorizationConfigured = false
        defaults.set(false, forKey: "authorizationConfigured")
        reader.disableBackground()
        observing = false
        message = "数据范围已更新。请点“授权并同步”确认健康读取权限。"
    }

    func setPaused(_ value: Bool) {
        guard !isSyncing, !isAuthorizing else { return }
        paused = value
        defaults.set(value, forKey: "paused")
        if value { reader.disableBackground(); observing = false; message = "同步已暂停。已有数据保留在 Mac。" }
        else { restoreObservers(); message = "同步已恢复。可点“立即同步”补齐数据。" }
    }

    var busy: Bool { isSyncing || isAuthorizing || isPairing }
    func supports(_ metric: HealthMetric) -> Bool { reader.sampleType(metric) != nil }

    func refreshPreviews() async {
        guard authorizationConfigured, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for metric in selected {
            do { previews[metric] = try await reader.recent(metric); previewErrors.removeValue(forKey: metric) }
            catch { previewErrors[metric] = "暂时无法读取，解锁手机后重试。" }
        }
        for metric in previews.keys where !selected.contains(metric) { previews.removeValue(forKey: metric) }
    }

    func requestStop() {
        guard isSyncing else { return }
        stopRequested = true
        message = "正在保存已确认的进度…"
    }

    func authorizeAndSync() async {
        guard connection != nil, !paused, !selected.isEmpty, !busy else { return }
        isAuthorizing = true
        do {
            try await reader.authorize(selected)
            // Completion does not disclose which read permissions the person granted.
            authorizationConfigured = true
            defaults.set(true, forKey: "authorizationConfigured")
            isAuthorizing = false
            restoreObservers()
            await sync()
            await refreshPreviews()
        } catch {
            isAuthorizing = false
            fail("读取设置未完成：\(error.localizedDescription)")
        }
    }

    func restoreObservers() {
        guard connection != nil, authorizationConfigured, !paused, !observing else { return }
        observing = true
        reader.observe(selected) { completion in
            Task { @MainActor in
                await self.sync()
                completion()
            }
        }
    }

    func resume() async {
        restoreObservers()
        if connection != nil, authorizationConfigured, !paused { await sync() }
    }

    func backfill(days: Int) async {
        guard !busy, !paused, authorizationConfigured, connection != nil else { return }
        resetAnchors(days: days)
        await sync()
    }

    private func resetAnchors(days: Int) {
        let since = days == 0 ? Date(timeIntervalSince1970: 0) : Date().addingTimeInterval(-Double(days) * 86400)
        for metric in HealthMetric.allCases {
            defaults.removeObject(forKey: "anchor.\(metric.rawValue)")
            defaults.set(since.timeIntervalSince1970, forKey: "since.\(metric.rawValue)")
        }
    }

    func sync() async {
        guard let connection, authorizationConfigured, !paused, !selected.isEmpty else { return }
        if isSyncing {
            needsAnotherPass = true
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        isSyncing = true
        stopRequested = false
        completedMetrics = []
        isError = false
        transferred = 0
        defer {
            isSyncing = false
            currentMetric = nil
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume() }
        }
        var failures: [String] = []
        repeat {
            needsAnotherPass = false
            failures.removeAll()
            for metric in HealthMetric.allCases where selected.contains(metric) {
                if stopRequested || Task.isCancelled { stopRequested = true; break }
                currentMetric = metric
                message = "正在同步\(metric.title)"
                do { try await syncMetric(metric, connection: connection); if !stopRequested { completedMetrics.insert(metric) } }
                catch {
                    let shouldStop = (error as? BridgeError)?.stopsSync == true
                    let error = error as NSError
                    if error.domain == HKErrorDomain && error.code == HKError.Code.errorDatabaseInaccessible.rawValue {
                        failures.append("\(metric.title)：请解锁 iPhone 后重试。")
                    } else { failures.append("\(metric.title)：\(error.localizedDescription)") }
                    if shouldStop { break }
                }
                if UIApplication.shared.applicationState != .active && UIApplication.shared.backgroundTimeRemaining < 5 {
                    failures.append("已保存当前进度。下次打开 App 会继续同步。")
                    break
                }
            }
        } while needsAnotherPass && failures.isEmpty && !stopRequested
        if stopRequested {
            message = "本次同步已停止，已确认的进度已保存。"
        } else if failures.isEmpty {
            lastSync = Date()
            defaults.set(lastSync!.timeIntervalSince1970, forKey: "lastSync")
            message = transferred > 0 ? "同步完成，已发送 \(transferred) 条变更。" : "同步完成，没有新增变更。空数据也可能是尚未授权或没有记录。"
        } else { fail(failures.prefix(3).joined(separator: "\n")) }
    }

    private func syncMetric(_ metric: HealthMetric, connection: Connection) async throws {
        let anchorKey = "anchor.\(metric.rawValue)"
        let sinceKey = "since.\(metric.rawValue)"
        if defaults.object(forKey: sinceKey) == nil {
            defaults.set(Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970, forKey: sinceKey)
        }
        let since = Date(timeIntervalSince1970: defaults.double(forKey: sinceKey))
        var anchor: HKQueryAnchor?
        if let data = defaults.data(forKey: anchorKey) {
            anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        }
        while true {
            if stopRequested || Task.isCancelled { stopRequested = true; return }
            let page = try await reader.page(metric, since: since, anchor: anchor)
            try Task.checkCancellation()
            let additions = try page.samples.map { try reader.record($0, metric: metric) }
            let deleted = page.deleted.map { $0.uuid.uuidString.lowercased() }
            let anchorData = try page.anchor.map { try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
            let cursor = anchorData?.base64EncodedString() ?? ""
            // Split unusually large deletion sets. Persist the local anchor only after every part is acknowledged.
            let count = max(additions.count, deleted.count)
            for offset in stride(from: 0, to: max(count, 1), by: 500) {
                let records = offset < additions.count ? Array(additions[offset..<min(offset + 500, additions.count)]) : []
                let removed = offset < deleted.count ? Array(deleted[offset..<min(offset + 500, deleted.count)]) : []
                let batch = SyncPayload(batch_id: UUID().uuidString.lowercased(), type: metric.rawValue,
                    cursor: offset + 500 >= count ? cursor : "", samples: records, deleted: removed)
                let ack = try await BridgeClient.request("v1/sync", endpoint: connection.endpoint, pin: connection.fingerprint,
                    token: connection.token, body: batch, reply: SyncAcknowledgement.self)
                guard ack.ok, ack.batch_id == batch.batch_id, ack.accepted == records.count, ack.deleted == removed.count else {
                    throw BridgeError.message("Mac 尚未完整确认本批次，下次同步会自动重试。")
                }
                transferred += records.count + removed.count
            }
            if let anchorData { defaults.set(anchorData, forKey: anchorKey) }
            anchor = page.anchor
            if additions.isEmpty && deleted.isEmpty { break }
            if UIApplication.shared.applicationState != .active && UIApplication.shared.backgroundTimeRemaining < 5 {
                throw BridgeError.message("后台时间不足，已保存进度，打开 App 后会继续。")
            }
        }
    }

    private func fail(_ text: String) { isError = true; message = text }
}
