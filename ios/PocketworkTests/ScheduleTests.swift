import XCTest
import DeviceActivity
@testable import Pocketwork

final class ScheduleTests: XCTestCase {
	private var calendar: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return calendar }
	private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
		calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
	}
	private let nightly = BlockDocument(id: "window", type: .schedule, title: "Every night", subtitle: nil, minutes: nil, items: nil, target: nil, text: nil, days: [1, 2, 3, 4, 5, 6, 7], start: "22:00", end: "07:00")
	private let weekdays = BlockDocument(id: "window", type: .schedule, title: "Weekdays", subtitle: nil, minutes: nil, items: nil, target: nil, text: nil, days: [2, 3, 4, 5, 6], start: "09:00", end: "17:00")

	private func standing(blocks: [BlockDocument]? = nil, rules: RuleDocument = RuleDocument(block_during_focus: true, notify_on_complete: false), enabled: Bool? = false) -> AppDocument {
		let shield = BlockDocument(id: "shield", type: .screen_time, title: "Feeds off", subtitle: nil, minutes: nil, items: nil, target: nil, text: nil, days: nil, start: nil, end: nil)
		return AppDocument(schema_version: 1, id: "bedtime", name: "Bedtime", description: "", blocks: blocks ?? [nightly, shield], rules: rules, enabled: enabled)
	}

	func test_accepts_a_standing_routine_and_round_trips_it_strictly() throws {
		let document = standing()
		XCTAssertNoThrow(try document.validate())
		XCTAssertTrue(document.is_standing)
		XCTAssertEqual(try AppDocument.decode(JSONEncoder().encode(document)), document)
	}

	func test_rejects_invalid_standing_routines() throws {
		let timer = BlockDocument.make(.timer)
		XCTAssertThrowsError(try standing(blocks: standing().blocks + [timer]).validate())
		XCTAssertThrowsError(try standing(rules: RuleDocument(block_during_focus: false, notify_on_complete: false)).validate())
		XCTAssertThrowsError(try standing(blocks: [nightly]).validate())
		var same = nightly; same.end = "22:00"
		XCTAssertThrowsError(try standing(blocks: [same, standing().blocks[1]]).validate())
		var short = nightly; short.end = "22:10"
		XCTAssertThrowsError(try standing(blocks: [short, standing().blocks[1]]).validate())
		var twice = nightly; twice.days = [2, 2]
		XCTAssertThrowsError(try standing(blocks: [twice, standing().blocks[1]]).validate())
		var session = AppDocument.blank(); session.enabled = true
		XCTAssertThrowsError(try session.validate())
	}

	func test_removing_the_schedule_drops_the_switch() throws {
		let document = standing(enabled: true).removing_block("window")
		XCTAssertNil(document.enabled)
		XCTAssertFalse(document.rules.block_during_focus)
		XCTAssertNoThrow(try document.validate())
		XCTAssertFalse(standing().can_add(.schedule))
	}

	func test_window_status_including_past_midnight() {
		// Wednesday 2026-09-16.
		XCTAssertFalse(ScheduleWindow.status(nightly, at: date(2026, 9, 16, 20, 30), calendar: calendar).active)
		let late = ScheduleWindow.status(nightly, at: date(2026, 9, 16, 23, 0), calendar: calendar)
		XCTAssertTrue(late.active)
		XCTAssertEqual(late.change_at, date(2026, 9, 17, 7, 0))
		XCTAssertTrue(ScheduleWindow.status(nightly, at: date(2026, 9, 17, 6, 59), calendar: calendar).active)
		XCTAssertFalse(ScheduleWindow.status(nightly, at: date(2026, 9, 17, 7, 0), calendar: calendar).active)
		XCTAssertEqual(ScheduleWindow.status(nightly, at: date(2026, 9, 16, 20, 30), calendar: calendar).change_at, date(2026, 9, 16, 22, 0))
		XCTAssertEqual(ScheduleWindow.status(weekdays, at: date(2026, 9, 18, 18, 0), calendar: calendar).change_at, date(2026, 9, 21, 9, 0))
		XCTAssertFalse(ScheduleWindow.status(weekdays, at: date(2026, 9, 19, 12, 0), calendar: calendar).active)
		XCTAssertTrue(ScheduleWindow.status(weekdays, at: date(2026, 9, 16, 12, 0), calendar: calendar).active)
	}

	func test_plain_words_match_the_web_editor() {
		XCTAssertEqual(ScheduleWindow.format_days([1, 2, 3, 4, 5, 6, 7]), "Every day")
		XCTAssertEqual(ScheduleWindow.format_days([2, 3, 4, 5, 6]), "Weekdays")
		XCTAssertEqual(ScheduleWindow.format_days([7, 1]), "Weekends")
		XCTAssertEqual(ScheduleWindow.format_days([2, 4]), "Mon, Wed")
		XCTAssertEqual(ScheduleWindow.format_clock("22:00"), "10 PM")
		XCTAssertEqual(ScheduleWindow.format_clock("09:30"), "9:30 AM")
		XCTAssertEqual(ScheduleWindow.describe(nightly), "Every day · 10 PM to 7 AM")
		XCTAssertEqual(ScheduleWindow.describe_status(nightly, enabled: false, at: date(2026, 9, 16, 20, 30), calendar: calendar), "Off · switch it on to start enforcing")
		XCTAssertEqual(ScheduleWindow.describe_status(nightly, enabled: true, at: date(2026, 9, 16, 20, 30), calendar: calendar), "On · next 10 PM")
		XCTAssertEqual(ScheduleWindow.describe_status(nightly, enabled: true, at: date(2026, 9, 16, 23, 0), calendar: calendar), "Active now · until tomorrow 7 AM")
		XCTAssertEqual(ScheduleWindow.describe_status(weekdays, enabled: true, at: date(2026, 9, 18, 18, 0), calendar: calendar), "On · next Mon 9 AM")
	}

	func test_activity_names_round_trip_routine_ids() {
		let id = UUID().uuidString
		let activity = SharedStore.standing_activity(id, weekday: 3)
		XCTAssertEqual(SharedStore.standing_id(from: activity), id)
		XCTAssertNil(SharedStore.standing_id(from: DeviceActivityName("pocketwork.abc")))
	}
}
