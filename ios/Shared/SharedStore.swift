import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

struct SharedStore {
	static let settings_name = ManagedSettingsStore.Name("pocketwork.focus")
	static let standing_prefix = "pocketwork.standing."
	private let defaults: UserDefaults

	// Each standing routine shields through its own store so two active routines never clear each other.
	static func standing_store(_ document_id: String) -> ManagedSettingsStore {
		ManagedSettingsStore(named: ManagedSettingsStore.Name(standing_prefix + document_id))
	}

	static func standing_activity(_ document_id: String, weekday: Int) -> DeviceActivityName {
		DeviceActivityName("\(standing_prefix)\(document_id).\(weekday)")
	}

	// "pocketwork.standing.<id>.<weekday>" → id. Routine IDs never contain dots.
	static func standing_id(from activity: DeviceActivityName) -> String? {
		guard activity.rawValue.hasPrefix(standing_prefix) else { return nil }
		let rest = activity.rawValue.dropFirst(standing_prefix.count)
		guard let dot = rest.lastIndex(of: ".") else { return nil }
		return String(rest[..<dot])
	}

	init() throws {
		guard let group = Bundle.main.object(forInfoDictionaryKey: "PocketworkAppGroup") as? String,
			FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil,
			let defaults = UserDefaults(suiteName: group) else {
			throw DocumentError.invalid("App Group is not configured. Set the same registered App Group on the host and monitor extension.")
		}
		self.defaults = defaults
	}

	// Each tool keeps its own private app selection; the tokens never leave this App Group.
	private func selection_key(_ document_id: String) -> String { "selected_activities.\(document_id)" }

	func selection(for document_id: String) throws -> FamilyActivitySelection {
		guard let data = defaults.data(forKey: selection_key(document_id)) else { return FamilyActivitySelection() }
		return try PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
	}

	func save_selection(_ selection: FamilyActivitySelection, for document_id: String) throws {
		defaults.set(try PropertyListEncoder().encode(selection), forKey: selection_key(document_id))
	}

	func remove_selection(for document_id: String) { defaults.removeObject(forKey: selection_key(document_id)) }

	// Which standing routines are switched on, so the monitor extension ignores callbacks from routines that were turned off.
	func standing_ids() -> Set<String> { Set(defaults.stringArray(forKey: "standing_routines") ?? []) }

	func set_standing(_ document_id: String, enabled: Bool) {
		var ids = standing_ids()
		if enabled { ids.insert(document_id) } else { ids.remove(document_id) }
		defaults.set(Array(ids).sorted(), forKey: "standing_routines")
	}

	func session() throws -> FocusSession? {
		guard let data = defaults.data(forKey: "focus_session") else { return nil }
		return try PropertyListDecoder().decode(FocusSession.self, from: data)
	}

	func save_session(_ session: FocusSession) throws {
		defaults.set(try PropertyListEncoder().encode(session), forKey: "focus_session")
	}

	func clear_session() { defaults.removeObject(forKey: "focus_session") }

	func apply_selection(for document_id: String, to settings: ManagedSettingsStore = ManagedSettingsStore(named: SharedStore.settings_name)) throws {
		let selection = try selection(for: document_id)
		settings.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
		settings.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
		settings.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
		settings.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
	}
}
