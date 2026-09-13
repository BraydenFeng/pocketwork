import Combine
import SwiftUI
import UserNotifications

private struct SavedBehaviors: Codable { var graph: BehaviorGraph; var state: BehaviorState }
struct BehaviorPanel: View {
	let document: AppDocument
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@EnvironmentObject private var home: HomeLocationController
	@Environment(\.scenePhase) private var scene_phase
	@State private var state = BehaviorState()
	@State private var outputs: [String: [String: BehaviorSignal]] = [:]
	@State private var messages: [String] = []
	@State private var error: String?
	@State private var busy = false
	@State private var paused = false
	@State private var timer_end: Date?
	private let clock = Timer.publish(every: CommandLine.arguments.contains("--ui-testing") ? 3600 : 1, on: .main, in: .common).autoconnect()
	private var storage_key: String { "behaviors.v1." + library.behavior_owner_key + "." + document.id }
	var body: some View {
		if let graph = document.behaviors {
			VStack(alignment: .leading, spacing: 12) {
				Text("Your behaviors").heading_font(17)
				Text("Connections run while this routine is open. Progress stays on this phone. Existing Screen Time schedules continue in the background.").supporting()
				HStack { Button(paused ? "Resume" : "Pause") { paused.toggle() }.buttonStyle(TextButtonStyle()); Button("Allow notifications") { Task { do { let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound]); if !granted { error = "Notifications are off. Messages still appear here." } } catch { self.error = error.localizedDescription } } }.buttonStyle(TextButtonStyle()) }
				if graph.nodes.contains(where: { ["location","arrive","leave"].contains($0.kind) }) {
					Text("One location is shared by all routines, including your home allowance.").supporting()
					Button("Set location here") { home.set_here() }.buttonStyle(QuietButtonStyle())
					Button("Allow location detection") { home.allow_background() }.buttonStyle(TextButtonStyle())
					Text(home.status).supporting()
				}
				ForEach(graph.nodes) { node in
					if node.kind == "button" || node.kind == "check_in" { Button(node.config.label.isEmpty ? node.kind : node.config.label) { Task { await run(tap: node.id) } }.buttonStyle(QuietButtonStyle()).disabled(paused || busy).accessibilityIdentifier("behavior." + node.id) }
					else if ["count","streak","variable","goal"].contains(node.kind) { HStack { Text(node.config.label).heading_font(15); Spacer(); Text(display(node)).supporting() } }
				}
				ForEach(Array(messages.enumerated()), id: \.offset) { _, message in Text(message).supporting() }
				if let error { Text(error).foregroundStyle(Theme.danger).font(.system(size: 13)) }
			}.onAppear { load(graph); Task { await run() } }
			.onChange(of: graph) { _, next in load(next) }
			.onChange(of: library.behavior_owner_key) { _, _ in load(graph) }
			.onReceive(clock) { _ in if scene_phase == .active && !paused { Task { await run() } } }
		}
	}
	private func display(_ node: BehaviorNode) -> String {
		guard let value = outputs[node.id]?.values.first else { return "0" }
		return node.kind == "goal" ? (value.value != 0 ? "Reached" : "In progress") : String(format: "%.0f", value.value)
	}
	private func load(_ graph: BehaviorGraph) {
		do {
			state = BehaviorState(); outputs = [:]; messages = []; error = nil
			if let data = UserDefaults.standard.data(forKey: storage_key) { let saved = try JSONDecoder().decode(SavedBehaviors.self, from: data); if saved.graph == graph { state = saved.state } }
			// A stale location from a previous visit is not a new boundary crossing.
			state.at_location = nil
		} catch { self.error = "Could not load behavior progress: " + error.localizedDescription; paused = true }
	}
	@MainActor private func run(tap: String? = nil) async {
		guard let graph = document.behaviors, !busy, !paused else { return }
		busy = true; defer { busy = false }
		let key = storage_key
		do {
			let now = Date(); let testing = CommandLine.arguments.contains("--ui-testing")
			var used: Double?
			if !testing && (document.home_allowance != nil || graph.nodes.contains(where: { $0.kind == "app_usage" })) {
				let snapshot = try await HomeWorker.run { try HomeEngine.snapshot() }
				if let policy = snapshot.document?.home_allowance { used = snapshot.ledger.day == policy.day_key(now) ? Double(snapshot.ledger.used_minutes) : 0 }
			}
			guard key == storage_key else { return }
			if let session = sessions.session, session.document_id == document.id { timer_end = session.ends_at }
			var external: [String: [String: BehaviorSignal]] = [:]
			for (id, ports) in document.behavior_external_ports { external[id] = ports.mapValues { BehaviorSignal(value: 0, token: "", type: $0) } }
			func signal(_ value: Bool, _ token: String) -> BehaviorSignal { BehaviorSignal(value: value ? 1 : 0, token: token) }
			for block in document.blocks {
				if block.type == .timer { let active = sessions.is_running(document) && (timer_end ?? .distantPast) > now; let finished = timer_end.map { $0 <= now } ?? false; let token = String(timer_end?.timeIntervalSince1970 ?? 0); external[block.id] = ["active":signal(active,token),"finished":signal(finished,token)] }
				if block.type == .schedule { let active = document.enabled == true && (document.home_allowance?.allows(at: now) ?? ScheduleWindow.status(block, at: now).active); external[block.id] = ["active":signal(active,String(active)),"outside":signal(!active,String(!active))] }
			}
			let location = home.always_allowed ? home.at_location : nil
			if document.home_allowance != nil {
				external["home-condition"] = ["present":signal(location == true,String(location == true))]
				external["usage-meter"] = ["used":BehaviorSignal(value: used ?? 0, token: String(used ?? 0), type: "number")]
				let reached = used.map { $0 >= Double(document.home_allowance?.rule(at: now)?.allowance_minutes ?? 0) } ?? false
				external["daily-allowance"] = ["reached":signal(reached,String(reached))]
			}
			let result = try BehaviorRuntime.run(graph, state: state, context: BehaviorContext(now: now, at_location: location, usage_minutes: used, tap: tap, external: external))
			let data = try JSONEncoder().encode(SavedBehaviors(graph: graph, state: result.state))
			UserDefaults.standard.set(data, forKey: key)
			state = result.state; outputs = result.signals; messages = Array((messages + result.messages.map(\.message)).suffix(8)); error = nil
			if !testing { for effect in result.messages {
				let content = UNMutableNotificationContent(); content.title = document.name; content.body = effect.message; content.sound = .default
				try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "behavior." + document.id + "." + effect.id + "." + String(state.sequence), content: content, trigger: nil))
			} }
		} catch { self.error = "Could not run behavior: " + error.localizedDescription; paused = true }
	}
}
