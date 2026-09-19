import Foundation

struct HomeWindow: Codable, Equatable { var start: String; var end: String }
struct HomeDayRule: Codable, Equatable { var days: [Int]; var allowance_minutes: Int; var windows: [HomeWindow] }
struct HomePolicy: Codable, Equatable {
	var timezone: String
	var away_usage_counts: Bool
	var outside_windows: String
	var rules: [HomeDayRule]
	var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: timezone)!; return value }
	func validate() throws {
		guard timezone == "America/Los_Angeles", !away_usage_counts, ["unrestricted", "block_at_home"].contains(outside_windows), (1...7).contains(rules.count) else { throw DocumentError.invalid("Unsupported home allowance settings.") }
		var days = Set<Int>()
		for rule in rules {
			guard (1...180).contains(rule.allowance_minutes), (1...2).contains(rule.windows.count), !rule.days.isEmpty else { throw DocumentError.invalid("Invalid daily allowance.") }
			for day in rule.days { guard (1...7).contains(day), days.insert(day).inserted else { throw DocumentError.invalid("Each weekday needs exactly one allowance.") } }
			var previous_end = 0
			for window in rule.windows {
				guard let start = ScheduleWindow.minutes(window.start), let end = ScheduleWindow.minutes(window.end), start >= previous_end, end - start >= 15 else { throw DocumentError.invalid("Home windows must be ordered, nonoverlapping, and at least 15 minutes.") }
				previous_end = end
			}
		}
		guard days.count == 7 else { throw DocumentError.invalid("Configure all seven weekdays.") }
	}
	// Outside the windows nothing is blocked unless the document kept the older setting on purpose.
	var blocks_outside: Bool { outside_windows == "block_at_home" }
	func rule(at date: Date) -> HomeDayRule? { rules.first { $0.days.contains(calendar.component(.weekday, from: date)) } }
	func allows(at date: Date) -> Bool {
		let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
		return rule(at: date)?.windows.contains { minute >= (ScheduleWindow.minutes($0.start) ?? 1440) && minute < (ScheduleWindow.minutes($0.end) ?? 0) } == true
	}
	func day_key(_ date: Date) -> String { let c = calendar.dateComponents([.year, .month, .day], from: date); return "\(c.year!)-\(c.month!)-\(c.day!)" }
}

struct HomeLedger: Codable, Equatable {
	var day = ""
	var used_minutes = 0
	var segment_base = 0
	var generation: String?
	var bonuses: [String: Int]?
	// Past days' used/budget, keyed by day_key, so status reports can show a trend. Trimmed to StatusReport.history_days entries.
	var history: [String: [Int]]?
	mutating func reset_if_needed(policy: HomePolicy, now: Date) {
		let today = policy.day_key(now)
		if day != today {
			if !day.isEmpty {
				var past = history ?? [:]
				past[day] = [used_minutes, budget(policy.rules.first { rule in rule.days.contains(HomeLedger.weekday(of: day, policy: policy)) }?.allowance_minutes ?? 0)]
				if past.count > StatusReport.history_days { for key in past.keys.sorted().prefix(past.count - StatusReport.history_days) { past.removeValue(forKey: key) } }
				history = past
			}
			day = today; used_minutes = 0; segment_base = 0; generation = nil; bonuses = [:]
		}
	}
	// day_key is "YYYY-M-D"; recover its weekday so yesterday's budget is the right rule's.
	static func weekday(of key: String, policy: HomePolicy) -> Int {
		let parts = key.split(separator: "-").compactMap { Int($0) }
		guard parts.count == 3, let date = policy.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return 0 }
		return policy.calendar.component(.weekday, from: date)
	}
	func budget(_ base: Int) -> Int { min(1440, base + (bonuses ?? [:]).values.reduce(0,+)) }
	mutating func grant(_ key: String, minutes: Int) throws -> Bool {
		guard (1...1440).contains(minutes) else { throw DocumentError.invalid("Choose 1 to 1440 bonus minutes.") }
		if bonuses?[key] != nil { return false }
		if bonuses == nil { bonuses = [:] }; bonuses?[key] = minutes; pause(); return true
	}
	mutating func checkpoint(generation: String, minutes: Int, at_home: Bool) {
		guard at_home, self.generation == generation, minutes > 0 else { return }
		used_minutes = max(used_minutes, segment_base + minutes)
	}
	mutating func pause() { generation = nil; segment_base = used_minutes }
}
