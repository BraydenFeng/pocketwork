import XCTest
@testable import Pocketwork

final class RoutinePageEditingTests: XCTestCase {
	@MainActor
	func test_cancel_discards_inline_changes_and_keeps_detached_bindings_safe() {
		let original = AppDocument.blank()
		let editor = RoutinePageEditing()
		editor.begin(original)
		let heading = editor.block(original.blocks[0])
		heading.wrappedValue.title = "Changed title"
		XCTAssertEqual(editor.draft?.blocks[0].title, "Changed title")
		editor.cancel()
		XCTAssertEqual(heading.wrappedValue, original.blocks[0])
		editor.begin(original)
		XCTAssertEqual(editor.draft, original)
	}
	@MainActor
	func test_inline_block_changes_preserve_identity_and_engine_constraints() {
		let editor = RoutinePageEditing()
		editor.begin(AppDocument.blank())
		editor.add(.timer)
		editor.add(.schedule)
		XCTAssertEqual(editor.draft?.blocks.count, 2)
		let timer = editor.draft!.blocks[1]
		editor.move(timer.id, by: -1)
		XCTAssertEqual(editor.draft?.blocks.first?.id, timer.id)
		XCTAssertEqual(editor.block(timer).wrappedValue.minutes, 25)
	}
}
