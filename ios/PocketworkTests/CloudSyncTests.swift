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
