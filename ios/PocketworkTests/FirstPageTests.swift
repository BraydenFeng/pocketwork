import XCTest
@testable import Pocketwork

final class FirstPageTests: XCTestCase {
	func test_the_sentence_becomes_a_scheduled_blocker_that_needs_nothing_else() throws {
		let document = try FirstPage.document(group: "Distractions", start: "21:00", end: "07:00", days: [5, 1, 2, 3, 4])
		XCTAssertEqual(document.name, "No distractions 9 PM–7 AM")
		XCTAssertEqual(document.schedule?.days, [1, 2, 3, 4, 5]); XCTAssertEqual(document.schedule?.start, "21:00"); XCTAssertEqual(document.schedule?.end, "07:00")
		XCTAssertEqual(document.shield?.group_names, ["Distractions"]); XCTAssertEqual(document.shield?.shield_mode, .block)
		XCTAssertTrue(document.rules.block_during_focus); XCTAssertEqual(document.enabled, false); XCTAssertTrue(document.is_standing)
		let ready = ActivationContext(screen_time_approved: true, groups: [AppGroup(id: "distractions", name: "Distractions")], group_count: { _ in 2 }, own_app_count: 0, has_home: false, always_location: false)
		XCTAssertEqual(Activation.missing(for: document, in: ready), [])
	}

	func test_a_window_ios_cannot_monitor_is_refused() {
		XCTAssertThrowsError(try FirstPage.document(group: "Distractions", start: "21:00", end: "21:00", days: [1]))
		XCTAssertThrowsError(try FirstPage.document(group: "Distractions", start: "21:00", end: "21:10", days: [1]))
	}

	func test_day_choices_read_as_part_of_the_sentence() {
		XCTAssertEqual(FirstPage.day_label([5, 4, 3, 2, 1]), "on school nights")
		XCTAssertEqual(FirstPage.day_label(ScheduleWindow.all_days), "every day")
		XCTAssertEqual(FirstPage.day_label([2, 4]), "on Mon, Wed")
	}

	func test_the_trial_blocks_the_same_apps_for_fifteen_minutes() throws {
		let page = try FirstPage.document(group: "Distractions", start: "21:00", end: "07:00", days: ScheduleWindow.all_days)
		let trial = try FirstPage.trial(of: page)
		XCTAssertEqual(trial.focus_minutes, 15); XCTAssertEqual(trial.shield, page.shield)
		XCTAssertNotEqual(trial.id, page.id); XCTAssertFalse(trial.is_standing); XCTAssertTrue(trial.rules.block_during_focus)
	}
}
