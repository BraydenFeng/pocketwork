import ActivityKit
import Foundation
import OSLog
import WidgetKit

// Keeps the home screen widget and the lock screen Live Activity in step with the library and the running session.
enum HomeScreenBridge {
	private static let logger = Logger(subsystem: "Pocketwork", category: "HomeScreen")

	// Called whenever routines or the session change. Cheap: one small JSON write plus a widget reload request.
	static func publish(library: ToolLibrary, session: FocusSession?) {
		let now = Date()
		let tiles = library.sorted.map { entry -> RoutineTile in
			let document = entry.document
			let running = session?.document_id == document.id && session.map { !$0.has_ended(at: now) } == true
			let status: String
			if running, let ends_at = session?.ends_at {
				status = "Running · until \(ends_at.formatted(date: .omitted, time: .shortened))"
			} else if let schedule = document.schedule {
				status = ScheduleWindow.describe_status(schedule, enabled: document.enabled == true, at: now)
			} else {
				status = document.has_timer ? "Ready · tap to start" : "Tap to open"
			}
			return RoutineTile(id: document.id, name: document.name, summary: ToolCopy.summary(document), status: status, standing: document.is_standing, enabled: document.enabled == true, running: running, ends_at: running ? session?.ends_at : nil)
		}
		let snapshot = WidgetSnapshot(tiles: tiles, updated_at: now)
		guard snapshot != WidgetSnapshot.load() else { return }
		do { try snapshot.save(); WidgetCenter.shared.reloadAllTimelines() }
		catch { logger.error("Widget snapshot not written: \(error.localizedDescription, privacy: .public)") }
	}

	// One Live Activity at a time, matching the one-session-at-a-time rule.
	static func start_activity(for document: AppDocument, session: FocusSession) {
		guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
		end_activity()
		let attributes = FocusActivityAttributes(routine_id: document.id, routine_name: document.name, caption: document.blocks.first(where: { $0.type == .timer })?.title ?? "Focus session")
		let state = FocusActivityAttributes.ContentState(ends_at: session.ends_at, blocks_apps: session.blocks_apps)
		do { _ = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: session.ends_at), pushType: nil) }
		catch { logger.error("Live Activity not started: \(error.localizedDescription, privacy: .public)") }
	}

	static func end_activity() {
		for activity in Activity<FocusActivityAttributes>.activities {
			Task { await activity.end(nil, dismissalPolicy: .immediate) }
		}
	}

	// On launch and foreground: an activity with no session behind it is stale (the session ended while the app was closed).
	static func reconcile(session: FocusSession?) {
		let live = session.map { !$0.has_ended(at: .now) } == true
		if !live { end_activity() }
	}
}
