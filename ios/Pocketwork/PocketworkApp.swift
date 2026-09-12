import SwiftUI

@main
struct PocketworkApp: App {
	@StateObject private var library = LibraryController()
	@StateObject private var sessions = SessionController()

	var body: some Scene {
		WindowGroup {
			HomeView()
				.environmentObject(library)
				.environmentObject(sessions)
		}
	}
}
