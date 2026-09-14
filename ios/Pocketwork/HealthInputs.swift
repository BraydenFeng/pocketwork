import Combine
import HealthKit

@MainActor final class HealthInputs: ObservableObject {
	@Published var values: [String: Double] = [:]
	@Published var message: String?
	@Published var busy = false
	private let store = HKHealthStore()
	private func quantity(_ metric: String) -> (HKQuantityType, HKUnit)? {
		let identifier: HKQuantityTypeIdentifier; let unit: HKUnit
		switch metric {
		case "steps": identifier = .stepCount; unit = .count()
		case "active_energy": identifier = .activeEnergyBurned; unit = .kilocalorie()
		case "exercise_minutes": identifier = .appleExerciseTime; unit = .minute()
		case "protein": identifier = .dietaryProtein; unit = .gram()
		case "carbohydrates": identifier = .dietaryCarbohydrates; unit = .gram()
		case "fat": identifier = .dietaryFatTotal; unit = .gram()
		case "water": identifier = .dietaryWater; unit = .literUnit(with: .milli)
		default: return nil
		}
		guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }; return (type, unit)
	}
	func refresh(_ metrics: [String], authorize: Bool = false) async {
		guard !busy, !CommandLine.arguments.contains("--ui-testing") else { return }
		guard HKHealthStore.isHealthDataAvailable() else { message = "Apple Health is unavailable on this device."; return }
		busy = true; defer { busy = false }
		do {
			let quantities = Array(Set(metrics)).compactMap { metric in quantity(metric).map { (metric, $0.0, $0.1) } }
			if authorize { try await store.requestAuthorization(toShare: [], read: Set(quantities.map { $0.1 as HKObjectType })) }
			var next: [String: Double] = [:]
			for (metric, type, unit) in quantities {
				let now = Date(); let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: now), end: now, options: .strictStartDate)
				let value: Double? = try await withCheckedThrowingContinuation { continuation in
					let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
						if let error { continuation.resume(throwing: error); return }
						continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
					}
					store.execute(query)
				}
				if let value, value.isFinite, value >= 0 { next[metric] = value }
			}
			values = next; message = next.count == quantities.count ? nil : "Some metrics have no readable data. Check Health access or refresh after your data syncs."
		} catch { values = [:]; message = "Could not read Apple Health: " + error.localizedDescription }
	}
}
