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
	// Set once the engine's own copy of the policy has been moved off the old "block outside the windows" behavior.
	var outside_migrated: Bool? = nil
	// Recent engine decisions, newest last, so a missed minute can be traced on the device.
	var log: [HomeLogEntry]? = nil
	mutating func note(_ text: String, at date: Date = .now) {
		var entries = log ?? []
		entries.append(HomeLogEntry(at: date.timeIntervalSince1970, text: text))
		log = Array(entries.suffix(40))
	}
}
struct HomeLogEntry: Codable, Equatable { var at: Double; var text: String }

// One shared file and a process lock serialize app/geofence and monitor-extension callbacks.
enum HomeEngine {
	static let prefix = "pocketwork.home."
	// iOS drops or throttles usage reports when a meter asks for one every minute (observed on device October 4),
	// so meters check in every five minutes, at the exact limit, and once more a minute later in case that report is lost.
	static let checkpoint_step = 5
	static func meter_thresholds(remaining: Int) -> [Int] {
		guard remaining > 0 else { return [] }
		return Array(stride(from: checkpoint_step, to: remaining, by: checkpoint_step)) + [remaining, remaining + 1]
	}
	static var center: DeviceActivityCenter { DeviceActivityCenter() }
	static var shield: ManagedSettingsStore { ManagedSettingsStore(named: ManagedSettingsStore.Name(prefix + "shield")) }
	private static func storage_folder() throws -> URL {
		guard let group = Bundle.main.object(forInfoDictionaryKey: "PocketworkAppGroup") as? String, let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw DocumentError.invalid("Home storage is unavailable.") }
		return folder
	}
	private static func transaction<T>(_ action: (inout HomeState) throws -> T) throws -> T {
		let folder = try storage_folder()
		return try HomeFileLock.with_lock(at: folder.appendingPathComponent("home.lock")) {
			let file = folder.appendingPathComponent("home-state.json")
			var state = FileManager.default.fileExists(atPath: file.path) ? try JSONDecoder().decode(HomeState.self, from: Data(contentsOf: file)) : HomeState()
			// The engine keeps its own copy of the routine from when it was switched on; apply the same one-time migration the library gets.
			if state.outside_migrated != true {
				if state.document?.home_allowance?.outside_windows == "block_at_home" { state.document?.home_allowance?.outside_windows = "unrestricted" }
				state.outside_migrated = true
			}
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
	static func note(_ text: String) { do { try transaction { $0.note(text) } } catch { /* Storage itself failed; the caller logs to OSLog. */ } }

	// Launch and foreground: re-evaluate the shield against the clock so a policy change (or the migration above) takes effect without a toggle.
	static func refresh_on_launch() throws {
		let state = try snapshot()
		guard state.enabled, let policy = state.document?.home_allowance else { return }
		// Builds before October 4 stopped every Pocketwork monitor whenever the app opened; put back whatever is missing.
		let registered = Set(center.activities.map(\.rawValue))
		if !clock_names(policy).allSatisfy(registered.contains) {
			center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(prefix + "clock.") || $0.rawValue == prefix + "midnight" })
			try start_clocks(policy)
			note("Restored the window schedule")
		}
		if let generation = state.ledger.generation, !registered.contains(prefix + "meter." + generation) {
			try transaction { state in if state.ledger.generation == generation { state.ledger.pause() } }
			note("Restarted counting after iOS lost the previous count")
		}
		try reconcile()
	}

	// One daily trigger per distinct window time (reconcile checks the weekday), which keeps the allowance well inside
	// iOS's 20-activity limit alongside scheduled routines. Windows never cross midnight.
	static func window_times(_ policy: HomePolicy) -> [HomeWindow] {
		var seen = Set<String>(), result: [HomeWindow] = []
		for rule in policy.rules { for window in rule.windows where seen.insert("\(window.start)-\(window.end)").inserted { result.append(window) } }
		return result
	}

	static func clock_name(_ window: HomeWindow) -> String {
		prefix + "clock." + window.start.replacingOccurrences(of: ":", with: "") + "-" + window.end.replacingOccurrences(of: ":", with: "")
	}

	static func clock_names(_ policy: HomePolicy) -> [String] { window_times(policy).map(clock_name) + [prefix + "midnight"] }

	private static func start_clocks(_ policy: HomePolicy) throws {
		for window in window_times(policy) {
			let start = ScheduleWindow.minutes(window.start)!, end = ScheduleWindow.minutes(window.end)!
			let schedule = DeviceActivitySchedule(intervalStart: DateComponents(timeZone: policy.calendar.timeZone, hour: start / 60, minute: start % 60), intervalEnd: DateComponents(timeZone: policy.calendar.timeZone, hour: end / 60, minute: end % 60), repeats: true)
			try center.startMonitoring(DeviceActivityName(clock_name(window)), during: schedule)
		}
		try center.startMonitoring(DeviceActivityName(prefix + "midnight"), during: DeviceActivitySchedule(intervalStart: DateComponents(timeZone: policy.calendar.timeZone, hour: 0, minute: 0), intervalEnd: DateComponents(timeZone: policy.calendar.timeZone, hour: 23, minute: 59), repeats: true))
	}
	static func set_home(_ place: HomePlace) throws {
		try transaction { $0.place = place; $0.at_home = false; $0.ledger.pause() }
		try reconcile()
	}
	static func location_changed(_ at_home: Bool) throws {
		try transaction { state in
			if state.at_home != at_home { state.ledger.pause(); state.note(at_home ? "Arrived home" : "Left home or location unknown") }
			state.at_home = at_home
		}
		try reconcile()
	}
	static func disable() throws {
		// Shields come off and monitoring stops even if the saved state cannot be written.
		defer {
			shield.clearAllSettings()
			center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(prefix) })
		}
		try transaction { $0.enabled = false; $0.ledger.pause() }
	}
	static func forget_account_data() throws {
		defer {
			shield.clearAllSettings()
			center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(prefix) })
		}
		try erase_saved_state(in: storage_folder())
	}
	static func erase_saved_state(in folder: URL) throws {
		try HomeFileLock.with_lock(at: folder.appendingPathComponent("home.lock")) {
			// Deletion must also work when the old file can no longer be decoded.
			try JSONEncoder().encode(HomeState()).write(to: folder.appendingPathComponent("home-state.json"), options: .atomic)
		}
	}
	static func configure(_ document: AppDocument, plan: SharedStore.ShieldPlan, enabled: Bool) throws {
		try document.validate()
		guard enabled else { try disable(); return }
		guard try snapshot().place != nil, AuthorizationCenter.shared.authorizationStatus == .approved else {
			// An allowance that can no longer run is switched off here too, so the engine never outlives the page's switch.
			try disable()
			throw DocumentError.invalid("Set your home and allow Screen Time access first.")
		}
		try SharedStore().save_plan(plan, for: document.id)
		try transaction { state in
			if state.document?.id != document.id { state.ledger = HomeLedger() }
			state.document = document; state.enabled = false; state.ledger.pause()
		}
		do {
			// DeviceActivity may synchronously launch the extension. Never hold home.lock across IPC.
			center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(prefix) })
			if let policy = document.home_allowance { try start_clocks(policy) }
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
			_ = try state.ledger.set_bonus(key, minutes: minutes)
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
			let before = state.ledger.used_minutes
			state.ledger.checkpoint(generation: generation, minutes: minutes, at_home: state.at_home && state.enabled)
			if state.ledger.used_minutes != before { state.note("iOS reported \(minutes) min since counting started; \(state.ledger.used_minutes) min used today") }
			else if !(state.at_home && state.enabled) { state.note("Ignored a \(minutes)-min report because you were away") }
			else if state.ledger.generation != generation { state.note("Ignored a \(minutes)-min report from an earlier count") }
		}
		try reconcile()
	}
	private static func reconcile() throws {
		let prepared = try transaction { state -> (HomeState, Bool) in
			guard state.enabled, let policy = state.document?.home_allowance else { state.ledger.pause(); return (state, false) }
			state.ledger.reset_if_needed(policy: policy, now: .now)
			let budget = state.ledger.budget(policy.rule(at: .now)?.allowance_minutes ?? 0)
			guard state.at_home, policy.allows(at: .now), state.ledger.used_minutes < budget else {
				if state.ledger.generation != nil { state.note(!state.at_home ? "Stopped counting: away" : !policy.allows(at: .now) ? "Stopped counting: window ended" : "Allowance used up; apps locked") }
				state.ledger.pause(); return (state, false)
			}
			let start = state.ledger.generation == nil
			if start { state.ledger.generation = UUID().uuidString; state.ledger.segment_base = state.ledger.used_minutes; state.note("Started counting: \(budget - state.ledger.used_minutes) min left") }
			return (state, start)
		}
		let state = prepared.0
		let stale = center.activities.filter { $0.rawValue.hasPrefix(prefix + "meter.") && $0.rawValue != prefix + "meter." + (state.ledger.generation ?? "") }
		if !stale.isEmpty { center.stopMonitoring(stale) }
		guard state.enabled, state.at_home, let document = state.document, let policy = document.home_allowance else { shield.clearAllSettings(); return }
		guard let generation = state.ledger.generation else {
			// No meter running: either the minutes are spent inside a window (block) or we are outside every window (leave the apps alone).
			if policy.allows(at: .now) || policy.blocks_outside { try SharedStore().apply_plan(for: document.id, to: shield) } else { shield.clearAllSettings() }
			return
		}
		if prepared.1 {
			do {
				let shared = try SharedStore()
				let selection = try shared.resolved_selection(for: document.id, plan: shared.plan(for: document.id))
				guard SharedStore.count(selection) > 0 else { throw DocumentError.invalid("Choose your distraction apps first.") }
				let remaining = state.ledger.budget(policy.rule(at: .now)?.allowance_minutes ?? 0) - state.ledger.used_minutes
				guard remaining > 0 else { try transaction { $0.ledger.pause() }; try reconcile(); return }
				var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
				for minute in meter_thresholds(remaining: remaining) {
					events[DeviceActivityEvent.Name(String(minute))] = DeviceActivityEvent(applications: selection.applicationTokens, categories: selection.categoryTokens, webDomains: selection.webDomainTokens, threshold: DateComponents(minute: minute))
				}
				let now = Date(), end = max(policy.calendar.date(byAdding: .day, value: 1, to: policy.calendar.startOfDay(for: now))!.addingTimeInterval(-1), now.addingTimeInterval(16 * 60))
				let components: Set<Calendar.Component> = [.timeZone, .year, .month, .day, .hour, .minute, .second]
				let schedule = DeviceActivitySchedule(intervalStart: policy.calendar.dateComponents(components, from: now), intervalEnd: policy.calendar.dateComponents(components, from: end), repeats: false)
				// The generation is persisted before IPC so callbacks can immediately read it.
				try center.startMonitoring(DeviceActivityName(prefix + "meter." + generation), during: schedule, events: events)
			} catch {
				try transaction { if $0.ledger.generation == generation { $0.ledger.pause() }; $0.note("Could not start counting: \(error.localizedDescription)") }
				throw error
			}
		}
		let latest = try snapshot()
		if latest.enabled != state.enabled || latest.at_home != state.at_home || latest.ledger.generation != generation { try reconcile(); return }
		shield.clearAllSettings()
	}
}
