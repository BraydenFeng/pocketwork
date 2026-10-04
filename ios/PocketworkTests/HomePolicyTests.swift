import XCTest
@testable import Pocketwork

final class HomePolicyTests: XCTestCase {
	private var policy: HomePolicy { HomePolicy(timezone: "America/Los_Angeles", away_usage_counts: false, outside_windows: "block_at_home", rules: [HomeDayRule(days: [2,3,4,5], allowance_minutes: 30, windows: [HomeWindow(start: "18:00", end: "18:30"), HomeWindow(start: "19:00", end: "20:50")]), HomeDayRule(days: [6], allowance_minutes: 120, windows: [HomeWindow(start: "14:30", end: "20:20")]), HomeDayRule(days: [1,7], allowance_minutes: 180, windows: [HomeWindow(start: "06:30", end: "20:30")])]) }
	func test_pause_ignores_away_and_stale_callbacks_then_resumes_remaining() {
		var ledger = HomeLedger(day: "today", used_minutes: 0, segment_base: 0, generation: "first")
		ledger.checkpoint(generation: "first", minutes: 20, at_home: true)
		ledger.pause()
		ledger.checkpoint(generation: "first", minutes: 30, at_home: false)
		XCTAssertEqual(ledger.used_minutes, 20)
		ledger.generation = "second"
		ledger.checkpoint(generation: "first", minutes: 30, at_home: true)
		XCTAssertEqual(ledger.used_minutes, 20)
		ledger.checkpoint(generation: "second", minutes: 5, at_home: true)
		ledger.checkpoint(generation: "second", minutes: 5, at_home: true)
		ledger.checkpoint(generation: "second", minutes: 3, at_home: true)
		XCTAssertEqual(ledger.used_minutes, 25)
	}
	func test_meters_check_in_every_five_minutes_and_at_the_limit_twice() {
		XCTAssertEqual(HomeEngine.meter_thresholds(remaining: 12), [5, 10, 12, 13])
		XCTAssertEqual(HomeEngine.meter_thresholds(remaining: 15), [5, 10, 15, 16])
		XCTAssertEqual(HomeEngine.meter_thresholds(remaining: 3), [3, 4])
		XCTAssertEqual(HomeEngine.meter_thresholds(remaining: 0), [])
		XCTAssertEqual(HomeEngine.meter_thresholds(remaining: 60).count, 13, "60 minutes needs 13 checkpoints instead of 60")
	}

	func test_a_later_report_covers_reports_that_never_arrived() {
		var ledger = HomeLedger(day: "2026-10-4")
		ledger.generation = "meter"
		ledger.checkpoint(generation: "meter", minutes: 5, at_home: true)
		ledger.checkpoint(generation: "meter", minutes: 20, at_home: true)
		XCTAssertEqual(ledger.used_minutes, 20, "the 10 and 15 minute reports were lost, the 20 minute one still counts all of it")
	}

	func test_clock_names_are_one_daily_trigger_per_distinct_window_plus_midnight() {
		let policy = HomePolicy(timezone: "America/Los_Angeles", away_usage_counts: false, outside_windows: "unrestricted", rules: [
			HomeDayRule(days: [2, 3], allowance_minutes: 30, windows: [HomeWindow(start: "18:00", end: "18:30"), HomeWindow(start: "19:00", end: "20:00")]),
			HomeDayRule(days: [4], allowance_minutes: 45, windows: [HomeWindow(start: "18:00", end: "18:30")]),
			HomeDayRule(days: [1], allowance_minutes: 60, windows: [HomeWindow(start: "10:00", end: "12:00")]),
		])
		// Four day/window pairs share three distinct times: three triggers instead of four, well inside iOS's 20-activity limit.
		XCTAssertEqual(HomeEngine.clock_names(policy), ["pocketwork.home.clock.1800-1830", "pocketwork.home.clock.1900-2000", "pocketwork.home.clock.1000-1200", "pocketwork.home.midnight"])
	}

	func test_daily_reset_and_split_windows() throws {
		try policy.validate()
		let formatter = ISO8601DateFormatter()
		let first = formatter.date(from: "2026-09-15T01:10:00Z")!
		let gap = formatter.date(from: "2026-09-15T01:45:00Z")!
		let second = formatter.date(from: "2026-09-15T02:10:00Z")!
		XCTAssertTrue(policy.allows(at: first)); XCTAssertFalse(policy.allows(at: gap)); XCTAssertTrue(policy.allows(at: second))
		var ledger = HomeLedger(day: policy.day_key(first), used_minutes: 20, segment_base: 20, generation: nil)
		ledger.reset_if_needed(policy: policy, now: second)
		XCTAssertEqual(ledger.used_minutes, 20)
		ledger.reset_if_needed(policy: policy, now: first.addingTimeInterval(86400))
		XCTAssertEqual(ledger.used_minutes, 0)
	}
	func test_overlapping_windows_rejected() {
		var bad = policy; bad.rules[0].windows[1].start = "18:20"
		XCTAssertThrowsError(try bad.validate())
	}
	func test_bonus_updates_and_usage_entries_include_today() throws {
		let now = ISO8601DateFormatter().date(from: "2026-09-20T19:00:00Z")!
		var ledger = HomeLedger(day: policy.day_key(now), used_minutes: 35, segment_base: 35, generation: "active", bonuses: [:], history: ["2026-9-19":[20,60]])
		XCTAssertTrue(try ledger.set_bonus("steps", minutes: 80)); XCTAssertEqual(ledger.budget(180), 260); XCTAssertNil(ledger.generation)
		XCTAssertTrue(try ledger.set_bonus("steps", minutes: 120)); XCTAssertEqual(ledger.budget(180), 300)
		XCTAssertFalse(try ledger.set_bonus("steps", minutes: 120))
		let entries = ledger.usage_entries(policy: policy, now: now)
		XCTAssertEqual(entries.map(\.id), ["2026-9-19", "2026-9-20"])
		XCTAssertEqual(entries.last?.values["minutes"], .number(35)); XCTAssertEqual(entries.last?.values["budget"], .number(300))
	}
}
