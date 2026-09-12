import XCTest
@testable import Pocketwork

final class DocumentTests: XCTestCase {
	private func sample() throws -> Data {
		let url = try XCTUnwrap(Bundle.main.url(forResource: "starter.pocketwork", withExtension: "json"))
		return try Data(contentsOf: url)
	}

	func test_editor_fixture_decodes() throws {
		let document = try AppDocument.decode(sample())
		XCTAssertEqual(document.name, "My focus space")
		XCTAssertEqual(document.focus_minutes, 25)
		XCTAssertTrue(document.rules.block_during_focus)
	}

	func test_round_trip() throws {
		let document = try AppDocument.decode(sample())
		XCTAssertEqual(try AppDocument.decode(JSONEncoder().encode(document)), document)
	}

	func test_rejects_unsupported_version() throws {
		var object = try XCTUnwrap(JSONSerialization.jsonObject(with: sample()) as? [String: Any])
		object["schema_version"] = 2
		XCTAssertThrowsError(try AppDocument.decode(JSONSerialization.data(withJSONObject: object)))
	}

	func test_rejects_executable_fields() throws {
		var object = try XCTUnwrap(JSONSerialization.jsonObject(with: sample()) as? [String: Any])
		object["script"] = "doSomething()"
		XCTAssertThrowsError(try AppDocument.decode(JSONSerialization.data(withJSONObject: object)))
	}

	func test_rejects_short_screen_time_intervals() throws {
		var object = try XCTUnwrap(JSONSerialization.jsonObject(with: sample()) as? [String: Any])
		var blocks = try XCTUnwrap(object["blocks"] as? [[String: Any]])
		blocks[1]["minutes"] = 5
		object["blocks"] = blocks
		XCTAssertThrowsError(try AppDocument.decode(JSONSerialization.data(withJSONObject: object)))
	}

	func test_rejects_duplicate_ids() throws {
		var object = try XCTUnwrap(JSONSerialization.jsonObject(with: sample()) as? [String: Any])
		var blocks = try XCTUnwrap(object["blocks"] as? [[String: Any]])
		blocks[1]["id"] = "welcome"
		object["blocks"] = blocks
		XCTAssertThrowsError(try AppDocument.decode(JSONSerialization.data(withJSONObject: object)))
	}

	func test_rejects_oversized_file() {
		XCTAssertThrowsError(try AppDocument.decode(Data(repeating: 32, count: 100_001)))
	}

	func test_deadline_survives_suspension() {
		let start = Date(timeIntervalSince1970: 0)
		let session = FocusSession(activity_name: "test", document_id: "tool", ends_at: start.addingTimeInterval(900), blocks_apps: true)
		XCTAssertEqual(session.remaining(at: start.addingTimeInterval(60)), 840)
		XCTAssertFalse(session.has_ended(at: start.addingTimeInterval(899)))
		XCTAssertTrue(session.has_ended(at: start.addingTimeInterval(900)))
		XCTAssertEqual(session.remaining(at: start.addingTimeInterval(5000)), 0)
	}
}
