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
		try result.validate()
		return result
	}
}
