import Combine
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import OSLog
import UserNotifications

struct ProgressSnapshot: Codable, Equatable {
	var completed_tasks: Set<String> = []
	var counters: [String: Int] = [:]
}

// One focus session at a time, device-wide. The session remembers which tool started it so the timer shows in the right place.
@MainActor
final class SessionController: ObservableObject {
	@Published private(set) var session: FocusSession?
	@Published private(set) var progress: [String: ProgressSnapshot] = [:]
	@Published var error_message: String?
	@Published private(set) var is_busy = false
	private let logger = Logger(subsystem: "Pocketwork", category: "SessionController")
	private let center = DeviceActivityCenter()
	private let notifications = UNUserNotificationCenter.current()
	private let notification_id = "pocketwork.focus.complete"
	private let progress_key = "tool_progress.v2"

	init() {
		do {
			if let data = UserDefaults.standard.data(forKey: progress_key) {
				progress = try JSONDecoder().decode([String: ProgressSnapshot].self, from: data)
			}
		} catch { report(error) }
		refresh()
	}

	func report(_ error: Error) {
		logger.error("Pocketwork operation failed: \(error.localizedDescription, privacy: .public)")
		error_message = error.localizedDescription
	}

	func is_running(_ document: AppDocument) -> Bool { session?.document_id == document.id }

	// Read during view rendering, so it must never publish state; a missing App Group is logged and shows as zero selected.
	func selection(for document: AppDocument) -> FamilyActivitySelection {
		do { return try SharedStore().selection(for: document.id) }
		catch { logger.warning("App selection unavailable: \(error.localizedDescription, privacy: .public)"); return FamilyActivitySelection() }
	}

	func selected_count(for document: AppDocument) -> Int {
		let selection = selection(for: document)
		return selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
	}

	func authorize_screen_time() async -> Bool {
		do {
			try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
			guard AuthorizationCenter.shared.authorizationStatus == .approved else { throw DocumentError.invalid("Screen Time permission was not granted.") }
			return true
		} catch { report(error); return false }
	}

	func save_selection(_ value: FamilyActivitySelection, for document: AppDocument) {
		guard !is_running(document) else { error_message = "End your session before changing the selected apps."; return }
		do { try SharedStore().save_selection(value, for: document.id); objectWillChange.send() } catch { report(error) }
	}

	func forget(_ document_id: String) {
		if session?.document_id == document_id { stop() }
		progress.removeValue(forKey: document_id)
		do { try SharedStore().remove_selection(for: document_id); try persist_progress() } catch { report(error) }
	}

	func start(_ document: AppDocument) async {
		guard !is_busy, session == nil, let minutes = document.focus_minutes else {
			if session != nil { error_message = "Another session is already running. End it first." }
			return
		}
		is_busy = true
		defer { is_busy = false }
		var scheduled_activity: DeviceActivityName?
		do {
			let shared = try SharedStore()
			if document.rules.block_during_focus {
				guard AuthorizationCenter.shared.authorizationStatus == .approved else { throw DocumentError.invalid("Choose apps and allow Screen Time access before starting this blocking session.") }
				guard selected_count(for: document) > 0 else { throw DocumentError.invalid("Choose at least one app, website, or category to block.") }
			}
			if document.rules.notify_on_complete {
				let granted = try await notifications.requestAuthorization(options: [.alert, .sound])
				guard granted else { throw DocumentError.invalid("Notifications are disabled. Enable them in Settings or turn off the completion-notification rule in your tool.") }
			}
			let now = Date()
			let record = FocusSession(activity_name: "pocketwork.\(UUID().uuidString)", document_id: document.id, ends_at: now.addingTimeInterval(Double(minutes) * 60), blocks_apps: document.rules.block_during_focus)
			if record.blocks_apps {
				let activity = DeviceActivityName(record.activity_name)
				let calendar = Calendar.current
				let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
				let schedule = DeviceActivitySchedule(intervalStart: calendar.dateComponents(parts, from: now), intervalEnd: calendar.dateComponents(parts, from: record.ends_at), repeats: false)
				try shared.save_session(record)
				try center.startMonitoring(activity, during: schedule)
				scheduled_activity = activity
				try shared.apply_selection(for: document.id)
			} else {
				try shared.save_session(record)
			}
			if document.rules.notify_on_complete {
				let content = UNMutableNotificationContent()
				content.title = "A little progress feels good."
				content.body = "\(document.name) has finished."
				content.sound = .default
				let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, record.ends_at.timeIntervalSinceNow), repeats: false)
				try await notifications.add(UNNotificationRequest(identifier: notification_id, content: content, trigger: trigger))
			}
			session = record
		} catch {
			if let activity = scheduled_activity { center.stopMonitoring([activity]) }
			ManagedSettingsStore(named: SharedStore.settings_name).clearAllSettings()
			notifications.removePendingNotificationRequests(withIdentifiers: [notification_id])
			do { try SharedStore().clear_session() } catch { logger.error("Session rollback failed: \(error.localizedDescription, privacy: .public)") }
			session = nil
			report(error)
		}
	}

	func stop() {
		ManagedSettingsStore(named: SharedStore.settings_name).clearAllSettings()
		center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix("pocketwork.") })
		notifications.removePendingNotificationRequests(withIdentifiers: [notification_id])
		notifications.removeDeliveredNotifications(withIdentifiers: [notification_id])
		do { try SharedStore().clear_session() } catch { report(error) }
		session = nil
	}

	func refresh() {
		guard !is_busy else { return }
		do {
			let shared = try SharedStore()
			let stored = try shared.session()
			if let stored, !stored.has_ended(at: .now) {
				if stored.blocks_apps && AuthorizationCenter.shared.authorizationStatus != .approved { stop(); return }
				session = stored
			} else {
				ManagedSettingsStore(named: SharedStore.settings_name).clearAllSettings()
				center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix("pocketwork.") })
				shared.clear_session()
				session = nil
			}
		} catch {
			// Runs on launch and every foreground; an alert here would greet the user before they did anything, so log and fail safe instead.
			ManagedSettingsStore(named: SharedStore.settings_name).clearAllSettings()
			logger.error("Session refresh failed: \(error.localizedDescription, privacy: .public)")
		}
	}

	func completed(_ task_id: String, in document: AppDocument) -> Bool { progress[document.id]?.completed_tasks.contains(task_id) ?? false }
	func count(_ block: BlockDocument, in document: AppDocument) -> Int { progress[document.id]?.counters[block.id] ?? 0 }

	func toggle_task(_ id: String, in document: AppDocument) {
		guard document.blocks.contains(where: { $0.items?.contains(where: { $0.id == id }) == true }) else { return }
		var snapshot = progress[document.id] ?? ProgressSnapshot()
		if snapshot.completed_tasks.contains(id) { snapshot.completed_tasks.remove(id) } else { snapshot.completed_tasks.insert(id) }
		progress[document.id] = snapshot
		do { try persist_progress() } catch { report(error) }
	}

	func increment(_ block: BlockDocument, in document: AppDocument) {
		guard let target = block.target else { return }
		var snapshot = progress[document.id] ?? ProgressSnapshot()
		snapshot.counters[block.id] = min(target, (snapshot.counters[block.id] ?? 0) + 1)
		progress[document.id] = snapshot
		do { try persist_progress() } catch { report(error) }
	}

	func reset_progress(for document: AppDocument) {
		progress.removeValue(forKey: document.id)
		do { try persist_progress() } catch { report(error) }
	}

	private func persist_progress() throws {
		UserDefaults.standard.set(try JSONEncoder().encode(progress), forKey: progress_key)
	}
}
