import XCTest
@testable import Pocketwork

final class ActivationTests: XCTestCase {
	private let social = AppGroup(id: "social", name: "Social")

	private func context(approved: Bool = true, groups: [AppGroup] = [], counts: [String: Int] = [:], own: Int = 0, home: Bool = true, always: Bool = true) -> ActivationContext {
		ActivationContext(screen_time_approved: approved, groups: groups, group_count: { counts[$0.id] ?? 0 }, own_app_count: own, has_home: home, always_location: always)
	}

	private func page(_ kinds: [BlockKind], groups: [String] = [], blocking: Bool = true) -> AppDocument {
		var document = AppDocument.blank()
		document.blocks = kinds.map { kind in
			var block = BlockDocument.make(kind)
			if kind == .screen_time { block.mode = .block; block.groups = groups.isEmpty ? nil : groups }
			return block
		}
		document.rules.block_during_focus = blocking
		return document
	}

	func test_schedule_asks_for_screen_time_then_each_groups_apps() {
		let document = page([.schedule, .screen_time], groups: ["Social", "Games"])
		XCTAssertEqual(Activation.missing(for: document, in: context(approved: false, groups: [social])), [.screen_time, .group_apps(id: "social", name: "Social"), .create_group(name: "Games")])
	}

	func test_a_ready_page_needs_nothing() {
		let document = page([.timer, .screen_time], groups: ["Social"])
		XCTAssertEqual(Activation.missing(for: document, in: context(groups: [social], counts: ["social": 3])), [])
	}

	func test_a_timer_that_blocks_nothing_needs_no_permissions() {
		let document = page([.timer], blocking: false)
		XCTAssertEqual(Activation.missing(for: document, in: context(approved: false, home: false, always: false)), [])
	}

	func test_a_page_without_groups_needs_its_own_apps() {
		let document = page([.timer, .screen_time])
		XCTAssertEqual(Activation.missing(for: document, in: context()), [.own_apps])
		XCTAssertEqual(Activation.missing(for: document, in: context(own: 2)), [])
	}

	func test_home_allowance_also_needs_home_and_always_location() {
		var document = page([.schedule, .screen_time], groups: ["Social"])
		document.home_allowance = HomePolicy(timezone: "America/Los_Angeles", away_usage_counts: false, outside_windows: "unrestricted", rules: [HomeDayRule(days: [1, 2, 3, 4, 5, 6, 7], allowance_minutes: 30, windows: [HomeWindow(start: "18:00", end: "20:00")])])
		XCTAssertEqual(Activation.missing(for: document, in: context(groups: [social], counts: ["social": 1], home: false, always: false)), [.home, .always_location])
		XCTAssertEqual(Activation.missing(for: document, in: context(groups: [social], counts: ["social": 1])), [])
	}
}
