import Foundation

// What the phone shares with the account when the person opts in: minute counts and running state, never app identities.
// Mirrors status_schema in lib/status.ts. Stored as one row per user in routine_status.
struct RoutineStatus: Codable, Equatable {
	var id: String
	var name: String
	var kind: String            // "session" | "standing" | "allowance"
	var enabled: Bool
	var running: Bool
	var ends_at: String?        // ISO-8601, running sessions only
}

struct AllowanceStatus: Codable, Equatable {
	var routine_id: String
	var day: String             // YYYY-M-D in the policy's timezone, matching HomePolicy.day_key
	var budget_minutes: Int
	var used_minutes: Int
	var remaining_minutes: Int
	var at_home: Bool
	var in_window: Bool
	var window_ends: String?    // HH:MM when in_window
	var next_window: String?    // HH:MM when a later window exists today
}

struct DayHistory: Codable, Equatable {
	var day: String             // YYYY-MM-DD local
	var allowance_used: Int?
	var allowance_budget: Int?
	var session_minutes: Int
	var sessions: Int
}

struct StatusReport: Codable, Equatable {
	static let history_days = 30
	var schema_version = 1
	var reported_at: String
	var timezone: String
	var routines: [RoutineStatus]
	var allowance: AllowanceStatus?
	var history: [DayHistory]
}

// Focus sessions that finished or were ended, rolled up per day so history never grows past a few hundred bytes.
struct SessionHistory: Codable, Equatable {
	struct Day: Codable, Equatable { var minutes = 0; var sessions = 0 }
	static let key = "session_history.v1"
	var days: [String: Day] = [:]

	static func day_key(_ date: Date, calendar: Calendar = .current) -> String {
		let parts = calendar.dateComponents([.year, .month, .day], from: date)
		return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
	}

	mutating func record(minutes: Int, at date: Date = .now) {
		guard minutes > 0 else { return }
		let key = Self.day_key(date)
		var day = days[key] ?? Day()
		day.minutes += minutes; day.sessions += 1
		days[key] = day
		prune(before: date)
	}

	mutating func prune(before date: Date) {
		let keep = Set((0..<StatusReport.history_days).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: date) }.map { Self.day_key($0) })
		days = days.filter { keep.contains($0.key) }
	}

	static func load(from defaults: UserDefaults) -> SessionHistory {
		guard let data = defaults.data(forKey: key), let history = try? JSONDecoder().decode(SessionHistory.self, from: data) else { return SessionHistory() }
		return history
	}

	func save(to defaults: UserDefaults) throws { defaults.set(try JSONEncoder().encode(self), forKey: Self.key) }
}
