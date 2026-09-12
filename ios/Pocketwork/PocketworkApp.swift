import SwiftUI

@main
struct PocketworkApp: App {
	@StateObject private var library = LibraryController()
	@StateObject private var sessions = SessionController()

	// UI tests start from an empty library so screenshots are deterministic.
	init() {
		if CommandLine.arguments.contains("--reset-library") {
			UserDefaults.standard.removeObject(forKey: LibraryController.library_key)
			UserDefaults.standard.removeObject(forKey: LibraryController.legacy_key)
		}
	}

	var body: some Scene {
		WindowGroup {
			HomeView()
				.environmentObject(library)
				.environmentObject(sessions)
		}
	}
}
