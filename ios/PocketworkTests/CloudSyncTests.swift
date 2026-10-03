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
