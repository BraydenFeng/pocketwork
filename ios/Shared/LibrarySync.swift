import Foundation

extension ToolLibrary {
	func merging(_ remote: ToolLibrary, now: Date = .now) throws -> ToolLibrary {
		var tombstones = removed ?? [:]
		for (id, stamp) in remote.removed ?? [:] { tombstones[id] = max(tombstones[id] ?? "", stamp) }
		var entries: [String: LibraryEntry] = [:]
		for entry in tools + remote.tools {
			if entries[entry.id] == nil || entry.updated_at > entries[entry.id]!.updated_at { entries[entry.id] = entry }
		}
		var result = ToolLibrary.empty
		for entry in entries.values {
			if let stamp = tombstones[entry.id], stamp >= entry.updated_at { continue }
			tombstones.removeValue(forKey: entry.id)
			result.tools.append(entry)
		}
		result.tools.sort { $0.id < $1.id }
		let horizon = Self.iso_formatter.string(from: now.addingTimeInterval(-30 * 86400))
		result.removed = tombstones.filter { $0.value >= horizon }
		if result.removed?.isEmpty == true { result.removed = nil }
		if groups_updated_at != nil || remote.groups_updated_at != nil {
			let source = (groups_updated_at ?? "") > (remote.groups_updated_at ?? "") ? self : remote
			result.groups = source.groups ?? []
			result.groups_updated_at = source.groups_updated_at
		} else {
			var known_ids = Set<String>(), names = Set<String>()
			result.groups = ((groups ?? []) + (remote.groups ?? [])).filter { group in
				guard !known_ids.contains(group.id), !names.contains(group.name.lowercased()) else { return false }
				known_ids.insert(group.id); names.insert(group.name.lowercased()); return true
			}.sorted { $0.id < $1.id }
			if result.groups?.isEmpty == true { result.groups = nil }
		}
		// Groups added on two devices at once: keep any group a merged page still names, from whichever side has it.
		for name in result.tools.flatMap({ $0.document.referenced_groups }) where result.group(named: name) == nil {
			guard let group = (groups ?? []).first(where: { $0.name.lowercased() == name.lowercased() }) ?? (remote.groups ?? []).first(where: { $0.name.lowercased() == name.lowercased() }), result.group(id: group.id) == nil else { continue }
			result.groups = (result.groups ?? []) + [group]
		}
		// App choices merge per group by their own stamp, so a rename on one device cannot wipe apps picked on another.
		var newest: [String: AppGroup] = [:]
		for group in (groups ?? []) + (remote.groups ?? []) {
			guard let stamp = group.apps_updated_at, stamp > (newest[group.id]?.apps_updated_at ?? "") else { continue }
			newest[group.id] = group
		}
		result.groups = result.groups?.map { group in
			guard let best = newest[group.id], (group.apps_updated_at ?? "") < (best.apps_updated_at ?? "") else { return group }
			var updated = group
			updated.apps = best.apps
			updated.apps_updated_at = best.apps_updated_at
			return updated
		}
		try result.validate()
		return result
	}
}
