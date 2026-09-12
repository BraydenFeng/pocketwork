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

	static let empty = ToolLibrary(schema_version: 1, tools: [])

	static func decode(_ data: Data) throws -> ToolLibrary {
		let library: ToolLibrary
		do { library = try JSONDecoder().decode(ToolLibrary.self, from: data) }
		catch { throw DocumentError.invalid("Your saved tools could not be opened. They have not been overwritten. \(error.localizedDescription)") }
		try library.validate()
		return library
	}

	func validate() throws {
		guard schema_version == 1 else { throw DocumentError.invalid("Your saved tools use a newer format than this version of the app understands.") }
		guard tools.count <= Self.max_tools else { throw DocumentError.invalid("Too many tools to open.") }
		var ids = Set<String>()
		for entry in tools {
			try entry.document.validate()
			guard ids.insert(entry.document.id).inserted else { throw DocumentError.invalid("Every tool needs a unique ID.") }
			guard entry.updated_date != nil else { throw DocumentError.invalid("A saved tool has an unreadable edit time.") }
		}
	}

	func encoded() throws -> Data {
		try validate()
		return try JSONEncoder().encode(self)
	}

	func find(_ id: String) -> AppDocument? { tools.first(where: { $0.document.id == id })?.document }

	var sorted: [LibraryEntry] { tools.sorted { $0.updated_at > $1.updated_at } }

	func upserting(_ document: AppDocument, now: Date) throws -> ToolLibrary {
		try document.validate()
		let entry = LibraryEntry(document: document, updated_at: Self.iso_formatter.string(from: now))
		var next = self
		if let index = next.tools.firstIndex(where: { $0.document.id == document.id }) {
			next.tools[index] = entry
		} else {
			guard next.tools.count < Self.max_tools else { throw DocumentError.invalid("You can keep up to \(Self.max_tools) tools. Delete one to add another.") }
			next.tools.append(entry)
		}
		return next
	}

	func deleting(_ id: String) -> ToolLibrary {
		var next = self
		next.tools.removeAll { $0.document.id == id }
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
		var parts: [String] = []
		if let minutes = document.focus_minutes { parts.append("\(minutes) min session") }
		if let schedule = document.schedule { parts.append(ScheduleWindow.describe(schedule)) }
		if document.rules.block_during_focus { parts.append("blocks apps") }
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
