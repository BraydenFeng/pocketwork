import Foundation

// Pure schedule math shared by the app and the monitor extension. Mirrors lib/schedule.ts.
enum ScheduleWindow {
	static let day_labels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	static let weekdays = [2, 3, 4, 5, 6]
	static let all_days = [1, 2, 3, 4, 5, 6, 7]

	struct Status: Equatable {
		let active: Bool
		let change_at: Date?
	}

	static func minutes(_ clock: String) -> Int? {
		let parts = clock.split(separator: ":")
		guard parts.count == 2, let hours = Int(parts[0]), let mins = Int(parts[1]), (0...23).contains(hours), (0...59).contains(mins), parts[0].count == 2, parts[1].count == 2 else { return nil }
		return hours * 60 + mins
	}

	static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

	// A window belongs to the day it starts on. Ending earlier than it starts means it runs past midnight.
	static func status(_ block: BlockDocument, at now: Date, calendar: Calendar = .current) -> Status {
		guard let days = block.days, let start_clock = block.start, let end_clock = block.end, let start = minutes(start_clock), let end = minutes(end_clock) else {
			return Status(active: false, change_at: nil)
		}
		let length = end > start ? end - start : 24 * 60 - start + end
		var next_start: Date?
		for offset in -1...7 {
			guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
			guard days.contains(calendar.component(.weekday, from: day)) else { continue }
			guard let window_start = calendar.date(byAdding: .minute, value: start, to: day) else { continue }
			let window_end = window_start.addingTimeInterval(Double(length) * 60)
			if now >= window_start && now < window_end { return Status(active: true, change_at: window_end) }
			if window_start > now, next_start == nil || window_start < next_start! { next_start = window_start }
		}
		return Status(active: false, change_at: next_start)
	}

	static func format_clock(_ clock: String) -> String {
		guard let total = minutes(clock) else { return clock }
		let hours = total / 60, mins = total % 60
		let suffix = hours >= 12 ? "PM" : "AM"
		let twelve = hours % 12 == 0 ? 12 : hours % 12
		return mins == 0 ? "\(twelve) \(suffix)" : "\(twelve):" + String(format: "%02d", mins) + " \(suffix)"
	}

	static func format_days(_ days: [Int]) -> String {
		let sorted = Array(Set(days)).sorted()
		if sorted.count == 7 { return "Every day" }
		if sorted == weekdays { return "Weekdays" }
		if sorted == [1, 7] { return "Weekends" }
		return sorted.compactMap { (1...7).contains($0) ? day_labels[$0 - 1] : nil }.joined(separator: ", ")
	}

	static func describe(_ block: BlockDocument) -> String {
		"\(format_days(block.days ?? [])) · \(format_clock(block.start ?? "")) to \(format_clock(block.end ?? ""))"
	}

	static func describe_status(_ block: BlockDocument, enabled: Bool, at now: Date, calendar: Calendar = .current) -> String {
		guard enabled else { return "Off · switch it on to start enforcing" }
		let current = status(block, at: now, calendar: calendar)
		if current.active, let until = current.change_at { return "Active now · until \(relative(until, now: now, calendar: calendar))" }
		guard let next = current.change_at else { return "On · waiting for a scheduled day" }
		return "On · next \(relative(next, now: now, calendar: calendar))"
	}

	private static func relative(_ date: Date, now: Date, calendar: Calendar) -> String {
		let components = calendar.dateComponents([.hour, .minute], from: date)
		let clock_text = format_clock(clock((components.hour ?? 0) * 60 + (components.minute ?? 0)))
		if calendar.isDate(date, inSameDayAs: now) { return clock_text }
		if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "tomorrow \(clock_text)" }
		return "\(day_labels[calendar.component(.weekday, from: date) - 1]) \(clock_text)"
	}
}
