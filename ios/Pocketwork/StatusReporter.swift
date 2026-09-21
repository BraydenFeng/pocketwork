import Foundation

// Builds the status report the phone shares with the account: what is running, minutes left today, and a short history.
enum StatusReporter {
	static let opt_in_key = "share_status.v1"
	static var sharing: Bool {
		get { UserDefaults.standard.bool(forKey: opt_in_key) }
		set { UserDefaults.standard.set(newValue, forKey: opt_in_key) }
	}

	static func build(library: ToolLibrary, session: FocusSession?, home: HomeState?, now: Date = .now) -> StatusReport {
		let iso = ToolLibrary.iso_formatter
		var routines: [RoutineStatus] = []
		var allowance: AllowanceStatus?
		for entry in library.sorted {
			let document = entry.document
			let running = session?.document_id == document.id && session.map { !$0.has_ended(at: now) } == true
			let kind = document.home_allowance != nil ? "allowance" : document.is_standing ? "standing" : "session"
			routines.append(RoutineStatus(id: document.id, name: document.name, kind: kind, enabled: document.enabled == true, running: running, ends_at: running ? session.map { iso.string(from: $0.ends_at) } : nil))
			if let policy = document.home_allowance, allowance == nil {
				allowance = allowance_status(document: document, policy: policy, home: home, now: now)
			}
		}
		return StatusReport(reported_at: iso.string(from: now), timezone: TimeZone.current.identifier, routines: routines, allowance: allowance, history: history(home: home, now: now))
	}

	private static func allowance_status(document: AppDocument, policy: HomePolicy, home: HomeState?, now: Date) -> AllowanceStatus {
		let today = policy.day_key(now)
		let ledger = home?.ledger
		let same_day = ledger?.day == today
		let base = policy.rule(at: now)?.allowance_minutes ?? 0
		let budget = same_day ? (ledger?.budget(base) ?? base) : base
		let used = same_day ? (ledger?.used_minutes ?? 0) : 0
		let minute = policy.calendar.component(.hour, from: now) * 60 + policy.calendar.component(.minute, from: now)
		let windows = policy.rule(at: now)?.windows ?? []
		let current = windows.first { (ScheduleWindow.minutes($0.start) ?? 1441) <= minute && minute < (ScheduleWindow.minutes($0.end) ?? 0) }
		let upcoming = windows.first { (ScheduleWindow.minutes($0.start) ?? 0) > minute }
		return AllowanceStatus(routine_id: document.id, day: today, budget_minutes: budget, used_minutes: used, remaining_minutes: max(0, budget - used), at_home: home?.at_home ?? false, in_window: current != nil, window_ends: current?.end, next_window: upcoming?.start)
	}

	private static func history(home: HomeState?, now: Date) -> [DayHistory] {
		let sessions = SessionHistory.load(from: .standard)
		let policy = home?.document?.home_allowance
		var days: [DayHistory] = []
		for offset in stride(from: StatusReport.history_days - 1, through: 0, by: -1) {
			guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: now) else { continue }
			let key = SessionHistory.day_key(date)
			let session_day = sessions.days[key] ?? SessionHistory.Day()
			var used: Int?; var budget: Int?
			if let policy, let ledger = home?.ledger {
				let policy_key = policy.day_key(date)
				if ledger.day == policy_key { used = ledger.used_minutes; budget = ledger.budget(policy.rule(at: date)?.allowance_minutes ?? 0) }
				else if let past = ledger.history?[policy_key], past.count == 2 { used = past[0]; budget = past[1] }
			}
			if session_day.sessions == 0 && used == nil && offset > 13 { continue }
			days.append(DayHistory(day: key, allowance_used: used, allowance_budget: budget, session_minutes: session_day.minutes, sessions: session_day.sessions))
		}
		return days
	}
}
