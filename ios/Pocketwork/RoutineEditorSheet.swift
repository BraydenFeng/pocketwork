import SwiftUI

struct RoutineDraft: Identifiable {
	let document: AppDocument
	let is_new: Bool
	var id: String { document.id }
}

struct RoutineEditorSheet: View {
	let item: RoutineDraft
	var body: some View {
		if item.document.home_allowance != nil { HomePolicyEditorView(document: item.document) }
		else { EditorView(document: item.document, is_new: item.is_new) }
	}
}
