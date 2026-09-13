import Foundation

// Same shape as pocketwork.library.v1 in the web editor, so a library can move between the two unchanged.
struct LibraryEntry: Codable, Equatable, Identifiable {
	var document: AppDocument
	var updated_at: String

	var id: String { document.id }
	var updated_date: Date? { ToolLibrary.iso_formatter.date(from: updated_at) }
}

struct ToolLibrary: Codable, Equatable {
	static let max_tools = 50
	static let iso_formatter: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter
	}()

	var schema_version: Int
	var tools: [LibraryEntry]
	// Deletions remembered (id → when) so a routine deleted on one device does not come back from another.
	var removed: [String: String]?
	// App groups are named here and shared by every routine; which apps are in them is set on each phone.
	var groups: [AppGroup]?
	var groups_updated_at: String? = nil

	static let empty = ToolLibrary(schema_version: 1, tools: [], removed: nil, groups: nil)
	static let max_groups = 20

	static func decode(_ data: Data) throws -> ToolLibrary {
		let library: ToolLibrary
		do { library = try JSONDecoder().decode(ToolLibrary.self, from: data) }
		catch { throw DocumentError.invalid("Your saved tools could not be opened. They have not been overwritten. \(error.localizedDescription)") }
		try library.validate()
		return library
	}

	func validate() throws {
		guard tools.filter({ $0.document.home_allowance != nil }).count <= 1 else { throw DocumentError.invalid("Only one home allowance can run on this iPhone.") }
		guard schema_version == 1 else { throw DocumentError.invalid("Your saved tools use a newer format than this version of the app understands.") }
		guard tools.count <= Self.max_tools else { throw DocumentError.invalid("Too many tools to open.") }
		var ids = Set<String>()
		for entry in tools {
			try entry.document.validate()
			guard ids.insert(entry.document.id).inserted else { throw DocumentError.invalid("Every tool needs a unique ID.") }
			guard entry.updated_date != nil else { throw DocumentError.invalid("A saved tool has an unreadable edit time.") }
		}
		var names = Set<String>()
		for group in groups ?? [] {
			try AppDocument.validate_id(group.id)
			guard !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, group.name.utf16.count <= 40 else { throw DocumentError.invalid("An app group has an empty or overlong name.") }
			guard names.insert(group.name.lowercased()).inserted else { throw DocumentError.invalid("Two app groups are called \"\(group.name)\".") }
		}
		guard (groups ?? []).count <= Self.max_groups else { throw DocumentError.invalid("Too many app groups to open.") }
	}

	func encoded() throws -> Data {
		try validate()
		return try JSONEncoder().encode(self)
	}

	func find(_ id: String) -> AppDocument? { tools.first(where: { $0.document.id == id })?.document }

	func group(named name: String) -> AppGroup? { (groups ?? []).first { $0.name.lowercased() == name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } }
	func group(id: String) -> AppGroup? { (groups ?? []).first { $0.id == id } }
	func routines_using(group name: String) -> [AppDocument] { tools.map(\.document).filter { $0.referenced_groups.contains { $0.lowercased() == name.lowercased() } } }

	func adding_group(_ raw_name: String) throws -> ToolLibrary {
		let name = raw_name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !name.isEmpty, name.utf16.count <= 40 else { throw DocumentError.invalid("Group names are 1 to 40 characters.") }
		guard group(named: name) == nil else { throw DocumentError.invalid("There is already an app group called \"\(name)\".") }
		guard (groups ?? []).count < Self.max_groups else { throw DocumentError.invalid("You can have up to \(Self.max_groups) app groups.") }
		var next = self
		next.groups_updated_at = Self.iso_formatter.string(from: .now)
		next.groups = (groups ?? []) + [AppGroup(id: UUID().uuidString, name: name)]
		return next
	}

	// Renaming follows through to every routine that mentions the group, so nothing silently stops matching.
	func renaming_group(_ id: String, to raw_name: String, now: Date) throws -> ToolLibrary {
		let name = raw_name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let old = group(id: id) else { throw DocumentError.invalid("That app group no longer exists.") }
		guard !name.isEmpty, name.utf16.count <= 40 else { throw DocumentError.invalid("Group names are 1 to 40 characters.") }
		if let clash = group(named: name), clash.id != id { throw DocumentError.invalid("There is already an app group called \"\(name)\".") }
		var next = self
		next.groups_updated_at = Self.iso_formatter.string(from: now)
		next.groups = (groups ?? []).map { $0.id == id ? AppGroup(id: id, name: name) : $0 }
		next.tools = tools.map { entry in
			guard entry.document.referenced_groups.contains(where: { $0.lowercased() == old.name.lowercased() }) else { return entry }
			var document = entry.document
			document.blocks = document.blocks.map { block in
				guard block.type == .screen_time else { return block }
				var copy = block
				copy.groups = block.group_names.map { $0.lowercased() == old.name.lowercased() ? name : $0 }
				return copy
			}
			return LibraryEntry(document: document, updated_at: Self.iso_formatter.string(from: now))
		}
		return next
	}

	func removing_group(_ id: String) throws -> ToolLibrary {
		guard let old = group(id: id) else { return self }
		let users = routines_using(group: old.name)
		guard users.isEmpty else { throw DocumentError.invalid("\"\(old.name)\" is used by \(users.map { "\"\($0.name)\"" }.joined(separator: ", ")). Take it out of those routines first.") }
		var next = self
		let remaining = (groups ?? []).filter { $0.id != id }
		next.groups_updated_at = Self.iso_formatter.string(from: .now)
		next.groups = remaining
		return next
	}

	// Routines can mention groups that do not exist yet (an import, or an agent naming a new one); they get created empty.
	func ensuring_groups(for document: AppDocument) throws -> ToolLibrary {
		var next = self
		for name in document.referenced_groups where next.group(named: name) == nil { next = try next.adding_group(name) }
		return next
	}

	var sorted: [LibraryEntry] { tools.sorted { $0.updated_at > $1.updated_at } }

	func upserting(_ document: AppDocument, now: Date) throws -> ToolLibrary {
		try document.validate()
		let entry = LibraryEntry(document: document, updated_at: Self.iso_formatter.string(from: now))
		var next = try ensuring_groups(for: document)
		if let index = next.tools.firstIndex(where: { $0.document.id == document.id }) {
			next.tools[index] = entry
		} else {
			guard next.tools.count < Self.max_tools else { throw DocumentError.invalid("You can keep up to \(Self.max_tools) tools. Delete one to add another.") }
			next.tools.append(entry)
		}
		return next
	}

	func deleting(_ id: String, now: Date = .now) -> ToolLibrary {
		var next = self
		next.tools.removeAll { $0.document.id == id }
		var tombstones = removed ?? [:]
		tombstones[id] = Self.iso_formatter.string(from: now)
		next.removed = tombstones
		return next
	}

	func duplicating(_ id: String, now: Date) throws -> (library: ToolLibrary, document: AppDocument) {
		guard var copy = find(id) else { throw DocumentError.invalid("That tool no longer exists.") }
		copy.id = UUID().uuidString
		copy.name = String("\(copy.name) copy".prefix(80))
		return (try upserting(copy, now: now), copy)
	}

	// Imported files keep their content but never collide with a tool already in the library.
	func importing(_ document: AppDocument, now: Date) throws -> (library: ToolLibrary, document: AppDocument) {
		var next_document = document
		if find(document.id) != nil { next_document.id = UUID().uuidString }
		return (try upserting(next_document, now: now), next_document)
	}
}

// Plain-language card copy, matching summarize_tool and format_edited in the web editor.
enum ToolCopy {
	static func summary(_ document: AppDocument) -> String {
		if document.home_allowance != nil { return "Home only · shared daily distraction allowance" }
		var parts: [String] = []
		if let minutes = document.focus_minutes { parts.append("\(minutes) min session") }
		if let schedule = document.schedule { parts.append(ScheduleWindow.describe(schedule)) }
		if document.rules.block_during_focus, let shield = document.shield {
			// Lowercase the verb, never a group name: "blocks Social", "only Work", but "Work · 45 min limit".
			let words = shield.shield_description
			if shield.group_names.isEmpty { parts.append("blocks apps") }
			else if words.hasPrefix("Blocks ") || words.hasPrefix("Only ") { parts.append(words.prefix(1).lowercased() + words.dropFirst()) }
			else { parts.append(words) }
		}
		let tasks = document.blocks.compactMap(\.items).reduce(0) { $0 + $1.count }
		if tasks > 0 { parts.append("\(tasks) task\(tasks == 1 ? "" : "s")") }
		let counters = document.blocks.filter { $0.type == .counter }.count
		if counters > 0 { parts.append("\(counters) counter\(counters == 1 ? "" : "s")") }
		if parts.isEmpty { return "\(document.blocks.count) block\(document.blocks.count == 1 ? "" : "s")" }
		return parts.joined(separator: " · ")
	}

	static func edited(_ entry: LibraryEntry, now: Date) -> String {
		guard let date = entry.updated_date else { return "Edited" }
		let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
		if minutes < 1 { return "Edited just now" }
		if minutes < 60 { return "Edited \(minutes) min ago" }
		let hours = minutes / 60
		if hours < 24 { return "Edited \(hours) hr ago" }
		let days = hours / 24
		return days == 1 ? "Edited yesterday" : "Edited \(days) days ago"
	}
}
