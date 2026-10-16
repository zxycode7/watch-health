import Foundation

enum HealthMetric: String, CaseIterable, Codable, Identifiable {
    case steps, heart_rate, resting_heart_rate, hrv, active_energy, exercise_time
    case blood_oxygen, respiratory_rate, body_mass, wrist_temperature, sleep, workout
    var id: String { rawValue }
    var title: String {
        switch self {
        case .steps: "步数"
        case .heart_rate: "心率"
        case .resting_heart_rate: "静息心率"
        case .hrv: "心率变异性"
        case .active_energy: "活动能量"
        case .exercise_time: "锻炼时间"
        case .blood_oxygen: "血氧"
        case .respiratory_rate: "呼吸频率"
        case .body_mass: "体重"
        case .wrist_temperature: "睡眠手腕温度"
        case .sleep: "睡眠阶段"
        case .workout: "体能训练"
        }
    }
    var unit: String {
        switch self {
        case .steps: "count"
        case .heart_rate, .resting_heart_rate, .respiratory_rate: "count/min"
        case .hrv: "ms"
        case .active_energy: "kcal"
        case .exercise_time: "min"
        case .blood_oxygen: "%"
        case .body_mass: "kg"
        case .wrist_temperature: "degC"
        case .sleep: "category"
        case .workout: "s"
        }
    }
    static let defaults: Set<HealthMetric> = [.steps, .heart_rate, .resting_heart_rate, .hrv, .sleep, .workout, .active_energy]
}

struct SampleMetadata: Codable {
    var category: Int?
    var activity_type: UInt?
    var duration_seconds: Double?
    var distance_m: Double?
    var energy_kcal: Double?
    var was_user_entered: Bool?
}

struct HealthRecord: Codable {
    var id: String
    var start: String
    var end: String
    var value: Double
    var unit: String
    var source_name: String
    var source_bundle: String
    var device_model: String
    var metadata: SampleMetadata
}

struct SyncPayload: Encodable {
    let batch_id: String
    let type: String
    let cursor: String
    let samples: [HealthRecord]
    let deleted: [String]
}

struct SyncAcknowledgement: Decodable {
    let ok: Bool
    let batch_id: String
    let accepted: Int
    let deleted: Int
}

struct Connection: Codable {
    let endpoint: URL
    let fingerprint: String
    let token: String
    let deviceID: String
}

struct PairingLink {
    let endpoint: URL
    let fingerprint: String
    let code: String

    init(_ text: String) throws {
        guard let link = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              link.scheme == "watchbridge", link.host == "pair",
              let items = link.queryItems,
              let address = items.first(where: { $0.name == "endpoint" })?.value,
              let url = URL(string: address), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              let pin = items.first(where: { $0.name == "pin" })?.value,
              pin.count == 64, pin.allSatisfy({ $0.isHexDigit }),
              let code = items.first(where: { $0.name == "code" })?.value, (20...100).contains(code.count)
        else { throw BridgeError.message("配对链接不完整。请在 Mac 上重新生成链接。") }
        endpoint = url
        fingerprint = pin.lowercased()
        self.code = code
    }
}

enum BridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}
