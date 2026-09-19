import XCTest
@testable import Pocketwork

final class StatusReportTests: XCTestCase {
	private var policy: HomePolicy { HomePolicy(timezone: "America/Los_Angeles", away_usage_counts: false, outside_windows: "unrestricted", rules: [HomeDayRule(days: [1,2,3,4,5,6,7], allowance_minutes: 30, windows: [HomeWindow(start: "18:00", end: "20:50")])]) }
	private var calendar: Calendar { policy.calendar }
	private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))! }

	private func allowance_document() throws -> AppDocument {
		var document = AppDocument.blank()
		document.blocks = [BlockDocument.make(.heading), BlockDocument.make(.schedule), BlockDocument.make(.screen_time)]
		document.blocks[1].days = [1,2,3,4,5,6,7]; document.blocks[1].start = "00:00"; document.blocks[1].end = "23:59"
		document.blocks[2].groups = ["Distractions"]; document.schema_version = 2; document.rules.block_during_focus = true; document.enabled = true
		document.home_allowance = policy; document.name = "Home allowance"
		try document.validate()
		return document
	}

	func test_ledger_rolls_yesterday_into_history_on_reset() {
		var ledger = HomeLedger(day: policy.day_key(date(2026, 9, 17, 19, 0)), used_minutes: 22)
		ledger.reset_if_needed(policy: policy, now: date(2026, 9, 18, 8, 0))
		XCTAssertEqual(ledger.used_minutes, 0)
		XCTAssertEqual(ledger.history?[policy.day_key(date(2026, 9, 17, 12, 0))], [22, 30])
		// A second reset on the same day changes nothing.
		ledger.used_minutes = 5; ledger.reset_if_needed(policy: policy, now: date(2026, 9, 18, 9, 0))
		XCTAssertEqual(ledger.used_minutes, 5)
	}

	func test_session_history_rolls_up_per_day_and_prunes() {
		var history = SessionHistory()
		let today = Date()
		history.record(minutes: 25, at: today); history.record(minutes: 50, at: today); history.record(minutes: 0, at: today)
		XCTAssertEqual(history.days[SessionHistory.day_key(today)], SessionHistory.Day(minutes: 75, sessions: 2))
		history.record(minutes: 10, at: Calendar.current.date(byAdding: .day, value: -45, to: today)!)
		history.record(minutes: 10, at: today)
		XCTAssertEqual(history.days.count, 1, "entries older than the history window are dropped")
	}

	@MainActor func test_report_describes_allowance_inside_a_window() throws {
		let document = try allowance_document()
		let library = try ToolLibrary.empty.upserting(document, now: .now)
		let now = date(2026, 9, 18, 19, 30)
		var state = HomeState(); state.document = document; state.enabled = true; state.at_home = true
		state.ledger = HomeLedger(day: policy.day_key(now), used_minutes: 8)
		let report = StatusReporter.build(library: library, session: nil, home: state, now: now)
		let allowance = try XCTUnwrap(report.allowance)
		XCTAssertEqual(allowance.remaining_minutes, 22); XCTAssertEqual(allowance.budget_minutes, 30)
		XCTAssertTrue(allowance.in_window); XCTAssertEqual(allowance.window_ends, "20:50"); XCTAssertNil(allowance.next_window)
		XCTAssertEqual(report.routines.first?.kind, "allowance"); XCTAssertTrue(report.routines.first?.enabled == true)
		XCTAssertEqual(report.history.last?.day, SessionHistory.day_key(now)); XCTAssertEqual(report.history.last?.allowance_used, 8)
		let encoded = try JSONEncoder().encode(report)
		XCTAssertEqual(try JSONDecoder().decode(StatusReport.self, from: encoded), report)
	}

	@MainActor func test_report_marks_running_sessions() throws {
		var document = AppDocument.blank(); document.blocks.append(BlockDocument.make(.timer)); document.name = "Deep work"
		let library = try ToolLibrary.empty.upserting(document, now: .now)
		let session = FocusSession(activity_name: "pocketwork.x", document_id: document.id, ends_at: Date().addingTimeInterval(600), blocks_apps: false)
		let report = StatusReporter.build(library: library, session: session, home: nil)
		XCTAssertTrue(report.routines[0].running); XCTAssertNotNil(report.routines[0].ends_at); XCTAssertNil(report.allowance)
	}
}
