import Foundation
import HealthKit

final class HealthReader {
    let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []

    func sampleType(_ metric: HealthMetric) -> HKSampleType? {
        if metric == .breathing_disturbances {
            if #available(iOS 18.0, *) { return HKQuantityType.quantityType(forIdentifier: .appleSleepingBreathingDisturbances) }
            return nil
        }
        switch metric {
        case .steps: return HKQuantityType.quantityType(forIdentifier: .stepCount)
        case .heart_rate: return HKQuantityType.quantityType(forIdentifier: .heartRate)
        case .resting_heart_rate: return HKQuantityType.quantityType(forIdentifier: .restingHeartRate)
        case .hrv: return HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .active_energy: return HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        case .exercise_time: return HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)
        case .blood_oxygen: return HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)
        case .respiratory_rate: return HKQuantityType.quantityType(forIdentifier: .respiratoryRate)
        case .body_mass: return HKQuantityType.quantityType(forIdentifier: .bodyMass)
        case .wrist_temperature: return HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)
        case .vo2_max: return HKQuantityType.quantityType(forIdentifier: .vo2Max)
        case .heart_rate_recovery: return HKQuantityType.quantityType(forIdentifier: .heartRateRecoveryOneMinute)
        case .walking_heart_rate: return HKQuantityType.quantityType(forIdentifier: .walkingHeartRateAverage)
        case .basal_energy: return HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)
        case .distance_walking_running: return HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        case .flights_climbed: return HKQuantityType.quantityType(forIdentifier: .flightsClimbed)
        case .stand_time: return HKQuantityType.quantityType(forIdentifier: .appleStandTime)
        case .walking_speed: return HKQuantityType.quantityType(forIdentifier: .walkingSpeed)
        case .walking_step_length: return HKQuantityType.quantityType(forIdentifier: .walkingStepLength)
        case .walking_asymmetry: return HKQuantityType.quantityType(forIdentifier: .walkingAsymmetryPercentage)
        case .walking_double_support: return HKQuantityType.quantityType(forIdentifier: .walkingDoubleSupportPercentage)
        case .walking_steadiness: return HKQuantityType.quantityType(forIdentifier: .appleWalkingSteadiness)
        case .daylight: return HKQuantityType.quantityType(forIdentifier: .timeInDaylight)
        case .environmental_audio: return HKQuantityType.quantityType(forIdentifier: .environmentalAudioExposure)
        case .headphone_audio: return HKQuantityType.quantityType(forIdentifier: .headphoneAudioExposure)
        case .sleep: return HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
        case .workout: return HKObjectType.workoutType()
        case .breathing_disturbances: return nil
        }
    }

    func recent(_ metric: HealthMetric, limit: Int = 30) async throws -> [HealthRecord] {
        guard let type = sampleType(metric) else { return [] }
        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
        return try samples.map { try record($0, metric: metric) }
    }

    func authorize(_ metrics: Set<HealthMetric>) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw BridgeError.message("此设备无法读取 Apple 健康数据。请在真实 iPhone 上运行。")
        }
        let types = Set(metrics.compactMap(sampleType).map { $0 as HKObjectType })
        try await store.requestAuthorization(toShare: [], read: types)
    }

    func observe(_ metrics: Set<HealthMetric>, onChange: @escaping (@escaping () -> Void) -> Void) {
        stopObserving()
        for type in metrics.compactMap(sampleType) {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                onChange(completion)
            }
            observers.append(query)
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }

    func stopObserving() {
        observers.forEach { store.stop($0) }
        observers.removeAll()
    }

    func disableBackground() {
        stopObserving()
        store.disableAllBackgroundDelivery { _, _ in }
    }

    struct Page {
        let samples: [HKSample]
        let deleted: [HKDeletedObject]
        let anchor: HKQueryAnchor?
    }

    func page(_ metric: HealthMetric, since: Date, anchor: HKQueryAnchor?) async throws -> Page {
        guard let type = sampleType(metric) else { throw BridgeError.message("设备不支持\(metric.title)。") }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
            let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: anchor, limit: 200) {
                _, samples, deleted, newAnchor, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: Page(samples: samples ?? [], deleted: deleted ?? [], anchor: newAnchor)) }
            }
            store.execute(query)
        }
    }

    func record(_ sample: HKSample, metric: HealthMetric) throws -> HealthRecord {
        var metadata = SampleMetadata()
        metadata.was_user_entered = sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool
        let revision = sample.sourceRevision
        metadata.source_version = revision.version
        metadata.source_product_type = revision.productType
        let os = revision.operatingSystemVersion
        metadata.source_os = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        metadata.device_hardware = sample.device?.hardwareVersion
        metadata.device_firmware = sample.device?.firmwareVersion
        metadata.device_software = sample.device?.softwareVersion
        metadata.unit_convention = metric.isPercentage ? "percentage_0_100" : nil
        let value: Double
        if let quantity = sample as? HKQuantitySample {
            value = quantity.quantity.doubleValue(for: HKUnit(from: metric.unit)) * (metric.isPercentage ? 100 : 1)
        } else if let category = sample as? HKCategorySample {
            value = Double(category.value)
            metadata.category = category.value
        } else if let workout = sample as? HKWorkout {
            value = workout.duration
            metadata.activity_type = workout.workoutActivityType.rawValue
            metadata.duration_seconds = workout.duration
            metadata.distance_m = workout.totalDistance?.doubleValue(for: .meter())
            if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                metadata.energy_kcal = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())
            }
        } else { throw BridgeError.message("遇到无法编码的健康记录，尚未推进同步进度。") }
        guard value.isFinite else { throw BridgeError.message("遇到无效数值，尚未推进同步进度。") }
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return HealthRecord(id: sample.uuid.uuidString.lowercased(), start: format.string(from: sample.startDate),
            end: format.string(from: sample.endDate), value: value, unit: metric.unit,
            source_name: sample.sourceRevision.source.name, source_bundle: sample.sourceRevision.source.bundleIdentifier,
            device_model: sample.device?.model ?? "", metadata: metadata)
    }
}
