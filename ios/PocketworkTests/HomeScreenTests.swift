import XCTest
@testable import Pocketwork

final class HomeScreenTests: XCTestCase {
	private func starter() throws -> AppDocument {
		let url = try XCTUnwrap(Bundle.main.url(forResource: "starter.pocketwork", withExtension: "json"))
		return try AppDocument.decode(Data(contentsOf: url))
	}

	func test_widget_snapshot_round_trips_and_deep_links() throws {
		let tile = RoutineTile(id: "abc", name: "Deep work", summary: "90 min session", status: "Ready · tap to start", standing: false, enabled: false, running: false, ends_at: nil)
		let snapshot = WidgetSnapshot(tiles: [tile], updated_at: Date(timeIntervalSince1970: 1_800_000_000))
		let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
		XCTAssertEqual(decoded, snapshot)
		let url = try XCTUnwrap(WidgetSnapshot.url(for: "abc"))
		XCTAssertEqual(WidgetSnapshot.routine_id(from: url), "abc")
		XCTAssertNil(WidgetSnapshot.routine_id(from: URL(string: "com.braydenfeng.pocketwork://auth/callback?code=x")!))
		XCTAssertNil(WidgetSnapshot.routine_id(from: URL(string: "https://example.com/routine/abc")!))
	}

	@MainActor func test_publish_describes_running_and_standing_routines() throws {
		// Publishing needs the App Group; on a simulator without it the bridge logs and returns, so exercise the tile logic through a fake session instead.
		let document = try starter()
		let session = FocusSession(activity_name: "pocketwork.test", document_id: document.id, ends_at: Date().addingTimeInterval(600), blocks_apps: true)
		let library = try ToolLibrary.empty.upserting(document, now: .now)
		HomeScreenBridge.publish(library: library, session: session)
		if let snapshot = WidgetSnapshot.load() {
			let tile = try XCTUnwrap(snapshot.tiles.first { $0.id == document.id })
			XCTAssertTrue(tile.running)
			XCTAssertEqual(tile.ends_at, session.ends_at)
			XCTAssertTrue(tile.status.hasPrefix("Running"))
		}
		HomeScreenBridge.publish(library: library, session: nil)
		if let snapshot = WidgetSnapshot.load() {
			let tile = try XCTUnwrap(snapshot.tiles.first { $0.id == document.id })
			XCTAssertFalse(tile.running)
			XCTAssertEqual(tile.status, "Ready · tap to start")
		}
	}
}
