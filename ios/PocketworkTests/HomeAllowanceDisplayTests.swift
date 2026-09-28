import XCTest
@testable import Pocketwork

@MainActor
final class HomeAllowanceDisplayTests: XCTestCase {
	private let monday = ISO8601DateFormatter().date(from: "2026-09-15T01:10:00Z")!
	private var policy: HomePolicy {
		HomePolicy(timezone: "America/Los_Angeles", away_usage_counts: false, outside_windows: "unrestricted", rules: [
			HomeDayRule(days: [2], allowance_minutes: 30, windows: [HomeWindow(start: "18:00", end: "20:00")]),
			HomeDayRule(days: [1, 3, 4, 5, 6, 7], allowance_minutes: 60, windows: [HomeWindow(start: "18:00", end: "20:00")])
		])
	}
	private func state(used: Int = 0) -> HomeState {
		var value = HomeState()
		value.ledger.day = policy.day_key(monday)
		value.ledger.used_minutes = used
		return value
	}

	func test_refresh_reads_new_usage_without_changing_the_ledger() async throws {
		var saved = state(used: 3)
		let display = HomeAllowanceDisplay(read_state: { saved }, now: { self.monday })
		XCTAssertNil(display.remaining)
		try await display.refresh(policy: policy)
		XCTAssertEqual(display.remaining, 27)
		saved.ledger.used_minutes = 8
		let original = saved.ledger
		try await display.refresh(policy: policy)
		XCTAssertEqual(display.remaining, 22)
		XCTAssertEqual(saved.ledger, original)
	}

	func test_refresh_includes_bonuses_and_never_shows_negative_time() async throws {
		var saved = state(used: 20)
		saved.ledger.bonuses = ["gym": 15]
		let display = HomeAllowanceDisplay(read_state: { saved }, now: { self.monday })
		try await display.refresh(policy: policy)
		XCTAssertEqual(display.remaining, 25)
		saved.ledger.used_minutes = 50
		try await display.refresh(policy: policy)
		XCTAssertEqual(display.remaining, 0)
	}

	func test_refresh_after_midnight_uses_the_new_day_without_yesterdays_bonus() async throws {
		var saved = state(used: 20)
		saved.ledger.bonuses = ["gym": 15]
		var date = monday
		let display = HomeAllowanceDisplay(read_state: { saved }, now: { date })
		try await display.refresh(policy: policy)
		XCTAssertEqual(display.remaining, 25)
		date = ISO8601DateFormatter().date(from: "2026-09-15T07:00:00Z")!
		try await display.refresh(policy: policy)
		XCTAssertEqual(display.remaining, 60)
		XCTAssertEqual(saved.ledger.used_minutes, 20)
	}

	func test_refresh_uses_updated_allowance_settings() async throws {
		let saved = state(used: 10)
		let display = HomeAllowanceDisplay(read_state: { saved }, now: { self.monday })
		try await display.refresh(policy: policy)
		XCTAssertEqual(display.remaining, 20)
		var updated = policy
		updated.rules[0].allowance_minutes = 45
		try await display.refresh(policy: updated)
		XCTAssertEqual(display.remaining, 35)
	}

	func test_failed_read_keeps_the_last_value_and_can_retry() async throws {
		enum Failure: Error { case expected }
		var saved = state(used: 5)
		var fail = false
		let display = HomeAllowanceDisplay(read_state: {
			if fail { throw Failure.expected }
			return saved
		}, now: { self.monday })
		try await display.refresh(policy: policy)
		fail = true
		do { try await display.refresh(policy: policy); XCTFail("Expected read failure") }
		catch Failure.expected {} catch { XCTFail("Unexpected read failure: \(error)") }
		XCTAssertEqual(display.remaining, 25)
		fail = false
		saved.ledger.used_minutes = 9
		try await display.refresh(policy: policy)
		XCTAssertEqual(display.remaining, 21)
	}

	func test_slow_read_does_not_queue_overlapping_refreshes() async throws {
		let started = expectation(description: "snapshot read started")
		let skipped = expectation(description: "overlapping refresh skipped")
		let saved = state(used: 7)
		var reads = 0
		var pending: [CheckedContinuation<HomeState, Never>] = []
		let display = HomeAllowanceDisplay(read_state: {
			reads += 1
			return await withCheckedContinuation { continuation in
				pending.append(continuation)
				started.fulfill()
			}
		}, now: { self.monday })
		let first = Task { try await display.refresh(policy: policy) }
		await fulfillment(of: [started], timeout: 2)
		let second = Task {
			defer { skipped.fulfill() }
			try await display.refresh(policy: policy)
		}
		await fulfillment(of: [skipped], timeout: 2)
		XCTAssertEqual(reads, 1)
		for continuation in pending { continuation.resume(returning: saved) }
		try await first.value
		try await second.value
		XCTAssertEqual(display.remaining, 23)
	}
}
