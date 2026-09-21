import ActivityKit
import AppIntents
import Foundation

// The running session as it appears on the lock screen and in the Dynamic Island. Shared by the app (which starts it) and the widget extension (which draws it).
struct FocusActivityAttributes: ActivityAttributes {
	struct ContentState: Codable, Hashable {
		var ends_at: Date
		var blocks_apps: Bool
	}
	var routine_id: String
	var routine_name: String
	var caption: String
}

// The End button on the Live Activity. A LiveActivityIntent runs inside the app process, so the app installs the handler at launch;
// the widget extension compiles this file too but never performs it.
struct EndFocusSessionIntent: LiveActivityIntent {
	static var title: LocalizedStringResource = "End session"
	static var description = IntentDescription("Ends the running Pocketwork session and releases its restrictions.")
	static var openAppWhenRun = false

	@MainActor static var handler: (() async -> Void)?

	func perform() async throws -> some IntentResult {
		if let handler = await Self.handler { await handler() }
		return .result()
	}
}
