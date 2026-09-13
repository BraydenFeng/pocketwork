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

	func selected_count(for document: AppDocument) -> Int { SharedStore.count(selection(for: document)) }

	func group_selection(_ group: AppGroup) -> FamilyActivitySelection {
		do { return try SharedStore().group_selection(group.id) }
		catch { logger.warning("Group selection unavailable: \(error.localizedDescription, privacy: .public)"); return FamilyActivitySelection() }
	}

	func group_count(_ group: AppGroup) -> Int { SharedStore.count(group_selection(group)) }

	func save_group_selection(_ value: FamilyActivitySelection, for group: AppGroup) {
		do { try SharedStore().save_group_selection(value, for: group.id); objectWillChange.send() } catch { report(error) }
	}

	func forget_group(_ group_id: String) {
		do { try SharedStore().remove_group_selection(group_id) } catch { report(error) }
	}

	// Turns the routine's Screen Time block into a plan the monitor extension can act on without the library.
	// Throws in plain words when a group is missing or has no apps yet, so the person knows what to fix.
	func plan(for document: AppDocument, groups: [AppGroup]) throws -> SharedStore.ShieldPlan {
		guard let shield = document.shield else { return SharedStore.ShieldPlan(mode: .block, group_ids: [], limit_minutes: nil) }
		var ids: [String] = []
		for name in shield.group_names {
			guard let group = groups.first(where: { $0.name.lowercased() == name.lowercased() }) else { throw DocumentError.invalid("The app group \"\(name)\" does not exist yet. Create it under App groups.") }
			guard group_count(group) > 0 else { throw DocumentError.invalid("Choose the apps for \"\(group.name)\" first (App groups).") }
			ids.append(group.id)
		}
		if ids.isEmpty { guard selected_count(for: document) > 0 else { throw DocumentError.invalid("Choose at least one app, website, or category to block.") } }
		return SharedStore.ShieldPlan(mode: shield.shield_mode, group_ids: ids, limit_minutes: shield.shield_mode == .limit ? shield.limit_minutes : nil)
	}

	private func limit_events(_ plan: SharedStore.ShieldPlan, document_id: String, shared: SharedStore) throws -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
		guard plan.mode == .limit, let minutes = plan.limit_minutes else { return [:] }
		let selection = try shared.resolved_selection(for: document_id, plan: plan)
		return [DeviceActivityEvent.Name("pocketwork.limit"): DeviceActivityEvent(applications: selection.applicationTokens, categories: selection.categoryTokens, webDomains: selection.webDomainTokens, threshold: DateComponents(minute: minutes))]
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
		do { if try HomeEngine.snapshot().document?.id == document_id { try HomeEngine.disable() } } catch { report(error) }
		if session?.document_id == document_id { stop() }
		release_standing(document_id)
		progress.removeValue(forKey: document_id)
		do { try SharedStore().remove_selection(for: document_id); try SharedStore().set_standing(document_id, enabled: false); try persist_progress() } catch { report(error) }
	}

	// Standing routines: one repeating DeviceActivity per chosen weekday. iOS fires the monitor extension at each window edge.
	func set_standing(_ document: AppDocument, enabled: Bool, groups: [AppGroup]) -> Bool {
		if document.home_allowance != nil {
			do {
				if !enabled { try HomeEngine.disable(); try SharedStore().set_standing(document.id, enabled: false); return true }
				try HomeEngine.configure(document, plan: plan(for: document, groups: groups), enabled: true)
				try SharedStore().set_standing(document.id, enabled: true)
				return true
			} catch { report(error); return false }
		}
		guard let schedule = document.schedule, let days = schedule.days, let start = schedule.start, let end = schedule.end,
			let from = ScheduleWindow.minutes(start), let to = ScheduleWindow.minutes(end) else { return false }
		guard !enabled else {
			do {
				let shared = try SharedStore()
				guard AuthorizationCenter.shared.authorizationStatus == .approved else { throw DocumentError.invalid("Allow Screen Time access and choose apps before switching this routine on.") }
				let shield_plan = try plan(for: document, groups: groups)
				try shared.save_plan(shield_plan, for: document.id)
				let events = try limit_events(shield_plan, document_id: document.id, shared: shared)
				var scheduled: [DeviceActivityName] = []
				do {
					for day in days {
						let end_day = to > from ? day : (day % 7) + 1
						let window = DeviceActivitySchedule(intervalStart: DateComponents(hour: from / 60, minute: from % 60, weekday: day), intervalEnd: DateComponents(hour: to / 60, minute: to % 60, weekday: end_day), repeats: true)
						let activity = SharedStore.standing_activity(document.id, weekday: day)
						try center.startMonitoring(activity, during: window, events: events)
						scheduled.append(activity)
					}
				} catch { center.stopMonitoring(scheduled); throw error }
				shared.set_standing(document.id, enabled: true)
				let store = SharedStore.standing_store(document.id)
				if shield_plan.mode != .limit, ScheduleWindow.status(schedule, at: .now).active { try shared.apply_plan(for: document.id, to: store) } else { store.clearAllSettings() }
				objectWillChange.send()
				return true
			} catch { release_standing(document.id); report(error); return false }
		}
		release_standing(document.id)
		do { try SharedStore().set_standing(document.id, enabled: false) } catch { report(error) }
		objectWillChange.send()
		return true
	}

	private func release_standing(_ document_id: String) {
		center.stopMonitoring(center.activities.filter { SharedStore.standing_id(from: $0) == document_id })
		SharedStore.standing_store(document_id).clearAllSettings()
		if let shared = try? SharedStore(), session?.document_id != document_id { shared.remove_plan(for: document_id) }
	}

	// The emergency exit: every shield this app has ever applied comes off. Returns the standing routines that were switched off.
	func clear_everything() -> [String] {
		do { try HomeEngine.disable() } catch { report(error) }
		stop()
		let ids = (try? SharedStore().standing_ids()) ?? []
		for id in ids { release_standing(id); _ = try? SharedStore().set_standing(id, enabled: false) }
		center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(SharedStore.standing_prefix) })
		objectWillChange.send()
		return Array(ids)
	}

	func start(_ document: AppDocument, groups: [AppGroup]) async {
		guard !is_busy, session == nil, let minutes = document.focus_minutes else {
			if session != nil { error_message = "Another session is already running. End it first." }
			return
		}
		is_busy = true
		defer { is_busy = false }
		var scheduled_activity: DeviceActivityName?
		do {
			let shared = try SharedStore()
			var shield_plan: SharedStore.ShieldPlan?
			if document.rules.block_during_focus {
				guard AuthorizationCenter.shared.authorizationStatus == .approved else { throw DocumentError.invalid("Choose apps and allow Screen Time access before starting this blocking session.") }
				shield_plan = try plan(for: document, groups: groups)
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
				if let shield_plan { try shared.save_plan(shield_plan, for: document.id) }
				try center.startMonitoring(activity, during: schedule, events: try limit_events(shield_plan ?? SharedStore.ShieldPlan(mode: .block, group_ids: [], limit_minutes: nil), document_id: document.id, shared: shared))
				scheduled_activity = activity
				if shield_plan?.mode != .limit { try shared.apply_plan(for: document.id, to: ManagedSettingsStore(named: SharedStore.settings_name)) }
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
		do {
			let shared = try SharedStore()
			if let running = session { shared.remove_plan(for: running.document_id) }
			shared.clear_session()
		} catch { report(error) }
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
