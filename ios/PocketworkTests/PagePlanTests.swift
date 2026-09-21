import XCTest
@testable import Pocketwork

@MainActor
final class PagePlanTests: XCTestCase {
	func testFreeSlotsAndCancellationKeepOldPages() throws {
		let name = "PagePlanTests." + UUID().uuidString
		let defaults = try XCTUnwrap(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
		let controller = LibraryController(defaults: defaults)
		for _ in 0..<3 { XCTAssertNotNil(controller.create_blank()) }
		XCTAssertNil(controller.create_blank())
		controller.pro_until = Date().addingTimeInterval(60)
		let fourth = try XCTUnwrap(controller.create_blank())
		controller.pro_until = .distantPast
		var edited = fourth; edited.name = "Still mine"
		XCTAssertTrue(controller.save(edited)); XCTAssertNil(controller.create_blank())
		controller.delete(fourth.id); controller.delete(controller.library.tools[0].id)
		XCTAssertNotNil(controller.create_blank())
	}
	func testAccountPurgeDoesNotDeleteAnotherAccountsCache() throws {
		let name = "PagePlanTests." + UUID().uuidString
		let defaults = try XCTUnwrap(UserDefaults(suiteName: name)); defer { defaults.removePersistentDomain(forName: name) }
		let controller = LibraryController(defaults: defaults)
		try controller.switch_account("alice"); XCTAssertNotNil(controller.create_blank())
		defaults.set(Data([1]), forKey: "behaviors.v1.alice.test")
		defaults.set(Data([2]), forKey: "behaviors.v1.bob.test")
		var history = SessionHistory(); history.record(minutes: 20, at: .now); try history.save(to: defaults)
		controller.purge_account()
		XCTAssertNil(defaults.data(forKey: "tool_library.v1.alice")); XCTAssertNil(defaults.data(forKey: "behaviors.v1.alice.test"))
		XCTAssertNil(defaults.data(forKey: SessionHistory.key))
		XCTAssertNotNil(defaults.data(forKey: "behaviors.v1.bob.test")); XCTAssertEqual(controller.library.tools.count, 0)
	}
}
