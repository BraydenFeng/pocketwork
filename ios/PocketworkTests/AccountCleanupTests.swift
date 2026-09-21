import XCTest
@testable import Pocketwork

final class AccountCleanupTests: XCTestCase {
	@MainActor func test_cleanup_continues_after_failure_and_reports_it() async {
		var completed: [String] = []
		let failures = await AccountCleanup.run([
			("location", { throw DocumentError.invalid("test failure") }),
			("sign-in", { completed.append("sign-in") }),
			("library", { completed.append("library") })
		])
		XCTAssertEqual(completed, ["sign-in", "library"])
		XCTAssertEqual(failures, ["location: test failure"])
	}
	@MainActor func test_successful_cleanup_has_no_failures() async {
		let failures = await AccountCleanup.run([("sign-in", {}), ("library", {})])
		XCTAssertTrue(failures.isEmpty)
	}
	func test_home_cleanup_erases_personal_state_and_accepts_corrupt_data() throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { do { try FileManager.default.removeItem(at: folder) } catch { XCTFail("Cleanup failed: \(error)") } }
		let file = folder.appendingPathComponent("home-state.json")
		let other = folder.appendingPathComponent("unrelated.json")
		try Data("keep".utf8).write(to: other)
		var original = HomeState()
		original.document = AppDocument.blank(); original.place = HomePlace(latitude: 1, longitude: 2)
		original.at_home = true; original.enabled = true; original.ledger.used_minutes = 20
		for data in [try JSONEncoder().encode(original), Data("broken".utf8)] {
			try data.write(to: file)
			try HomeEngine.erase_saved_state(in: folder)
			let cleared = try JSONDecoder().decode(HomeState.self, from: Data(contentsOf: file))
			XCTAssertNil(cleared.document); XCTAssertNil(cleared.place)
			XCTAssertFalse(cleared.enabled); XCTAssertFalse(cleared.at_home)
			XCTAssertEqual(cleared.ledger.used_minutes, 0)
			XCTAssertEqual(try Data(contentsOf: other), Data("keep".utf8))
			try HomeEngine.erase_saved_state(in: folder)
		}
	}
}
