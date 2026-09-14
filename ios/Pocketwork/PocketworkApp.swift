import SwiftUI

@main
struct PocketworkApp: App {
	@UIApplicationDelegateAdaptor(HomeAppDelegate.self) private var app_delegate
	@StateObject private var library = LibraryController()
	@Environment(\.scenePhase) private var scene_phase
	@StateObject private var home = HomeLocationController.shared
	@StateObject private var cloud = CloudController()
	@StateObject private var sessions = SessionController.shared

	// UI tests start from an empty library so screenshots are deterministic.
	init() {
		// The Live Activity's End button runs this in the app process, even when the app was not open.
		EndFocusSessionIntent.handler = { await MainActor.run { SessionController.shared.stop() } }
		if CommandLine.arguments.contains("--reset-library") {
			UserDefaults.standard.removeObject(forKey: LibraryController.library_key)
			UserDefaults.standard.removeObject(forKey: LibraryController.legacy_key)
		}
		if CommandLine.arguments.contains("--ui-testing") {
			UIView.setAnimationsEnabled(false)
			if let fixture = ProcessInfo.processInfo.environment["POCKETWORK_UI_LIBRARY"], let data = fixture.data(using: .utf8) {
				do { _ = try ToolLibrary.decode(data); UserDefaults.standard.set(data, forKey: LibraryController.library_key) }
				catch { assertionFailure("Invalid UI test library: \(error)") }
			}
		}
	}

	var body: some Scene {
		WindowGroup {
			HomeView()
				// The workbench palette is light-only (like the web editor); without this, dark mode turns system-drawn text white on the light cards.
				.preferredColorScheme(.light)
				.environmentObject(library)
				.environmentObject(sessions)
				.environmentObject(cloud)
				.environmentObject(home)
				.task { await cloud.attach(library, sessions) }
				.onChange(of: scene_phase) { _, phase in if phase == .active { Task { await cloud.sync() }; HomeScreenBridge.reconcile(session: sessions.session) } }
				// Widgets read a snapshot, not the library; refresh it whenever routines or the session change.
				.onAppear { HomeScreenBridge.publish(library: library.library, session: sessions.session) }
				.onChange(of: library.library) { _, next in HomeScreenBridge.publish(library: next, session: sessions.session) }
				.onChange(of: sessions.session) { _, next in HomeScreenBridge.publish(library: library.library, session: next) }
		}
	}
}
