import SwiftUI
import WidgetKit

@main
struct PocketworkWidgets: WidgetBundle {
	var body: some Widget {
		RoutineWidget()
		FocusSessionActivity()
	}
}

// The web tokens, kept minimal here so the extension does not depend on the app's Theme file.
enum WidgetTheme {
	static let bg = Color(red: 0.949, green: 0.953, blue: 0.965)
	static let surface = Color(red: 0.988, green: 0.988, blue: 0.992)
	static let border = Color(red: 0.851, green: 0.859, blue: 0.886)
	static let text = Color(red: 0.137, green: 0.153, blue: 0.188)
	static let text_dim = Color(red: 0.322, green: 0.341, blue: 0.376)
	static let text_faint = Color(red: 0.427, green: 0.443, blue: 0.478)
	static let accent = Color(red: 0.145, green: 0.373, blue: 0.702)
	static let success = Color(red: 0.204, green: 0.514, blue: 0.376)
}
