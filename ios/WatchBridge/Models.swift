import Foundation

enum HealthMetric: String, CaseIterable, Codable, Identifiable {
    case steps
    case heart_rate
    case resting_heart_rate
    case hrv
    case active_energy
    case exercise_time
    case blood_oxygen
    case respiratory_rate
    case body_mass
    case wrist_temperature
    case sleep
    case workout
    case vo2_max
    case heart_rate_recovery
    case walking_heart_rate
    case basal_energy
    case distance_walking_running
    case flights_climbed
    case stand_time
    case walking_speed
    case walking_step_length
    case walking_asymmetry
    case walking_double_support
    case walking_steadiness
    case daylight
    case environmental_audio
    case headphone_audio
    case breathing_disturbances
    var id: String { rawValue }
    var title: String { switch self {
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
        case .vo2_max: "最大摄氧量"
        case .heart_rate_recovery: "心率恢复"
        case .walking_heart_rate: "步行平均心率"
        case .basal_energy: "静息能量"
        case .distance_walking_running: "步行与跑步距离"
        case .flights_climbed: "爬楼层数"
        case .stand_time: "站立时间"
        case .walking_speed: "步行速度"
        case .walking_step_length: "步长"
        case .walking_asymmetry: "步行不对称性"
        case .walking_double_support: "双足支撑时间"
        case .walking_steadiness: "步行稳定性"
        case .daylight: "日照时间"
        case .environmental_audio: "环境音量"
        case .headphone_audio: "耳机音量"
        case .breathing_disturbances: "睡眠呼吸紊乱"
    } }
    var unit: String { switch self {
        case .steps: "count"
        case .heart_rate: "count/min"
        case .resting_heart_rate: "count/min"
        case .hrv: "ms"
        case .active_energy: "kcal"
        case .exercise_time: "min"
        case .blood_oxygen: "%"
        case .respiratory_rate: "count/min"
        case .body_mass: "kg"
        case .wrist_temperature: "degC"
        case .sleep: "category"
        case .workout: "s"
        case .vo2_max: "ml/kg*min"
        case .heart_rate_recovery: "count/min"
        case .walking_heart_rate: "count/min"
        case .basal_energy: "kcal"
        case .distance_walking_running: "m"
        case .flights_climbed: "count"
        case .stand_time: "min"
        case .walking_speed: "m/s"
        case .walking_step_length: "m"
        case .walking_asymmetry: "%"
        case .walking_double_support: "%"
        case .walking_steadiness: "%"
        case .daylight: "min"
        case .environmental_audio: "dBASPL"
        case .headphone_audio: "dBASPL"
        case .breathing_disturbances: "count"
    } }
    var group: String { switch self {
        case .steps: "活动"
        case .heart_rate: "心脏"
        case .resting_heart_rate: "心脏"
        case .hrv: "心脏"
        case .active_energy: "活动"
        case .exercise_time: "活动"
        case .blood_oxygen: "呼吸与睡眠"
        case .respiratory_rate: "呼吸与睡眠"
        case .body_mass: "身体"
        case .wrist_temperature: "呼吸与睡眠"
        case .sleep: "呼吸与睡眠"
        case .workout: "活动"
        case .vo2_max: "心脏"
        case .heart_rate_recovery: "心脏"
        case .walking_heart_rate: "心脏"
        case .basal_energy: "活动"
        case .distance_walking_running: "活动"
        case .flights_climbed: "活动"
        case .stand_time: "活动"
        case .walking_speed: "步态"
        case .walking_step_length: "步态"
        case .walking_asymmetry: "步态"
        case .walking_double_support: "步态"
        case .walking_steadiness: "步态"
        case .daylight: "环境"
        case .environmental_audio: "环境"
        case .headphone_audio: "环境"
        case .breathing_disturbances: "呼吸与睡眠"
    } }
    var symbol: String { switch self {
        case .steps: "figure.walk"
        case .heart_rate: "heart"
        case .resting_heart_rate: "heart.text.clipboard"
        case .hrv: "waveform.path"
        case .active_energy: "flame"
        case .exercise_time: "figure.run"
        case .blood_oxygen: "lungs"
        case .respiratory_rate: "wind"
        case .body_mass: "scalemass"
        case .wrist_temperature: "thermometer.medium"
        case .sleep: "bed.double"
        case .workout: "figure.strengthtraining.traditional"
        case .vo2_max: "lungs.fill"
        case .heart_rate_recovery: "heart.circle"
        case .walking_heart_rate: "figure.walk.circle"
        case .basal_energy: "bolt.heart"
        case .distance_walking_running: "point.topleft.down.to.point.bottomright.curvepath"
        case .flights_climbed: "stairs"
        case .stand_time: "figure.stand"
        case .walking_speed: "speedometer"
        case .walking_step_length: "shoeprints.fill"
        case .walking_asymmetry: "figure.walk.motion"
        case .walking_double_support: "figure.stand.line.dotted.figure.stand"
        case .walking_steadiness: "figure.walk.diamond"
        case .daylight: "sun.max"
        case .environmental_audio: "ear"
        case .headphone_audio: "headphones"
        case .breathing_disturbances: "waveform.path.ecg.rectangle"
    } }
    var explanation: String { switch self {
        case .steps: "保留每个来源的步数记录，不直接跨设备相加。"
        case .heart_rate: "每次心率采样的时间和来源。"
        case .resting_heart_rate: "Apple 健康中已有的静息心率结果。"
        case .hrv: "SDNN 采样值；不是连续逐搏心电图。"
        case .active_energy: "活动消耗的原始记录，保留来源。"
        case .exercise_time: "Apple 健康已记录的锻炼时间。"
        case .blood_oxygen: "读取已有血氧样本，不能启动被系统禁用的传感器。"
        case .respiratory_rate: "包括设备已生成的睡眠呼吸采样。"
        case .body_mass: "来自健康 App、体重秤或手动录入。"
        case .wrist_temperature: "支持设备在睡眠中产生的手腕温度样本。"
        case .sleep: "保留清醒、REM、核心、深睡和卧床区间，不混合累加。"
        case .workout: "训练时长、类型、距离和能量。"
        case .vo2_max: "设备已估算的心肺适能；并非每次运动都有。"
        case .heart_rate_recovery: "运动结束一分钟的心率恢复记录。"
        case .walking_heart_rate: "Apple 健康生成的步行心率记录。"
        case .basal_energy: "静息状态下的能量消耗估算。"
        case .distance_walking_running: "保留每个来源的距离区间。"
        case .flights_climbed: "设备记录的上楼层数。"
        case .stand_time: "手表已经生成的站立分钟数。"
        case .walking_speed: "健康库中的步行速度样本。"
        case .walking_step_length: "健康库中的步行步长样本。"
        case .walking_asymmetry: "按百分数展示已有的步态记录。"
        case .walking_double_support: "双脚同时接触地面的时间占比。"
        case .walking_steadiness: "读取系统计算的稳定性，不自行推断跌倒风险。"
        case .daylight: "手表记录的日光暴露时间。"
        case .environmental_audio: "已存储的环境声级，不能反推出录音。"
        case .headphone_audio: "已存储的耳机声级。"
        case .breathing_disturbances: "读取系统生成的夜间指标；不自行诊断睡眠呼吸暂停。"
    } }
    var isPercentage: Bool { [.blood_oxygen, .walking_asymmetry, .walking_double_support, .walking_steadiness].contains(self) }
    var isInterval: Bool { self == .sleep || self == .workout }
    static let groups = ["心脏", "呼吸与睡眠", "活动", "步态", "身体", "环境"]
    static let defaults: Set<HealthMetric> = [.steps, .heart_rate, .resting_heart_rate, .hrv, .sleep, .workout, .active_energy]
    func displayValue(_ value: Double) -> String {
        if self == .sleep { return [0: "卧床", 1: "睡眠（未分期）", 2: "清醒", 3: "核心睡眠", 4: "深度睡眠", 5: "REM 睡眠"][Int(value)] ?? "阶段 \(Int(value))" }
        if self == .workout { return "\(Int(value / 60)) 分钟" }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
    var displayUnit: String {
        switch unit { case "count/min": "次/分"; case "count": self == .steps ? "步" : (self == .flights_climbed ? "层" : "次"); case "category", "s": ""; case "degC": "°C"; case "ml/kg*min": "mL/kg/min"; default: unit }
    }
}

struct SampleMetadata: Codable {
    var category: Int?
    var activity_type: UInt?
    var duration_seconds: Double?
    var distance_m: Double?
    var energy_kcal: Double?
    var was_user_entered: Bool?
    var source_version: String?
    var source_product_type: String?
    var source_os: String?
    var device_hardware: String?
    var device_firmware: String?
    var device_software: String?
    var unit_convention: String?
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
    case connection(String)
    var stopsSync: Bool { if case .connection = self { return true }; return false }
    var errorDescription: String? {
        switch self { case .message(let message), .connection(let message): message }
    }
}
