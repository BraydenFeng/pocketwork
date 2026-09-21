import FamilyControls
import Foundation
import ManagedSettings

enum BuilderAppRules {
	private static var shield: ManagedSettingsStore { ManagedSettingsStore(named: ManagedSettingsStore.Name("pocketwork.builder.apps")) }
	private static func update(reset: Bool = false, _ edit: (inout [String: FamilyActivitySelection]) throws -> Void) throws {
		guard let group = Bundle.main.object(forInfoDictionaryKey: "PocketworkAppGroup") as? String, let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw DocumentError.invalid("App rule storage is unavailable.") }
		let selections = try HomeFileLock.with_lock(at: folder.appendingPathComponent("builder-apps.lock")) { () -> [String: FamilyActivitySelection] in
			let file = folder.appendingPathComponent("builder-apps.json")
			var rules = !reset && FileManager.default.fileExists(atPath: file.path) ? try JSONDecoder().decode([String: FamilyActivitySelection].self, from: Data(contentsOf: file)) : [:]
			try edit(&rules); try JSONEncoder().encode(rules).write(to: file, options: .atomic); return rules
		}
		var merged = FamilyActivitySelection()
		for selection in selections.values { merged.applicationTokens.formUnion(selection.applicationTokens); merged.categoryTokens.formUnion(selection.categoryTokens); merged.webDomainTokens.formUnion(selection.webDomainTokens) }
		shield.shield.applications = merged.applicationTokens.isEmpty ? nil : merged.applicationTokens
		shield.shield.webDomains = merged.webDomainTokens.isEmpty ? nil : merged.webDomainTokens
		shield.shield.applicationCategories = merged.categoryTokens.isEmpty ? nil : .specific(merged.categoryTokens)
		shield.shield.webDomainCategories = merged.categoryTokens.isEmpty ? nil : .specific(merged.categoryTokens)
	}
	static func set(document: String, node: String, active: Bool, names: [String], groups: [AppGroup]) throws {
		guard !active || AuthorizationCenter.shared.authorizationStatus == .approved else { throw DocumentError.invalid("Allow Screen Time access first.") }
		var selection = FamilyActivitySelection()
		if active {
			let shared = try SharedStore()
			for name in names {
				guard let group = groups.first(where: { $0.name.lowercased() == name.lowercased() }) else { throw DocumentError.invalid("Create the app group “" + name + "” first.") }
				let part = try shared.group_selection(group.id)
				guard SharedStore.count(part) > 0 else { throw DocumentError.invalid("Choose apps for “" + name + "” first.") }
				selection.applicationTokens.formUnion(part.applicationTokens); selection.categoryTokens.formUnion(part.categoryTokens); selection.webDomainTokens.formUnion(part.webDomainTokens)
			}
		}
		try update { rules in let key = document + "." + node; if active { rules[key] = selection } else { rules.removeValue(forKey: key) } }
	}
	static func prune(document: String, nodes: Set<String>) throws { try update { rules in rules = rules.filter { !$0.key.hasPrefix(document + ".") || nodes.contains(String($0.key.dropFirst(document.count + 1))) } } }
	static func clear() throws {
		defer { shield.clearAllSettings() }
		try update(reset: true) { $0 = [:] }
	}
}
