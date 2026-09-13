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
		let descriptor = open(folder.appendingPathComponent("home.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
		guard descriptor >= 0 else { throw DocumentError.invalid("Could not open the home allowance lock.") }
		defer { close(descriptor) }
		guard flock(descriptor, LOCK_EX) == 0 else { throw DocumentError.invalid("Could not lock the home allowance.") }
		defer { flock(descriptor, LOCK_UN) }
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
	static func snapshot() throws -> HomeState { try transaction { $0 } }
	static func set_home(_ place: HomePlace) throws { try transaction { $0.place = place; $0.at_home = false; try apply(&$0) } }
	static func location_changed(_ at_home: Bool) throws { try transaction { state in
		if state.at_home != at_home { state.ledger.pause(); stop_meter() }
		state.at_home = at_home; try apply(&state)
	} }
	static func disable() throws {
		try transaction { $0.enabled = false; $0.ledger.pause(); center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(prefix) }); shield.clearAllSettings() }
	}
	static func configure(_ document: AppDocument, plan: SharedStore.ShieldPlan, enabled: Bool) throws {
		try document.validate()
		try transaction { state in
			if enabled { guard state.place != nil, AuthorizationCenter.shared.authorizationStatus == .approved else { throw DocumentError.invalid("Set your home and allow Screen Time access first.") } }
			if state.document?.id != document.id { state.ledger = HomeLedger() }
			state.document = document; state.enabled = enabled
			try SharedStore().save_plan(plan, for: document.id)
			center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(prefix) }); state.ledger.pause()
			do {
				if enabled, let policy = document.home_allowance {
					for rule in policy.rules { for day in rule.days { for (index, window) in rule.windows.enumerated() {
						let start = ScheduleWindow.minutes(window.start)!, end = ScheduleWindow.minutes(window.end)!
						let schedule = DeviceActivitySchedule(intervalStart: DateComponents(timeZone: policy.calendar.timeZone, hour: start / 60, minute: start % 60, weekday: day), intervalEnd: DateComponents(timeZone: policy.calendar.timeZone, hour: end / 60, minute: end % 60, weekday: day), repeats: true)
						try center.startMonitoring(DeviceActivityName(prefix + "clock.\(day).\(index)"), during: schedule)
					} } }
					try center.startMonitoring(DeviceActivityName(prefix + "midnight"), during: DeviceActivitySchedule(intervalStart: DateComponents(timeZone: policy.calendar.timeZone, hour: 0, minute: 0), intervalEnd: DateComponents(timeZone: policy.calendar.timeZone, hour: 23, minute: 59), repeats: true))
				}
				try apply(&state)
			} catch { state.enabled = false; center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(prefix) }); shield.clearAllSettings(); throw error }
		}
	}
	static func clock_changed() throws { try transaction { try apply(&$0) } }
	static func reached(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) throws {
		guard activity.rawValue.hasPrefix(prefix + "meter."), let minutes = Int(event.rawValue) else { return }
		let generation = String(activity.rawValue.dropFirst((prefix + "meter.").count))
		try transaction { state in
			guard let policy = state.document?.home_allowance else { return }
			state.ledger.reset_if_needed(policy: policy, now: .now)
			state.ledger.checkpoint(generation: generation, minutes: minutes, at_home: state.at_home && state.enabled)
			try apply(&state)
		}
	}
	private static func stop_meter() { center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(prefix + "meter.") }) }
	private static func apply(_ state: inout HomeState) throws {
		guard state.enabled, let document = state.document, let policy = document.home_allowance else { stop_meter(); state.ledger.pause(); shield.clearAllSettings(); return }
		state.ledger.reset_if_needed(policy: policy, now: .now)
		guard state.at_home else { stop_meter(); state.ledger.pause(); shield.clearAllSettings(); return }
		let allowance = policy.rule(at: .now)?.allowance_minutes ?? 0
		guard policy.allows(at: .now), state.ledger.used_minutes < allowance else {
			stop_meter(); state.ledger.pause(); try SharedStore().apply_plan(for: document.id, to: shield); return
		}
		if state.ledger.generation == nil {
			let shared = try SharedStore()
			let selection = try shared.resolved_selection(for: document.id, plan: shared.plan(for: document.id))
			guard SharedStore.count(selection) > 0 else { throw DocumentError.invalid("Choose your distraction apps first.") }
			let generation = UUID().uuidString
			let remaining = allowance - state.ledger.used_minutes
			var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
			for minute in 1...remaining {
				events[DeviceActivityEvent.Name(String(minute))] = DeviceActivityEvent(applications: selection.applicationTokens, categories: selection.categoryTokens, webDomains: selection.webDomainTokens, threshold: DateComponents(minute: minute))
			}
			// A fresh non-repeating activity starts counting now; past/away usage is excluded.
			let now = Date(), end = policy.calendar.date(byAdding: .day, value: 1, to: policy.calendar.startOfDay(for: now))!.addingTimeInterval(-1)
			let components: Set<Calendar.Component> = [.timeZone, .year, .month, .day, .hour, .minute, .second]
			let schedule = DeviceActivitySchedule(intervalStart: policy.calendar.dateComponents(components, from: now), intervalEnd: policy.calendar.dateComponents(components, from: end), repeats: false)
			try center.startMonitoring(DeviceActivityName(prefix + "meter." + generation), during: schedule, events: events)
			state.ledger.generation = generation; state.ledger.segment_base = state.ledger.used_minutes
		}
		shield.clearAllSettings()
	}
}
