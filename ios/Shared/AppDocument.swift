import Foundation

enum DocumentError: LocalizedError {
	case invalid(String)
	var errorDescription: String? {
		switch self { case .invalid(let message): return message }
	}
}

struct TaskDocument: Codable, Identifiable, Equatable {
	var id: String
	var text: String
}

enum BlockKind: String, Codable {
	case heading, timer, checklist, counter, note, screen_time
}

struct BlockDocument: Codable, Identifiable, Equatable {
	var id: String
	var type: BlockKind
	var title: String
	var subtitle: String?
	var minutes: Int?
	var items: [TaskDocument]?
	var target: Int?
	var text: String?

	// Mirrors create_block in lib/document.ts so a block added on the phone matches one added in the browser.
	static func make(_ kind: BlockKind) -> BlockDocument {
		let id = UUID().uuidString
		switch kind {
		case .heading: return BlockDocument(id: id, type: kind, title: "Make room for what matters.", subtitle: "A little space, just for you.", minutes: nil, items: nil, target: nil, text: nil)
		case .timer: return BlockDocument(id: id, type: kind, title: "Focus session", subtitle: nil, minutes: 25, items: nil, target: nil, text: nil)
		case .checklist: return BlockDocument(id: id, type: kind, title: "On my list", subtitle: nil, minutes: nil, items: [TaskDocument(id: UUID().uuidString, text: "My first task")], target: nil, text: nil)
		case .counter: return BlockDocument(id: id, type: kind, title: "Small wins", subtitle: nil, minutes: nil, items: nil, target: 5, text: nil)
		case .note: return BlockDocument(id: id, type: kind, title: "A note to myself", subtitle: nil, minutes: nil, items: nil, target: nil, text: "One thing at a time.")
		case .screen_time: return BlockDocument(id: id, type: kind, title: "Fewer distractions", subtitle: nil, minutes: nil, items: nil, target: nil, text: nil)
		}
	}
}

struct RuleDocument: Codable, Equatable {
	var block_during_focus: Bool
	var notify_on_complete: Bool
}

struct AppDocument: Codable, Equatable {
	var schema_version: Int
	var id: String
	var name: String
	var description: String
	var blocks: [BlockDocument]
	var rules: RuleDocument

	var focus_minutes: Int? { blocks.first(where: { $0.type == .timer })?.minutes }
	var has_timer: Bool { blocks.contains(where: { $0.type == .timer }) }
	var has_screen_time: Bool { blocks.contains(where: { $0.type == .screen_time }) }

	static func blank() -> AppDocument {
		AppDocument(schema_version: 1, id: UUID().uuidString, name: "My new tool", description: "", blocks: [BlockDocument.make(.heading)], rules: RuleDocument(block_during_focus: false, notify_on_complete: false))
	}

	// Rules that depend on a removed block are switched off rather than left invalid, as remove_block does in the editor.
	func removing_block(_ block_id: String) -> AppDocument {
		guard blocks.count > 1 else { return self }
		var next = self
		next.blocks.removeAll { $0.id == block_id }
		next.rules.block_during_focus = rules.block_during_focus && next.has_timer && next.has_screen_time
		next.rules.notify_on_complete = rules.notify_on_complete && next.has_timer
		return next
	}

	func can_add(_ kind: BlockKind) -> Bool {
		guard blocks.count < 20 else { return false }
		if kind == .timer || kind == .screen_time { return !blocks.contains(where: { $0.type == kind }) }
		return true
	}

	static func decode(_ data: Data) throws -> AppDocument {
		guard data.count <= 100_000 else { throw DocumentError.invalid("This tool exceeds the 100 KB limit.") }
		guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw DocumentError.invalid("This file is not a Pocketwork configuration.")
		}
		try require_keys(object, ["schema_version", "id", "name", "description", "blocks", "rules"])
		guard let raw_blocks = object["blocks"] as? [[String: Any]], let raw_rules = object["rules"] as? [String: Any] else {
			throw DocumentError.invalid("The tool is missing its blocks or rules.")
		}
		try require_keys(raw_rules, ["block_during_focus", "notify_on_complete"])
		for block in raw_blocks {
			guard let type = block["type"] as? String else { throw DocumentError.invalid("A block is missing its type.") }
			let extras: Set<String>
			switch type {
			case "heading": extras = ["subtitle"]
			case "timer": extras = ["minutes"]
			case "checklist": extras = ["items"]
			case "counter": extras = ["target"]
			case "note": extras = ["text"]
			case "screen_time": extras = []
			default: throw DocumentError.invalid("This version cannot run the \(type) block.")
			}
			try require_keys(block, Set(["id", "type", "title"]).union(extras))
			if let tasks = block["items"] as? [[String: Any]] {
				for task in tasks { try require_keys(task, ["id", "text"]) }
			}
		}
		let document = try JSONDecoder().decode(AppDocument.self, from: data)
		try document.validate()
		return document
	}

	private static func require_keys(_ object: [String: Any], _ keys: Set<String>) throws {
		guard Set(object.keys) == keys else { throw DocumentError.invalid("Unexpected or missing configuration fields. Export using the version 1 editor.") }
	}

	func validate() throws {
		guard schema_version == 1 else { throw DocumentError.invalid("Unsupported schema version. This host supports version 1.") }
		try Self.validate_id(id)
		try Self.validate_text(name, maximum: 80, required: true)
		try Self.validate_text(description, maximum: 200)
		guard (1...20).contains(blocks.count) else { throw DocumentError.invalid("A tool needs between 1 and 20 blocks.") }
		var ids = Set<String>()
		for block in blocks {
			try Self.validate_id(block.id)
			guard ids.insert(block.id).inserted else { throw DocumentError.invalid("Duplicate block or task ID.") }
			try Self.validate_text(block.title, maximum: 80, required: true)
			switch block.type {
			case .heading:
				guard let subtitle = block.subtitle else { throw DocumentError.invalid("Missing heading subtitle.") }
				try Self.validate_text(subtitle, maximum: 200)
			case .timer:
				guard let minutes = block.minutes, (15...120).contains(minutes) else { throw DocumentError.invalid("Focus timers must be 15–120 minutes.") }
			case .checklist:
				guard let items = block.items, (1...20).contains(items.count) else { throw DocumentError.invalid("Checklists need 1–20 tasks.") }
				for item in items {
					try Self.validate_id(item.id)
					guard ids.insert(item.id).inserted else { throw DocumentError.invalid("Duplicate block or task ID.") }
					try Self.validate_text(item.text, maximum: 80, required: true)
				}
			case .counter:
				guard let target = block.target, (1...1000).contains(target) else { throw DocumentError.invalid("Counter targets must be 1–1000.") }
			case .note:
				guard let text = block.text else { throw DocumentError.invalid("Missing note text.") }
				try Self.validate_text(text, maximum: 1000)
			case .screen_time: break
			}
		}
		guard blocks.filter({ $0.type == .timer }).count <= 1, blocks.filter({ $0.type == .screen_time }).count <= 1 else {
			throw DocumentError.invalid("Version 1 supports one timer and one Screen Time block.")
		}
		if rules.block_during_focus && (focus_minutes == nil || !blocks.contains(where: { $0.type == .screen_time })) {
			throw DocumentError.invalid("Focus blocking needs a timer and Screen Time block.")
		}
		if rules.notify_on_complete && focus_minutes == nil { throw DocumentError.invalid("Completion notifications need a timer.") }
	}

	private static func validate_id(_ value: String) throws {
		guard value.range(of: "^[a-zA-Z0-9_-]{1,64}$", options: .regularExpression) != nil else {
			throw DocumentError.invalid("Invalid block or task identifier.")
		}
	}

	private static func validate_text(_ value: String, maximum: Int, required: Bool = false) throws {
		guard value.utf16.count <= maximum, !required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
			throw DocumentError.invalid("A text field is empty or exceeds its length limit.")
		}
	}
}
