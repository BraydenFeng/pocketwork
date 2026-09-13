import Combine
import SwiftUI

@MainActor
final class RoutinePageEditing: ObservableObject {
	@Published var draft: AppDocument?
	@Published var saving = false
	@Published var failure: String?
	private var original: AppDocument?
	var active: Bool { draft != nil }
	func begin(_ document: AppDocument) { original = document; draft = document }
	func cancel() { draft = nil; original = nil }
	func block(_ fallback: BlockDocument) -> Binding<BlockDocument> {
		let id = fallback.id
		return Binding(get: { self.draft?.blocks.first { $0.id == id } ?? fallback }, set: { value in
			if let index = self.draft?.blocks.firstIndex(where: { $0.id == id }) { self.draft?.blocks[index] = value }
		})
	}
	func add(_ kind: BlockKind) {
		guard draft?.can_add(kind) == true else { return }
		draft?.blocks.append(BlockDocument.make(kind))
		if kind == .schedule { draft?.enabled = false }
		if draft?.has_engine == true && draft?.has_screen_time == true { draft?.rules.block_during_focus = true }
	}
	func move(_ id: String, by offset: Int) {
		guard let index = draft?.blocks.firstIndex(where: { $0.id == id }), let count = draft?.blocks.count, (0..<count).contains(index + offset) else { return }
		draft?.blocks.swapAt(index, index + offset)
	}
	func save(library: LibraryController, sessions: SessionController) async {
		guard !saving, !sessions.is_busy, var document = draft, let original else { return }
		guard library.tool(original.id) == original else { failure = "This routine changed while you were editing. Cancel and reopen it to use the latest version."; return }
		document.name = document.name.trimmingCharacters(in: .whitespacesAndNewlines)
		document.rules.block_during_focus = document.rules.block_during_focus && document.has_engine && document.has_screen_time
		document.rules.notify_on_complete = document.rules.notify_on_complete && document.has_timer
		if !document.is_standing { document.enabled = nil }
		do { try document.validate() } catch { failure = error.localizedDescription; return }
		saving = true
		defer { saving = false }
		if original.enabled == true && document.enabled != true {
			guard await sessions.set_routine(original, enabled: false, groups: library.groups) else { failure = sessions.error_message; return }
			library.set_enabled(original.id, false)
			self.original = library.tool(original.id)
		}
		guard library.save(document) else { failure = library.error_message; return }
		self.original = document
		if document.enabled == true, !(await sessions.set_routine(document, enabled: true, groups: library.groups)) {
			library.set_enabled(document.id, false); draft?.enabled = false; self.original = library.tool(document.id); failure = sessions.error_message; return
		}
		cancel()
	}
}
