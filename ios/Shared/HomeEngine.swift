import Darwin
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

struct HomePlace: Codable { var latitude: Double; var longitude: Double; var radius: Double = 150 }
struct HomeState: Codable {
	var document: AppDocument?
	var place: HomePlace?
	var at_home = false
	var enabled = false
	var ledger = HomeLedger()
}

// One shared file and a process lock serialize app/geofence and monitor-extension callbacks.
enum HomeEngine {
	static let prefix = "pocketwork.home."
	static var center: DeviceActivityCenter { DeviceActivityCenter() }
	static var shield: ManagedSettingsStore { ManagedSettingsStore(named: ManagedSettingsStore.Name(prefix + "shield")) }
	private static func transaction<T>(_ action: (inout HomeState) throws -> T) throws -> T {
		guard let group = Bundle.main.object(forInfoDictionaryKey: "PocketworkAppGroup") as? String, let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw DocumentError.invalid("Home storage is unavailable.") }
		return try HomeFileLock.with_lock(at: folder.appendingPathComponent("home.lock")) {
			let file = folder.appendingPathComponent("home-state.json")
			var state = FileManager.default.fileExists(atPath: file.path) ? try JSONDecoder().decode(HomeState.self, from: Data(contentsOf: file)) : HomeState()
			do {
				let result = try action(&state)
				try JSONEncoder().encode(state).write(to: file, options: .atomic)
				return result
			} catch {
				try JSONEncoder().encode(state).write(to: file, options: .atomic)
				throw error
			}
		}
	}

	static func snapshot() throws -> HomeState { try transaction { $0 } }
	static func set_home(_ place: HomePlace) throws {
		try transaction { $0.place = place; $0.at_home = false; $0.ledger.pause() }
		try reconcile()
	}
	static func location_changed(_ at_home: Bool) throws {
		try transaction { state in
			if state.at_home != at_home { state.ledger.pause() }
			state.at_home = at_home
		}
		try reconcile()
	}
	static func disable() throws {
		try transaction { $0.enabled = false; $0.ledger.pause() }
		shield.clearAllSettings()
		center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(prefix) })
	}
	static func configure(_ document: AppDocument, plan: SharedStore.ShieldPlan, enabled: Bool) throws {
		try document.validate()
		guard enabled else { try disable(); return }
		guard try snapshot().place != nil, AuthorizationCenter.shared.authorizationStatus == .approved else { throw DocumentError.invalid("Set your home and allow Screen Time access first.") }
		try SharedStore().save_plan(plan, for: document.id)
		try transaction { state in
			if state.document?.id != document.id { state.ledger = HomeLedger() }
			state.document = document; state.enabled = false; state.ledger.pause()
		}
		do {
			// DeviceActivity may synchronously launch the extension. Never hold home.lock across IPC.
			center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(prefix) })
			if let policy = document.home_allowance {
				for rule in policy.rules { for day in rule.days { for (index, window) in rule.windows.enumerated() {
					let start = ScheduleWindow.minutes(window.start)!, end = ScheduleWindow.minutes(window.end)!
					let schedule = DeviceActivitySchedule(intervalStart: DateComponents(timeZone: policy.calendar.timeZone, hour: start / 60, minute: start % 60, weekday: day), intervalEnd: DateComponents(timeZone: policy.calendar.timeZone, hour: end / 60, minute: end % 60, weekday: day), repeats: true)
					try center.startMonitoring(DeviceActivityName(prefix + "clock.\(day).\(index)"), during: schedule)
				} } }
				try center.startMonitoring(DeviceActivityName(prefix + "midnight"), during: DeviceActivitySchedule(intervalStart: DateComponents(timeZone: policy.calendar.timeZone, hour: 0, minute: 0), intervalEnd: DateComponents(timeZone: policy.calendar.timeZone, hour: 23, minute: 59), repeats: true))
			}
			try transaction { $0.enabled = true }
			try reconcile()
		} catch {
			let failure = error
			try disable()
			throw failure
		}
	}
	static func grant_allowance(key: String, minutes: Int) throws {
		try transaction { state in
			guard state.enabled, let policy = state.document?.home_allowance else { throw DocumentError.invalid("Enable a home allowance before adding screen time.") }
			state.ledger.reset_if_needed(policy: policy, now: .now)
			_ = try state.ledger.grant(key, minutes: minutes)
		}
		try reconcile()
	}
	static func clock_changed() throws { try reconcile() }
	static func reached(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) throws {
		guard activity.rawValue.hasPrefix(prefix + "meter."), let minutes = Int(event.rawValue) else { return }
		let generation = String(activity.rawValue.dropFirst((prefix + "meter.").count))
		try transaction { state in
			guard let policy = state.document?.home_allowance else { return }
			state.ledger.reset_if_needed(policy: policy, now: .now)
			state.ledger.checkpoint(generation: generation, minutes: minutes, at_home: state.at_home && state.enabled)
		}
		try reconcile()
	}
	private static func reconcile() throws {
		let prepared = try transaction { state -> (HomeState, Bool) in
			guard state.enabled, let policy = state.document?.home_allowance else { state.ledger.pause(); return (state, false) }
			state.ledger.reset_if_needed(policy: policy, now: .now)
			guard state.at_home, policy.allows(at: .now), state.ledger.used_minutes < state.ledger.budget(policy.rule(at: .now)?.allowance_minutes ?? 0) else { state.ledger.pause(); return (state, false) }
			let start = state.ledger.generation == nil
			if start { state.ledger.generation = UUID().uuidString; state.ledger.segment_base = state.ledger.used_minutes }
			return (state, start)
		}
		let state = prepared.0
		let stale = center.activities.filter { $0.rawValue.hasPrefix(prefix + "meter.") && $0.rawValue != prefix + "meter." + (state.ledger.generation ?? "") }
		if !stale.isEmpty { center.stopMonitoring(stale) }
		guard state.enabled, state.at_home, let document = state.document, let policy = document.home_allowance else { shield.clearAllSettings(); return }
		guard let generation = state.ledger.generation else { try SharedStore().apply_plan(for: document.id, to: shield); return }
		if prepared.1 {
			do {
				let shared = try SharedStore()
				let selection = try shared.resolved_selection(for: document.id, plan: shared.plan(for: document.id))
				guard SharedStore.count(selection) > 0 else { throw DocumentError.invalid("Choose your distraction apps first.") }
				let remaining = state.ledger.budget(policy.rule(at: .now)?.allowance_minutes ?? 0) - state.ledger.used_minutes
				guard remaining > 0 else { try transaction { $0.ledger.pause() }; try reconcile(); return }
				var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
				for minute in 1...remaining {
					events[DeviceActivityEvent.Name(String(minute))] = DeviceActivityEvent(applications: selection.applicationTokens, categories: selection.categoryTokens, webDomains: selection.webDomainTokens, threshold: DateComponents(minute: minute))
				}
				let now = Date(), end = policy.calendar.date(byAdding: .day, value: 1, to: policy.calendar.startOfDay(for: now))!.addingTimeInterval(-1)
				let components: Set<Calendar.Component> = [.timeZone, .year, .month, .day, .hour, .minute, .second]
				let schedule = DeviceActivitySchedule(intervalStart: policy.calendar.dateComponents(components, from: now), intervalEnd: policy.calendar.dateComponents(components, from: end), repeats: false)
				// The generation is persisted before IPC so callbacks can immediately read it.
				try center.startMonitoring(DeviceActivityName(prefix + "meter." + generation), during: schedule, events: events)
			} catch {
				try transaction { if $0.ledger.generation == generation { $0.ledger.pause() } }
				throw error
			}
		}
		let latest = try snapshot()
		if latest.enabled != state.enabled || latest.at_home != state.at_home || latest.ledger.generation != generation { try reconcile(); return }
		shield.clearAllSettings()
	}
}
