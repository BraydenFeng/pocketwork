import XCTest
@testable import Pocketwork

final class CloudSyncTests: XCTestCase {
	func test_deletion_beats_same_time_edit() throws {
		let now = Date()
		let doc = AppDocument.blank()
		let local = try ToolLibrary.empty.upserting(doc, now: now)
		let remote = local.deleting(doc.id, now: now)
		XCTAssertTrue(try local.merging(remote, now: now).tools.isEmpty)
	}
	func test_newer_remote_routine_and_group_deletion_win() throws {
		let now = Date()
		var doc = AppDocument.blank()
		let local = try ToolLibrary.empty.upserting(doc, now: now.addingTimeInterval(-60)).adding_group("Social")
		doc.name = "From website"
		var remote = try local.upserting(doc, now: now)
		remote.groups = []; remote.groups_updated_at = ToolLibrary.iso_formatter.string(from: now.addingTimeInterval(1))
		let merged = try local.merging(remote)
		XCTAssertEqual(merged.find(doc.id)?.name, "From website")
		XCTAssertEqual(merged.groups, [])
		XCTAssertEqual(try merged.merging(remote), merged)
	}
	func test_group_app_choices_merge_per_group() throws {
		let now = Date()
		let base = try ToolLibrary.empty.adding_group("Social").adding_group("Games")
		let social = try XCTUnwrap(base.group(named: "Social")?.id), games = try XCTUnwrap(base.group(named: "Games")?.id)
		// The phone picks Social's apps; the iPad renames Social later and picks Games' apps.
		let phone = try base.setting_group_apps(social, apps: "cGhvbmU=", now: now)
		var tablet = try base.renaming_group(social, to: "Social media", now: now.addingTimeInterval(30))
		tablet = try tablet.setting_group_apps(games, apps: "dGFibGV0", now: now.addingTimeInterval(10))
		XCTAssertEqual(phone.groups_updated_at, base.groups_updated_at, "app choices never decide which list of names wins")
		let merged = try phone.merging(tablet)
		XCTAssertEqual(merged.group(id: social)?.name, "Social media")
		XCTAssertEqual(merged.group(id: social)?.apps, "cGhvbmU=")
		XCTAssertEqual(merged.group(id: games)?.apps, "dGFibGV0")
		XCTAssertEqual(try tablet.merging(phone), merged)
		XCTAssertEqual(try merged.merging(phone), merged)
		let renamed = try merged.renaming_group(games, to: "Play", now: now.addingTimeInterval(60))
		XCTAssertEqual(renamed.group(id: games)?.apps, "dGFibGV0", "renaming keeps the group's app choices")
		XCTAssertThrowsError(try base.setting_group_apps(social, apps: String(repeating: "A", count: ToolLibrary.max_group_apps + 4), now: now))
	}
	private func gate_page(_ groups: [String]) -> AppDocument {
		var document = AppDocument.blank()
		document.schema_version = 3
		let config = { (label: String, groups: [String]?) in BehaviorConfig(label: label, value: 1, minutes: 5, time: "18:00", days: [1, 2, 3, 4, 5, 6, 7], message: "", operator: "gte", groups: groups) }
		document.behaviors = BehaviorGraph(nodes: [
			BehaviorNode(id: "tap", kind: "button", x: 0, y: 0, config: config("Tap", nil)),
			BehaviorNode(id: "gate", kind: "app_gate", x: 200, y: 0, config: config("Gate", groups)),
		], connections: [BehaviorEdge(from: "tap", output: "pressed", to: "gate", input: "closed")])
		return document
	}

	func test_app_gate_groups_count_as_used_and_follow_renames() throws {
		var library = try ToolLibrary.empty.adding_group("Distractions")
		library = try library.upserting(gate_page(["Distractions"]), now: Date())
		XCTAssertEqual(library.routines_using(group: "distractions").count, 1)
		let id = try XCTUnwrap(library.group(named: "Distractions")?.id)
		XCTAssertThrowsError(try library.removing_group(id))
		let renamed = try library.renaming_group(id, to: "Social", now: Date().addingTimeInterval(1))
		XCTAssertEqual(renamed.tools.first?.document.behaviors?.nodes.last?.config.groups, ["Social"])
	}

	func test_copies_and_imports_start_switched_off() throws {
		var routine = AppDocument.blank()
		routine.blocks = [BlockDocument.make(.schedule), BlockDocument.make(.screen_time)]
		routine.rules.block_during_focus = true
		routine.enabled = true
		let library = try ToolLibrary.empty.upserting(routine, now: Date())
		XCTAssertEqual(try library.duplicating(routine.id, now: Date()).document.enabled, false)
		XCTAssertEqual(try library.importing(routine, now: Date()).document.enabled, false)
	}

	func test_signing_in_again_keeps_signed_out_pages_up_to_the_limit() throws {
		let now = Date()
		var account = ToolLibrary.empty
		for _ in 0..<2 { account = try account.upserting(AppDocument.blank(), now: now) }
		var guest = try ToolLibrary.empty.adding_group("Games")
		var games = AppDocument.blank()
		games.blocks = [BlockDocument.make(.timer), { var block = BlockDocument.make(.screen_time); block.mode = .block; block.groups = ["Games"]; return block }()]
		guest = try guest.upserting(games, now: now.addingTimeInterval(10))
		guest = try guest.upserting(AppDocument.blank(), now: now)
		let adopted = try account.adopting_guest(guest, limit: 3, now: now)
		XCTAssertEqual(adopted.library.tools.count, 3)
		XCTAssertNotNil(adopted.library.find(games.id), "the newest signed-out page is adopted first")
		XCTAssertEqual(adopted.library.group(named: "Games")?.id, guest.group(named: "Games")?.id, "the group keeps its id, which its saved app choices use")
		XCTAssertEqual(adopted.leftover.tools.count, 1)
	}

	func test_a_merge_keeps_groups_that_pages_still_name() throws {
		let now = Date()
		var page = AppDocument.blank()
		page.blocks = [BlockDocument.make(.timer), { var block = BlockDocument.make(.screen_time); block.mode = .block; block.groups = ["Games"]; return block }()]
		let web = try ToolLibrary.empty.adding_group("Games").upserting(page, now: now)
		var phone = try ToolLibrary.empty.adding_group("Social")
		phone.groups_updated_at = ToolLibrary.iso_formatter.string(from: now.addingTimeInterval(60))
		let merged = try web.merging(phone)
		XCTAssertEqual(Set(merged.groups?.map(\.name) ?? []), ["Games", "Social"])
	}

	@MainActor
	func test_account_libraries_are_isolated() throws {
		let name = UUID().uuidString
		let defaults = UserDefaults(suiteName: name)!
		defer { defaults.removePersistentDomain(forName: name) }
		let controller = LibraryController(defaults: defaults)
		XCTAssertNotNil(controller.create_blank())
		try controller.switch_account("alice")
		XCTAssertEqual(controller.library.tools.count, 1)
		try controller.switch_account(nil)
		XCTAssertTrue(controller.library.tools.isEmpty)
		try controller.switch_account("bob")
		XCTAssertTrue(controller.library.tools.isEmpty)
		try controller.switch_account("alice")
		XCTAssertEqual(controller.library.tools.count, 1)
	}
}
