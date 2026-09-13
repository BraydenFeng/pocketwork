import SwiftUI

@main
struct PocketworkApp: App {
	@UIApplicationDelegateAdaptor(HomeAppDelegate.self) private var app_delegate
	@StateObject private var library = LibraryController()
	@Environment(\.scenePhase) private var scene_phase
	@StateObject private var home = HomeLocationController.shared
	@StateObject private var cloud = CloudController()
	@StateObject private var sessions = SessionController()

	// UI tests start from an empty library so screenshots are deterministic.
	init() {
		if CommandLine.arguments.contains("--reset-library") {
			UserDefaults.standard.removeObject(forKey: LibraryController.library_key)
			UserDefaults.standard.removeObject(forKey: LibraryController.legacy_key)
		}
		if CommandLine.arguments.contains("--ui-testing") { UIView.setAnimationsEnabled(false) }
	}

	var body: some Scene {
		WindowGroup {
			HomeView()
				.environmentObject(library)
				.environmentObject(sessions)
				.environmentObject(cloud)
				.environmentObject(home)
				.task { await cloud.attach(library, sessions) }
				.onChange(of: scene_phase) { _, phase in if phase == .active { Task { await cloud.sync() } } }
		}
	}
}
