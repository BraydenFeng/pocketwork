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
		guard timezone == "America/Los_Angeles", !away_usage_counts, outside_windows == "block_at_home", (1...7).contains(rules.count) else { throw DocumentError.invalid("Unsupported home allowance settings.") }
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
	mutating func reset_if_needed(policy: HomePolicy, now: Date) {
		let today = policy.day_key(now)
		if day != today { day = today; used_minutes = 0; segment_base = 0; generation = nil }
	}
	mutating func checkpoint(generation: String, minutes: Int, at_home: Bool) {
		guard at_home, self.generation == generation, minutes > 0 else { return }
		used_minutes = max(used_minutes, segment_base + minutes)
	}
	mutating func pause() { generation = nil; segment_base = used_minutes }
}
