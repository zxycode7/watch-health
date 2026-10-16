import Foundation
import SQLite3

struct MetricInventory: Identifiable {
    var id: String { metric.rawValue }
    let metric: HealthMetric
    let count: Int
    let latest: String?
}
struct PairedDevice: Identifiable { let id: String; let name: String; let lastSync: String?; let revoked: Bool }
struct SourceEntry: Identifiable, Hashable { var id: String { bundle }; let bundle: String; let name: String }
struct DesktopRecord: Identifiable {
    let id: String; let start: String; let end: String; let value: Double; let unit: String
    let source: String; let sourceBundle: String; let model: String; let metadata: String
    var date: Date { start.bridgeDate ?? .distantPast }
}
struct DatabaseSnapshot { let inventory: [MetricInventory]; let devices: [PairedDevice]; let sources: [SourceEntry]; let size: Int64 }
struct RecordPage { let rows: [DesktopRecord]; let total: Int }

// Every connection is read-only. Parameters never become SQL text.
actor LocalDatabase {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    private func query(_ sql: String, _ parameters: [String] = []) throws -> [[String: String]] {
        var database: OpaquePointer?
        let path = directory.appendingPathComponent("health.sqlite3").path
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            throw BridgeError.message("尚未找到可读的数据仓库。请先安装本机服务，并让 iPhone 完成一次同步。")
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 3000)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw BridgeError.message("数据仓库版本不匹配，请更新本机服务后刷新。") }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in parameters.enumerated() {
            let bound = value.withCString { sqlite3_bind_text(statement, Int32(offset + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard bound == SQLITE_OK else { throw BridgeError.message("无法设置查询条件。") }
        }
        var rows: [[String: String]] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            var row: [String: String] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                if let text = sqlite3_column_text(statement, column) { row[name] = String(cString: text) }
            }
            rows.append(row)
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw BridgeError.message("读取超时或数据仓库忙碌，请稍后刷新。") }
        return rows
    }
    func snapshot() throws -> DatabaseSnapshot {
        let metrics = try query("SELECT type,COUNT(*) AS count,MAX(start) AS latest FROM samples GROUP BY type")
        let inventory = HealthMetric.allCases.map { metric in
            let row = metrics.first { $0["type"] == metric.rawValue }
            return MetricInventory(metric: metric, count: Int(row?["count"] ?? "0") ?? 0, latest: row?["latest"])
        }
        let devices = try query("SELECT id,name,last_sync,revoked FROM devices ORDER BY paired_at DESC").map {
            PairedDevice(id: $0["id"]!, name: $0["name"] ?? "iPhone", lastSync: $0["last_sync"], revoked: $0["revoked"] == "1")
        }
        let sources = try query("SELECT source_bundle,MIN(source_name) AS name FROM samples GROUP BY source_bundle ORDER BY name").map {
            SourceEntry(bundle: $0["source_bundle"]!, name: $0["name"] ?? $0["source_bundle"]!)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("health.sqlite3").path)
        return DatabaseSnapshot(inventory: inventory, devices: devices, sources: sources, size: (attributes[.size] as? NSNumber)?.int64Value ?? 0)
    }
    func page(metric: HealthMetric, start: Date, end: Date, source: String, offset: Int) throws -> RecordPage {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'+00:00'"
        let first = formatter.string(from: start); let last = formatter.string(from: end)
        var predicate = "type=? AND start<? AND (end>? OR (start=end AND start>=?))"
        var args = [metric.rawValue, last, first, first]
        if !source.isEmpty { predicate += " AND source_bundle=?"; args.append(source) }
        let total = Int(try query("SELECT COUNT(*) AS count FROM samples WHERE " + predicate, args).first?["count"] ?? "0") ?? 0
        let rows = try query("SELECT * FROM samples WHERE " + predicate + " ORDER BY start DESC,id LIMIT 100 OFFSET ?", args + [String(max(0,offset))]).map {
            guard let text = $0["value"], let value = Double(text), value.isFinite else {
                throw BridgeError.message("数据仓库中有无法解释的数值，请检查原始记录。未将其替换为零。")
            }
            return DesktopRecord(id: $0["id"]!, start: $0["start"]!, end: $0["end"]!, value: value,
                unit: $0["unit"] ?? "", source: $0["source_name"] ?? "", sourceBundle: $0["source_bundle"] ?? "", model: $0["device_model"] ?? "", metadata: $0["metadata"] ?? "{}")
        }
        return RecordPage(rows: rows, total: total)
    }
}
