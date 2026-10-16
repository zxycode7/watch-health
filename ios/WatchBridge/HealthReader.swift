import Foundation
import HealthKit

final class HealthReader {
    let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []

    func sampleType(_ metric: HealthMetric) -> HKSampleType? {
        switch metric {
        case .steps: HKQuantityType.quantityType(forIdentifier: .stepCount)
        case .heart_rate: HKQuantityType.quantityType(forIdentifier: .heartRate)
        case .resting_heart_rate: HKQuantityType.quantityType(forIdentifier: .restingHeartRate)
        case .hrv: HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .active_energy: HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        case .exercise_time: HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)
        case .blood_oxygen: HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)
        case .respiratory_rate: HKQuantityType.quantityType(forIdentifier: .respiratoryRate)
        case .body_mass: HKQuantityType.quantityType(forIdentifier: .bodyMass)
        case .wrist_temperature: HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)
        case .sleep: HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
        case .workout: HKObjectType.workoutType()
        }
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
        let value: Double
        if let quantity = sample as? HKQuantitySample {
            value = quantity.quantity.doubleValue(for: HKUnit(from: metric.unit))
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
