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
	case heading, timer, checklist, counter, note, screen_time, schedule
}

// What a Screen Time block does to its groups. Mirrors ShieldMode in lib/document.ts.
enum ShieldMode: String, Codable {
	case block, allow_only, limit
}

struct AppGroup: Codable, Equatable, Identifiable {
	var id: String
	var name: String
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
	// Schedule blocks: days use 1 = Sunday … 7 = Saturday (Calendar.weekday); times are "HH:MM" in local time.
	var days: [Int]?
	var start: String?
	var end: String?
	// Screen Time blocks: named app groups (filled on the phone) and what happens to them. No groups means "choose apps for this routine".
	var mode: ShieldMode?
	var groups: [String]?
	var limit_minutes: Int?

	var shield_mode: ShieldMode { mode ?? .block }
	var group_names: [String] { groups ?? [] }

	// Plain words for what the Screen Time block does. Mirrors describe_shield in lib/document.ts.
	var shield_description: String {
		let names = group_names
		if names.isEmpty { return "Apps chosen on iPhone" }
		let list = names.count <= 3 ? names.joined(separator: ", ") : "\(names.prefix(2).joined(separator: ", ")) + \(names.count - 2) more"
		switch shield_mode {
		case .block: return "Blocks \(list)"
		case .allow_only: return "Only \(list)"
		case .limit: return "\(list) · \(limit_minutes ?? 0) min limit"
		}
	}

	// Mirrors create_block in lib/document.ts so a block added on the phone matches one added in the browser.
	static func make(_ kind: BlockKind) -> BlockDocument {
		let id = UUID().uuidString
		switch kind {
		case .heading: return BlockDocument(id: id, type: kind, title: "Make room for what matters.", subtitle: "A little space, just for you.", minutes: nil, items: nil, target: nil, text: nil, days: nil, start: nil, end: nil, mode: nil, groups: nil, limit_minutes: nil)
		case .timer: return BlockDocument(id: id, type: kind, title: "Focus session", subtitle: nil, minutes: 25, items: nil, target: nil, text: nil, days: nil, start: nil, end: nil, mode: nil, groups: nil, limit_minutes: nil)
		case .checklist: return BlockDocument(id: id, type: kind, title: "On my list", subtitle: nil, minutes: nil, items: [TaskDocument(id: UUID().uuidString, text: "My first task")], target: nil, text: nil, days: nil, start: nil, end: nil, mode: nil, groups: nil, limit_minutes: nil)
		case .counter: return BlockDocument(id: id, type: kind, title: "Small wins", subtitle: nil, minutes: nil, items: nil, target: 5, text: nil, days: nil, start: nil, end: nil, mode: nil, groups: nil, limit_minutes: nil)
		case .note: return BlockDocument(id: id, type: kind, title: "A note to myself", subtitle: nil, minutes: nil, items: nil, target: nil, text: "One thing at a time.", days: nil, start: nil, end: nil, mode: nil, groups: nil, limit_minutes: nil)
		case .screen_time: return BlockDocument(id: id, type: kind, title: "Fewer distractions", subtitle: nil, minutes: nil, items: nil, target: nil, text: nil, days: nil, start: nil, end: nil, mode: nil, groups: nil, limit_minutes: nil)
		case .schedule: return BlockDocument(id: id, type: kind, title: "Every evening", subtitle: nil, minutes: nil, items: nil, target: nil, text: nil, days: [1, 2, 3, 4, 5, 6, 7], start: "22:00", end: "07:00", mode: nil, groups: nil, limit_minutes: nil)
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
	// Only meaningful for a standing routine: whether the person has switched it on.
	var enabled: Bool?
	var home_allowance: HomePolicy? = nil
	var behaviors: BehaviorGraph? = nil

	var focus_minutes: Int? { blocks.first(where: { $0.type == .timer })?.minutes }
	var has_timer: Bool { blocks.contains(where: { $0.type == .timer }) }
	var has_screen_time: Bool { blocks.contains(where: { $0.type == .screen_time }) }
	var schedule: BlockDocument? { blocks.first(where: { $0.type == .schedule }) }
	var shield: BlockDocument? { blocks.first(where: { $0.type == .screen_time }) }
	var is_standing: Bool { schedule != nil }
	var has_engine: Bool { has_timer || is_standing }

	// Group names this routine mentions, in order, without case-insensitive duplicates.
	var referenced_groups: [String] {
		var names: [String] = []
		for block in blocks where block.type == .screen_time {
			for name in block.group_names where !names.contains(where: { $0.lowercased() == name.lowercased() }) { names.append(name) }
		}
		return names
	}

	static func blank() -> AppDocument {
		AppDocument(schema_version: 1, id: UUID().uuidString, name: "My new routine", description: "", blocks: [BlockDocument.make(.heading)], rules: RuleDocument(block_during_focus: false, notify_on_complete: false), enabled: nil)
	}

	// Rules that depend on a removed block are switched off rather than left invalid, as remove_block does in the editor.
	func removing_block(_ block_id: String) -> AppDocument {
		guard blocks.count > 1 else { return self }
		var next = self
		next.blocks.removeAll { $0.id == block_id }
		next.behaviors?.connections.removeAll { $0.from == block_id }
		next.rules.block_during_focus = rules.block_during_focus && next.has_engine && next.has_screen_time
		next.rules.notify_on_complete = rules.notify_on_complete && next.has_timer
		if !next.is_standing { next.enabled = nil }
		return next
	}

	func can_add(_ kind: BlockKind) -> Bool {
		guard blocks.count < 20 else { return false }
		if (kind == .timer && is_standing) || (kind == .schedule && has_timer) { return false }
		if kind == .timer || kind == .screen_time || kind == .schedule { return !blocks.contains(where: { $0.type == kind }) }
		return true
	}

	static func decode(_ data: Data) throws -> AppDocument {
		guard data.count <= 100_000 else { throw DocumentError.invalid("This tool exceeds the 100 KB limit.") }
		guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw DocumentError.invalid("This file is not a Pocketwork configuration.")
		}
		try require_keys(object, ["schema_version", "id", "name", "description", "blocks", "rules"], optional: ["enabled", "home_allowance", "behaviors"])
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
			case "schedule": extras = ["days", "start", "end"]
			default: throw DocumentError.invalid("This version cannot run the \(type) block.")
			}
			try require_keys(block, Set(["id", "type", "title"]).union(extras), optional: type == "screen_time" ? ["mode", "groups", "limit_minutes"] : [])
			if let tasks = block["items"] as? [[String: Any]] {
				for task in tasks { try require_keys(task, ["id", "text"]) }
			}
		}
		let document = try JSONDecoder().decode(AppDocument.self, from: data)
		try document.validate()
		return document
	}

	private static func require_keys(_ object: [String: Any], _ keys: Set<String>, optional: Set<String> = []) throws {
		let present = Set(object.keys)
		guard keys.isSubset(of: present), present.isSubset(of: keys.union(optional)) else { throw DocumentError.invalid("Unexpected or missing configuration fields. Export using the version 1 editor.") }
	}

	func validate() throws {
		guard schema_version == 3 || (schema_version == 2) == (home_allowance != nil) else { throw DocumentError.invalid("Home allowances need routine format 2.") }
		if let policy = home_allowance {
			try policy.validate()
			guard schedule != nil, rules.block_during_focus, shield?.shield_mode == .block, shield?.group_names.count == 1 else { throw DocumentError.invalid("Home allowances require one distraction group and a schedule.") }
		}
		guard schema_version == 1 || schema_version == 2 || schema_version == 3 else { throw DocumentError.invalid("Unsupported schema version. This host supports version 1.") }
		guard (schema_version == 3) == (behaviors != nil) else { throw DocumentError.invalid("Connected behaviors require routine format 3.") }
		if let behaviors { _ = try behaviors.ordered(external: behavior_external_ports) }
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
				guard let minutes = block.minutes, (15...120).contains(minutes) else { throw DocumentError.invalid("Timers must be 15–120 minutes.") }
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
			case .screen_time:
				let names = block.group_names
				guard names.count <= 20, Set(names.map { $0.lowercased() }).count == names.count else { throw DocumentError.invalid("Each group can only be listed once.") }
				for name in names { try Self.validate_text(name, maximum: 40, required: true) }
				if (block.shield_mode == .allow_only || block.shield_mode == .limit) && names.isEmpty { throw DocumentError.invalid("\"\(block.shield_mode == .limit ? "Limit" : "Only these")\" needs at least one app group.") }
				if block.shield_mode == .limit { guard let minutes = block.limit_minutes, (15...1440).contains(minutes) else { throw DocumentError.invalid("A limit needs 15 to 1440 minutes.") } }
				else if block.limit_minutes != nil { throw DocumentError.invalid("Minutes only apply to a limit.") }
			case .schedule: break // days and times are checked once, below, together with the rules that depend on them
			}
		}
		guard blocks.filter({ $0.type == .timer }).count <= 1, blocks.filter({ $0.type == .screen_time }).count <= 1, blocks.filter({ $0.type == .schedule }).count <= 1 else {
			throw DocumentError.invalid("Version 1 supports one timer, one schedule, and one Screen Time block.")
		}
		if let schedule {
			guard !has_timer else { throw DocumentError.invalid("A routine either runs on a schedule or when you start it, not both.") }
			guard has_screen_time, rules.block_during_focus else { throw DocumentError.invalid("A scheduled routine needs a Screen Time block with blocking turned on.") }
			guard let days = schedule.days, !days.isEmpty, days.count <= 7, Set(days).count == days.count, days.allSatisfy({ (1...7).contains($0) }) else {
				throw DocumentError.invalid("A schedule needs at least one day, each chosen once.")
			}
			guard let start = schedule.start, let end = schedule.end, let from = ScheduleWindow.minutes(start), let to = ScheduleWindow.minutes(end), start != end else {
				throw DocumentError.invalid("A schedule needs a start time and a different end time, like 22:00.")
			}
			guard (to > from ? to - from : 24 * 60 - from + to) >= 15 else { throw DocumentError.invalid("A scheduled window must last at least 15 minutes; iOS cannot monitor anything shorter.") }
		} else if enabled != nil {
			throw DocumentError.invalid("Only a scheduled routine can be switched on or off.")
		}
		if rules.block_during_focus && !has_screen_time { throw DocumentError.invalid("Blocking needs a Screen Time block.") }
		if rules.block_during_focus && !has_engine { throw DocumentError.invalid("Blocking needs either a timer or a schedule.") }
		if rules.notify_on_complete && focus_minutes == nil { throw DocumentError.invalid("Completion notifications need a timer.") }
	}

	static func validate_id(_ value: String) throws {
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
