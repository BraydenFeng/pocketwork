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

	// Routines without groups keep their own private app selection; groups keep theirs under a separate prefix. Tokens never leave this App Group.
	private func selection_key(_ document_id: String) -> String { "selected_activities.\(document_id)" }
	private func group_key(_ group_id: String) -> String { "group_activities.\(group_id)" }

	func group_selection(_ group_id: String) throws -> FamilyActivitySelection {
		guard let data = defaults.data(forKey: group_key(group_id)) else { return FamilyActivitySelection() }
		return try PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
	}

	func save_group_selection(_ selection: FamilyActivitySelection, for group_id: String) throws {
		defaults.set(try PropertyListEncoder().encode(selection), forKey: group_key(group_id))
	}

	func remove_group_selection(_ group_id: String) { defaults.removeObject(forKey: group_key(group_id)) }

	// What a running routine does to which apps, written when it starts so the monitor extension needs no library.
	struct ShieldPlan: Codable, Equatable {
		var mode: ShieldMode
		var group_ids: [String]
		var limit_minutes: Int?
	}

	private func plan_key(_ document_id: String) -> String { "shield_plan.\(document_id)" }

	func plan(for document_id: String) throws -> ShieldPlan? {
		guard let data = defaults.data(forKey: plan_key(document_id)) else { return nil }
		return try PropertyListDecoder().decode(ShieldPlan.self, from: data)
	}

	func save_plan(_ plan: ShieldPlan, for document_id: String) throws {
		defaults.set(try PropertyListEncoder().encode(plan), forKey: plan_key(document_id))
	}

	func remove_plan(for document_id: String) { defaults.removeObject(forKey: plan_key(document_id)) }

	// Everything the plan points at, merged. Falls back to the routine's own selection when it names no groups.
	func resolved_selection(for document_id: String, plan: ShieldPlan?) throws -> FamilyActivitySelection {
		guard let plan, !plan.group_ids.isEmpty else { return try selection(for: document_id) }
		var merged = FamilyActivitySelection()
		for group_id in plan.group_ids {
			let part = try group_selection(group_id)
			merged.applicationTokens.formUnion(part.applicationTokens)
			merged.categoryTokens.formUnion(part.categoryTokens)
			merged.webDomainTokens.formUnion(part.webDomainTokens)
		}
		return merged
	}

	static func count(_ selection: FamilyActivitySelection) -> Int {
		selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
	}

	// Applies the routine's plan to a store: block locks the selection, allow_only locks everything else, limit locks the selection (called once the threshold is hit).
	func apply_plan(for document_id: String, to settings: ManagedSettingsStore) throws {
		let plan = try plan(for: document_id)
		let selection = try resolved_selection(for: document_id, plan: plan)
		if plan?.mode == .allow_only {
			settings.shield.applications = nil
			settings.shield.webDomains = nil
			settings.shield.applicationCategories = .all(except: selection.applicationTokens)
			settings.shield.webDomainCategories = .all(except: selection.webDomainTokens)
		} else {
			settings.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
			settings.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
			settings.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
			settings.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
		}
	}

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
