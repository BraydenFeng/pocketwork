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
}
