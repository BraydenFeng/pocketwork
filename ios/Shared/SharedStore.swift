import FamilyControls
import Foundation
import ManagedSettings

struct SharedStore {
	static let settings_name = ManagedSettingsStore.Name("pocketwork.focus")
	private let defaults: UserDefaults

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

	func session() throws -> FocusSession? {
		guard let data = defaults.data(forKey: "focus_session") else { return nil }
		return try PropertyListDecoder().decode(FocusSession.self, from: data)
	}

	func save_session(_ session: FocusSession) throws {
		defaults.set(try PropertyListEncoder().encode(session), forKey: "focus_session")
	}

	func clear_session() { defaults.removeObject(forKey: "focus_session") }

	func apply_selection(for document_id: String) throws {
		let selection = try selection(for: document_id)
		let settings = ManagedSettingsStore(named: Self.settings_name)
		settings.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
		settings.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
		settings.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
		settings.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
	}
}
