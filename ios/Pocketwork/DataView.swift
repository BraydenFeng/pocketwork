import Charts
import SwiftUI

// The Data tab: what the routines have recorded on this iPhone, read-only.
struct DataView: View {
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@Environment(\.scenePhase) private var scene_phase
	@State private var home: HomeState?
	@State private var focus = SessionHistory()
	@State private var load_error: String?
	private struct Day: Identifiable { var date: Date; var minutes: Int; var budget: Int?; var id: Date { date } }
	private let shown_days = 14

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 0) {
					section(number: "01", label: "Screen time at home") { allowance_section }
					Hairline()
					section(number: "02", label: "Focus sessions") { focus_section }
					if let load_error { Text(load_error).font(.system(size: 13)).foregroundStyle(Theme.danger).padding(Theme.pad) }
				}
			}
			.refreshable { await load() }
			.page()
			.navigationTitle("Data")
			.navigationBarTitleDisplayMode(.inline)
			.task { await load() }
			.onChange(of: scene_phase) { _, phase in if phase == .active { Task { await load() } } }
			.onChange(of: sessions.session) { _, _ in Task { await load() } }
		}
	}

	private var allowance_document: AppDocument? { library.sorted_tools.first { $0.document.home_allowance != nil }?.document }

	@ViewBuilder private var allowance_section: some View {
		if let document = allowance_document, let policy = document.home_allowance {
			let days = allowance_days(policy)
			let today = days.last
			VStack(alignment: .leading, spacing: 6) {
				Text(today.map { "\($0.minutes) of \($0.budget ?? 0) min used today" } ?? "No usage counted today").heading_font(17)
				Text(document.enabled == true ? "\(document.name) is on." : "\(document.name) is off, so nothing is being counted.").supporting()
			}
			chart(days, budget: true).accessibilityIdentifier("data.allowance")
		} else {
			Text("No home allowance yet. Add one to see how much distraction time you use at home.").supporting()
		}
	}

	@ViewBuilder private var focus_section: some View {
		let days = focus_days()
		let today = focus.days[SessionHistory.day_key(.now)]
		VStack(alignment: .leading, spacing: 6) {
			Text("\(today?.minutes ?? 0) min today").heading_font(17)
			Text("\(today?.sessions ?? 0) session\(today?.sessions == 1 ? "" : "s") finished or ended today. Last 14 days: \(days.reduce(0) { $0 + $1.minutes }) min.").supporting()
		}
		if days.contains(where: { $0.minutes > 0 }) { chart(days, budget: false).accessibilityIdentifier("data.focus") }
		else { Text("Start a routine with a timer to see your focus time here.").supporting() }
	}

	private func chart(_ days: [Day], budget: Bool) -> some View {
		Chart {
			ForEach(days) { day in
				if budget, let limit = day.budget { BarMark(x: .value("Day", day.date, unit: .day), y: .value("Budget", limit)).foregroundStyle(Theme.border).opacity(0.6) }
				BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", day.minutes)).foregroundStyle(Theme.accent)
			}
		}
		.chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
		.frame(height: 160)
		.padding(.top, 8)
	}

	private func section<Content: View>(number: String, label: String, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: Theme.gap) {
			SectionLabel(number: number, text: label)
			content()
		}
		.padding(Theme.pad)
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	// The ledger and session history keep 30 days; the chart shows the last 14 with empty days filled in.
	private func allowance_days(_ policy: HomePolicy) -> [Day] {
		let entries = home?.ledger.usage_entries(policy: policy, now: .now) ?? []
		let calendar = policy.calendar
		var by_day: [Date: Day] = [:]
		for entry in entries {
			let date = calendar.startOfDay(for: Date(timeIntervalSince1970: entry.at / 1000))
			by_day[date] = Day(date: date, minutes: Int(entry.values["minutes"]?.number ?? 0), budget: entry.values["budget"]?.number.map { Int($0) })
		}
		return last_days(calendar) { by_day[$0] ?? Day(date: $0, minutes: 0, budget: nil) }
	}

	private func focus_days() -> [Day] {
		last_days(.current) { date in Day(date: date, minutes: focus.days[SessionHistory.day_key(date)]?.minutes ?? 0, budget: nil) }
	}

	private func last_days(_ calendar: Calendar, _ make: (Date) -> Day) -> [Day] {
		let today = calendar.startOfDay(for: .now)
		return (0..<shown_days).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.map(make)
	}

	private func load() async {
		focus = SessionHistory.load(from: .standard)
		guard !CommandLine.arguments.contains("--ui-testing") else { return }
		do { home = try await HomeWorker.run { try HomeEngine.snapshot() }; load_error = nil }
		catch { load_error = "Could not read home allowance data: \(error.localizedDescription)" }
	}
}
