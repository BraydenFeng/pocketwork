import Charts
import SwiftUI

struct MinutesDay: Identifiable { var date: Date; var minutes: Int; var budget: Int?; var id: Date { date } }

// Fourteen days of minutes as bars, with an optional budget bar behind each day. Used in a page's Data section.
struct MinutesChart: View {
	let days: [MinutesDay]
	var body: some View {
		Chart {
			ForEach(days) { day in
				// Unstacked so the used bar sits in front of the budget bar instead of on top of it.
				if let limit = day.budget { BarMark(x: .value("Day", day.date, unit: .day), y: .value("Budget", limit), stacking: .unstacked).foregroundStyle(Theme.border).opacity(0.6) }
				BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", day.minutes), stacking: .unstacked).foregroundStyle(Theme.accent)
			}
		}
		.chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
		.frame(height: 150)
	}
}

enum MinutesHistory {
	static let shown_days = 14

	// The allowance ledger keeps 30 days of [used, budget]; missing days show as empty.
	static func allowance(_ state: HomeState?, policy: HomePolicy, now: Date = .now) -> [MinutesDay] {
		let entries = state?.ledger.usage_entries(policy: policy, now: now) ?? []
		let calendar = policy.calendar
		var by_day: [Date: MinutesDay] = [:]
		for entry in entries {
			let date = calendar.startOfDay(for: Date(timeIntervalSince1970: entry.at / 1000))
			by_day[date] = MinutesDay(date: date, minutes: Int(entry.values["minutes"]?.number ?? 0), budget: entry.values["budget"]?.number.map { Int($0) })
		}
		return last_days(calendar, now: now) { by_day[$0] ?? MinutesDay(date: $0, minutes: 0, budget: nil) }
	}

	// Focus minutes for one page, from sessions that finished or were ended on this phone.
	static func focus(_ history: SessionHistory, page: String, now: Date = .now) -> [MinutesDay] {
		let days = history.pages?[page] ?? [:]
		return last_days(.current, now: now) { MinutesDay(date: $0, minutes: days[SessionHistory.day_key($0)]?.minutes ?? 0, budget: nil) }
	}

	private static func last_days(_ calendar: Calendar, now: Date, _ make: (Date) -> MinutesDay) -> [MinutesDay] {
		let today = calendar.startOfDay(for: now)
		return (0..<shown_days).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.map(make)
	}
}
