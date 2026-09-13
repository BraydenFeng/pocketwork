import DeviceActivity
import Foundation
import ManagedSettings
import OSLog

final class FocusMonitor: DeviceActivityMonitor {
	private let logger = Logger(subsystem: "Pocketwork", category: "FocusMonitor")

	override func intervalDidStart(for activity: DeviceActivityName) {
		super.intervalDidStart(for: activity)
		if activity.rawValue.hasPrefix(HomeEngine.prefix) {
			if !activity.rawValue.hasPrefix(HomeEngine.prefix + "meter.") { do { try HomeEngine.clock_changed() } catch { logger.error("Home window failed: \(error.localizedDescription, privacy: .public)") } }
			return
		}
		if let routine_id = SharedStore.standing_id(from: activity) { standing_window_opened(routine_id); return }
		do {
			let shared = try SharedStore()
			guard let session = try shared.session(), session.activity_name == activity.rawValue else { return }
			if session.has_ended(at: .now) {
				ManagedSettingsStore(named: SharedStore.settings_name).clearAllSettings()
				shared.clear_session()
			} else if session.blocks_apps, try shared.plan(for: session.document_id)?.mode != .limit {
				try shared.apply_plan(for: session.document_id, to: ManagedSettingsStore(named: SharedStore.settings_name))
			}
		} catch {
			logger.error("Unable to start focus monitoring: \(error.localizedDescription, privacy: .public)")
			ManagedSettingsStore(named: SharedStore.settings_name).clearAllSettings()
		}
	}

	override func intervalDidEnd(for activity: DeviceActivityName) {
		super.intervalDidEnd(for: activity)
		if activity.rawValue.hasPrefix(HomeEngine.prefix) { do { try HomeEngine.clock_changed() } catch { logger.error("Home window failed: \(error.localizedDescription, privacy: .public)") }; return }
		if let routine_id = SharedStore.standing_id(from: activity) { SharedStore.standing_store(routine_id).clearAllSettings(); return }
		do {
			let shared = try SharedStore()
			guard let session = try shared.session(), session.activity_name == activity.rawValue, session.has_ended(at: .now) else { return }
			ManagedSettingsStore(named: SharedStore.settings_name).clearAllSettings()
			shared.clear_session()
		} catch {
			logger.error("Unable to complete focus monitoring: \(error.localizedDescription, privacy: .public)")
			ManagedSettingsStore(named: SharedStore.settings_name).clearAllSettings()
		}
	}

	// A standing routine's window opened. Shield only if the person still has it switched on; otherwise fail safe and clear.
	// A limit plan waits for the usage threshold instead of shielding at the start.
	private func standing_window_opened(_ routine_id: String) {
		let store = SharedStore.standing_store(routine_id)
		do {
			let shared = try SharedStore()
			guard shared.standing_ids().contains(routine_id) else { store.clearAllSettings(); return }
			if try shared.plan(for: routine_id)?.mode == .limit { store.clearAllSettings(); return }
			try shared.apply_plan(for: routine_id, to: store)
		} catch {
			logger.error("Unable to apply a scheduled routine: \(error.localizedDescription, privacy: .public)")
			store.clearAllSettings()
		}
	}

	// A limited group used up its minutes inside the window: lock it for the rest of the window.
	override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
		super.eventDidReachThreshold(event, activity: activity)
		if activity.rawValue.hasPrefix(HomeEngine.prefix) { do { try HomeEngine.reached(event, activity: activity) } catch { logger.error("Home checkpoint failed: \(error.localizedDescription, privacy: .public)") }; return }
		do {
			let shared = try SharedStore()
			if let routine_id = SharedStore.standing_id(from: activity) {
				guard shared.standing_ids().contains(routine_id) else { return }
				try shared.apply_plan(for: routine_id, to: SharedStore.standing_store(routine_id))
			} else if let session = try shared.session(), session.activity_name == activity.rawValue, !session.has_ended(at: .now) {
				try shared.apply_plan(for: session.document_id, to: ManagedSettingsStore(named: SharedStore.settings_name))
			}
		} catch {
			logger.error("Unable to apply a limit: \(error.localizedDescription, privacy: .public)")
		}
	}
}
