import StoreKit
import XCTest
@testable import Pocketwork

@MainActor
final class PurchasePlanTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1_000)
	private func plan(_ environment: String? = nil, pro: Bool = true, expiration: String? = "1970-01-01T01:00:00.000Z") -> PurchasePlan {
		PurchasePlan(pro: pro, expires_at: expiration, configured: true, environment: environment)
	}

	func test_apple_environment_routing() throws {
		XCTAssertEqual(try SubscriptionController.purchase_environment(.production), .production)
		XCTAssertEqual(try SubscriptionController.purchase_environment(.sandbox), .sandbox)
		XCTAssertThrowsError(try SubscriptionController.purchase_environment(.xcode))
		XCTAssertEqual(PurchaseEnvironment.sandbox.verification_path, "api/subscription/sandbox")
		XCTAssertEqual(PurchaseEnvironment.production.verification_path, "api/subscription")
	}
	func test_test_response_cannot_unlock_production() {
		XCTAssertThrowsError(try plan("Sandbox").active_until(in: .production, now: now))
		XCTAssertThrowsError(try plan().active_until(in: .sandbox, now: now))
	}
	func test_expiration_and_inactive_plans() throws {
		XCTAssertNotNil(try plan().active_until(in: .production, now: now))
		XCTAssertNotNil(try plan("Sandbox").active_until(in: .sandbox, now: now))
		XCTAssertNil(try plan(pro: false).active_until(in: .production, now: now))
		XCTAssertNil(try plan(expiration: "1970-01-01T00:00:00Z").active_until(in: .production, now: now))
		XCTAssertNotNil(try plan(expiration: "1970-01-01T01:00:00Z").active_until(in: .production, now: now))
	}
	func test_invalid_responses_fail_closed() {
		XCTAssertThrowsError(try plan(expiration: nil).active_until(in: .production, now: now))
		XCTAssertThrowsError(try plan(expiration: "invalid").active_until(in: .production, now: now))
		XCTAssertThrowsError(try PurchasePlan(pro: true, expires_at: "1970-01-01T01:00:00Z", configured: false, environment: nil).active_until(in: .production, now: now))
	}
	func test_test_access_is_memory_only_and_cleared_between_accounts() throws {
		let name = "PurchasePlanTests." + UUID().uuidString
		let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
		defer { defaults.removePersistentDomain(forName: name) }
		let library = LibraryController(defaults: defaults)
		library.test_pro_until = .now.addingTimeInterval(60)
		XCTAssertTrue(library.has_pro)
		XCTAssertFalse(library.has_live_pro)
		XCTAssertFalse(LibraryController(defaults: defaults).has_pro)
		try library.switch_account(UUID().uuidString)
		XCTAssertFalse(library.has_pro)
		library.test_pro_until = .now.addingTimeInterval(60)
		library.purge_account()
		XCTAssertFalse(library.has_pro)
	}
}
