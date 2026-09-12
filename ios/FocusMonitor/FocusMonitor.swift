import DeviceActivity
import Foundation
import ManagedSettings
import OSLog

final class FocusMonitor: DeviceActivityMonitor {
	private let logger = Logger(subsystem: "Pocketwork", category: "FocusMonitor")

	override func intervalDidStart(for activity: DeviceActivityName) {
		super.intervalDidStart(for: activity)
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
}
