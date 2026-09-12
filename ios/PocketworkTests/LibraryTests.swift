import XCTest
@testable import Pocketwork

final class LibraryTests: XCTestCase {
	private let now = Date(timeIntervalSince1970: 1_800_000_000)

	private func starter() throws -> AppDocument {
		let url = try XCTUnwrap(Bundle.main.url(forResource: "starter.pocketwork", withExtension: "json"))
		return try AppDocument.decode(Data(contentsOf: url))
	}

	private func fresh_defaults() throws -> UserDefaults {
		let name = "PocketworkTests.\(UUID().uuidString)"
		let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
		defaults.removePersistentDomain(forName: name)
		return defaults
	}

	func test_reads_the_web_editor_library_format() throws {
		let encoded = String(decoding: try JSONEncoder().encode(try starter()), as: UTF8.self)
		let json = """
		{"schema_version":1,"tools":[{"document":\(encoded),"updated_at":"2026-09-10T12:00:00.000Z"}]}
		"""
		let library = try ToolLibrary.decode(Data(json.utf8))
		XCTAssertEqual(library.tools.count, 1)
		XCTAssertEqual(library.find("my-focus-space")?.name, "My focus space")
		XCTAssertNotNil(library.tools[0].updated_date)
		XCTAssertEqual(try ToolLibrary.decode(try library.encoded()), library)
	}

	func test_refuses_unreadable_libraries() throws {
		XCTAssertThrowsError(try ToolLibrary.decode(Data("broken".utf8)))
		XCTAssertThrowsError(try ToolLibrary.decode(Data("{\"schema_version\":2,\"tools\":[]}".utf8)))
		let entry = LibraryEntry(document: try starter(), updated_at: "yesterday")
		XCTAssertThrowsError(try ToolLibrary(schema_version: 1, tools: [entry]).encoded())
		let duplicate = LibraryEntry(document: try starter(), updated_at: "2026-09-10T12:00:00.000Z")
		XCTAssertThrowsError(try ToolLibrary(schema_version: 1, tools: [duplicate, duplicate]).encoded())
	}

	func test_upserts_deletes_duplicates_and_imports() throws {
		var library = try ToolLibrary.empty.upserting(try starter(), now: now)
		var renamed = try starter(); renamed.name = "Renamed"
		library = try library.upserting(renamed, now: now.addingTimeInterval(60))
		XCTAssertEqual(library.tools.count, 1)
		XCTAssertEqual(library.find("my-focus-space")?.name, "Renamed")
		XCTAssertEqual(library.deleting("my-focus-space").tools.count, 0)
		let copied = try library.duplicating("my-focus-space", now: now)
		XCTAssertNotEqual(copied.document.id, "my-focus-space")
		XCTAssertEqual(copied.document.name, "Renamed copy")
		XCTAssertEqual(copied.library.tools.count, 2)
		XCTAssertThrowsError(try library.duplicating("missing", now: now))
		let imported = try library.importing(try starter(), now: now)
		XCTAssertNotEqual(imported.document.id, "my-focus-space")
		XCTAssertEqual(imported.library.tools.count, 2)
	}

	func test_lists_most_recently_edited_first() throws {
		var older = try starter(); older.id = "older"
		var newer = try starter(); newer.id = "newer"
		let library = try ToolLibrary.empty.upserting(older, now: now).upserting(newer, now: now.addingTimeInterval(1))
		XCTAssertEqual(library.sorted.map(\.document.id), ["newer", "older"])
	}

	func test_caps_the_number_of_tools() throws {
		var library = ToolLibrary.empty
		for index in 0..<ToolLibrary.max_tools {
			var document = try starter(); document.id = "tool-\(index)"
			library = try library.upserting(document, now: now)
		}
		var extra = try starter(); extra.id = "one-more"
		XCTAssertThrowsError(try library.upserting(extra, now: now))
	}

	func test_bundled_routines_are_valid_and_enforce_something() throws {
		let catalog = try RoutineCatalog.bundled()
		XCTAssertEqual(catalog.routines.count, 6)
		XCTAssertEqual(catalog.routines.filter(\.document.is_standing).count, 2)
		for routine in catalog.routines {
			XCTAssertTrue(routine.document.rules.block_during_focus, routine.name)
			let first = routine.instantiate(), second = routine.instantiate()
			XCTAssertNotEqual(first.id, second.id)
			XCTAssertNoThrow(try first.validate())
		}
	}

	func test_removing_a_timer_switches_off_dependent_rules() throws {
		let document = try starter().removing_block("focus")
		XCTAssertFalse(document.rules.block_during_focus)
		XCTAssertFalse(document.rules.notify_on_complete)
		XCTAssertNoThrow(try document.validate())
		let single = AppDocument.blank()
		XCTAssertEqual(single.removing_block(single.blocks[0].id), single)
		XCTAssertTrue(try starter().can_add(.note))
		XCTAssertFalse(try starter().can_add(.timer))
	}

	func test_summaries_read_in_plain_words() throws {
		XCTAssertEqual(ToolCopy.summary(try starter()), "25 min session · blocks apps · 3 tasks")
		XCTAssertEqual(ToolCopy.summary(AppDocument.blank()), "1 block")
		let bedtime = try XCTUnwrap(RoutineCatalog.bundled().routines.first(where: { $0.template_id == "bedtime" })).document
		XCTAssertEqual(ToolCopy.summary(bedtime), "Every day · 10 PM to 7 AM · blocks apps · 2 tasks")
		let entry = LibraryEntry(document: try starter(), updated_at: ToolLibrary.iso_formatter.string(from: now.addingTimeInterval(-300)))
		XCTAssertEqual(ToolCopy.edited(entry, now: now), "Edited 5 min ago")
		XCTAssertEqual(ToolCopy.edited(entry, now: now.addingTimeInterval(86_400)), "Edited yesterday")
	}

	@MainActor func test_controller_upgrades_the_old_single_tool_and_persists() throws {
		let defaults = try fresh_defaults()
		defaults.set(try JSONEncoder().encode(try starter()), forKey: LibraryController.legacy_key)
		let controller = LibraryController(defaults: defaults)
		XCTAssertEqual(controller.sorted_tools.count, 1)
		XCTAssertNotNil(defaults.data(forKey: LibraryController.legacy_key), "the old key stays until a save succeeds")
		let created = try XCTUnwrap(controller.create_blank())
		XCTAssertEqual(controller.sorted_tools.count, 2)
		XCTAssertNil(defaults.data(forKey: LibraryController.legacy_key))
		XCTAssertEqual(LibraryController(defaults: defaults).tool(created.id)?.name, "My new tool")
		controller.delete(created.id)
		XCTAssertEqual(LibraryController(defaults: defaults).sorted_tools.count, 1)
	}

	@MainActor func test_controller_never_overwrites_unreadable_data() throws {
		let defaults = try fresh_defaults()
		defaults.set(Data("broken".utf8), forKey: LibraryController.library_key)
		let controller = LibraryController(defaults: defaults)
		XCTAssertTrue(controller.storage_blocked)
		XCTAssertNil(controller.create_blank())
		XCTAssertEqual(defaults.data(forKey: LibraryController.library_key), Data("broken".utf8))
		controller.replace_unreadable()
		XCTAssertNotNil(controller.create_blank())
		XCTAssertEqual(LibraryController(defaults: defaults).sorted_tools.count, 1)
	}
}
