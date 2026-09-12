import DeviceActivity
import Foundation
import ManagedSettings
import OSLog

final class FocusMonitor: DeviceActivityMonitor {
	private let logger = Logger(subsystem: "Pocketwork", category: "FocusMonitor")

	override func intervalDidStart(for activity: DeviceActivityName) {
		super.intervalDidStart(for: activity)
		if let routine_id = SharedStore.standing_id(from: activity) { standing_window_opened(routine_id); return }
		do {
			let shared = try SharedStore()
			guard let session = try shared.session(), session.activity_name == activity.rawValue else { return }
			if session.has_ended(at: .now) {
				ManagedSettingsStore(named: SharedStore.settings_name).clearAllSettings()
				shared.clear_session()
			} else if session.blocks_apps {
				try shared.apply_selection(for: session.document_id)
			}
		} catch {
			logger.error("Unable to start focus monitoring: \(error.localizedDescription, privacy: .public)")
			ManagedSettingsStore(named: SharedStore.settings_name).clearAllSettings()
		}
	}

	override func intervalDidEnd(for activity: DeviceActivityName) {
		super.intervalDidEnd(for: activity)
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
	private func standing_window_opened(_ routine_id: String) {
		let store = SharedStore.standing_store(routine_id)
		do {
			let shared = try SharedStore()
			guard shared.standing_ids().contains(routine_id) else { store.clearAllSettings(); return }
			try shared.apply_selection(for: routine_id, to: store)
		} catch {
			logger.error("Unable to apply a scheduled routine: \(error.localizedDescription, privacy: .public)")
			store.clearAllSettings()
		}
	}
}
