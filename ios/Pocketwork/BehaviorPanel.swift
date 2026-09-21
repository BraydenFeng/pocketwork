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
	@StateObject private var health = HealthInputs()
	@State private var reconcile_actions = true
	@State private var groups_open = false
	@State private var state = BehaviorState()
	@State private var outputs: [String: [String: BehaviorSignal]] = [:]
	@State private var messages: [String] = []
	@State private var error: String?
	@State private var busy = false
	@State private var paused = false
	@State private var visible = false
	@State private var epoch = 0
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
				if graph.nodes.contains(where: { $0.kind == "health" }) {
					HStack { Button("Allow Health access") { Task { await health.refresh(graph.nodes.filter { $0.kind == "health" }.map { $0.config.metric ?? "steps" }, authorize: true); await run() } }; Button("Refresh health") { Task { await health.refresh(graph.nodes.filter { $0.kind == "health" }.map { $0.config.metric ?? "steps" }); await run() } } }.buttonStyle(TextButtonStyle()).disabled(health.busy)
					if let message = health.message { Text(message).supporting() }
				}
				if graph.nodes.contains(where: { $0.kind == "app_gate" }) {
					HStack { Button("Choose app groups") { groups_open = true }; Button("Allow Screen Time") { Task { _ = await sessions.authorize_screen_time() } } }.buttonStyle(TextButtonStyle())
					Text("Gates update while this routine is open. An open gate releases only its own restrictions.").supporting()
				}
				ForEach(graph.nodes) { node in
					if node.kind == "button" || node.kind == "check_in" { Button(node.config.label.isEmpty ? node.kind : node.config.label) { Task { await run(tap: node.id) } }.buttonStyle(QuietButtonStyle()).disabled(paused || busy).accessibilityIdentifier("behavior." + node.id) }
					else if node.kind == "elapsed_timer" { PrimitiveTimerView(node: node, outputs: outputs[node.id] ?? [:], command: { command in Task { await run(timer_command: command) } }).disabled(busy || paused) }
					else if ["count","streak","variable","goal","app_usage"].contains(node.kind) { HStack { Text(node.config.label).heading_font(15); Spacer(); Text(display(node)).supporting() } }
					else { BuilderNodeView(node: node, state: state.data, outputs: outputs[node.id] ?? [:], input: { value in Task { await run(inputs: [node.id: value]) } }, submit: { values in Task { await run(submission: BuilderSubmission(node: node.id, values: values)) } }).disabled(busy) }
				}
				ForEach(Array(messages.enumerated()), id: \.offset) { _, message in Text(message).supporting() }
				if let error { Text(error).foregroundStyle(Theme.danger).font(.system(size: 13)) }
			}.onAppear { visible = true; load(graph); Task { if graph.nodes.contains(where: { $0.kind == "health" }) { await health.refresh(graph.nodes.filter { $0.kind == "health" }.map { $0.config.metric ?? "steps" }) }; await run() } }
			.onDisappear { visible = false; release_gates() }
			.onChange(of: paused) { _, value in if value { release_gates() } else { reconcile_actions = true } }
			.onChange(of: scene_phase) { _, value in if value != .active { release_gates() } else { reconcile_actions = true } }
			.sheet(isPresented: $groups_open) { NavigationStack { GroupsView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { groups_open = false; reconcile_actions = true } } } } }
			.onChange(of: graph) { _, next in load(next) }
			.onChange(of: library.behavior_owner_key) { _, _ in load(graph) }
			.onReceive(clock) { _ in if scene_phase == .active && !paused { Task { await run() } } }
		}
	}
	private func display(_ node: BehaviorNode) -> String {
		let port = node.kind == "app_usage" ? "minutes" : node.kind == "streak" ? "days" : node.kind == "goal" ? "reached" : "value"
		guard let value = outputs[node.id]?[port], value.available else { return "Unavailable" }
		return node.kind == "goal" ? (value.value != 0 ? "Goal reached" : "In progress") : value.value.formatted(.number.precision(.fractionLength(0...2))) + (node.config.unit.map { " " + $0 } ?? (node.kind == "app_usage" ? " minutes" : ""))
	}
	private func release_gates() {
		epoch += 1; reconcile_actions = true
		guard !CommandLine.arguments.contains("--ui-testing") else { return }
		let id = document.id
		Task { do { try await HomeWorker.run { try BuilderAppRules.prune(document: id, nodes: []) } } catch { self.error = "Could not release this page's app restrictions: " + error.localizedDescription } }
	}
	private func load(_ graph: BehaviorGraph) {
		do {
			state = BehaviorState(); paused = false; reconcile_actions = true; outputs = [:]; messages = []; error = nil
			if let data = UserDefaults.standard.data(forKey: storage_key) { let saved = try JSONDecoder().decode(SavedBehaviors.self, from: data); state = saved.state; state.reconcile(from: saved.graph, to: graph) }
			// A stale location from a previous visit is not a new boundary crossing.
			state.at_location = nil
		} catch { self.error = "Could not load behavior progress: " + error.localizedDescription; paused = true }
	}
	@MainActor private func run(tap: String? = nil, inputs: [String: BuilderValue] = [:], submission: BuilderSubmission? = nil, timer_command: PrimitiveTimerCommand? = nil) async {
		guard let graph = document.behaviors, visible, scene_phase == .active, !busy, !paused else { return }
		busy = true; defer { busy = false }
		let key = storage_key, run_epoch = epoch
		do {
			let now = Date(); let testing = CommandLine.arguments.contains("--ui-testing")
			var used: Double?
			var allowance: Int?
			if !testing && (document.home_allowance != nil || graph.nodes.contains(where: { $0.kind == "app_usage" })) {
				let snapshot = try await HomeWorker.run { try HomeEngine.snapshot() }
				if let policy = snapshot.document?.home_allowance { used = snapshot.ledger.day == policy.day_key(now) ? Double(snapshot.ledger.used_minutes) : 0; let base = policy.rule(at: now)?.allowance_minutes ?? 0; allowance = snapshot.ledger.day == policy.day_key(now) ? snapshot.ledger.budget(base) : base }
			}
			guard key == storage_key, run_epoch == epoch, visible, !paused, scene_phase == .active else { return }
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
				external["home-condition"]?["present"]?.available = location != nil
				external["usage-meter"] = ["used":BehaviorSignal(value: used ?? 0, token: String(used ?? 0), type: "number", available: used != nil)]
				let reached = used.map { $0 >= Double(allowance ?? 0) } ?? false
				external["daily-allowance"] = ["reached":signal(reached,String(reached))]
				external["daily-allowance"]?["reached"]?.available = used != nil
			}
			let result = try BehaviorRuntime.run(graph, state: state, context: BehaviorContext(now: now, at_location: location, usage_minutes: used, tap: tap, external: external, inputs: inputs, submission: submission, health: health.values, reconcile_actions: reconcile_actions, timer_command: timer_command))
			if !testing {
				let id = document.id, groups = library.groups, active_nodes = Set(graph.nodes.filter { $0.kind == "app_gate" }.map(\.id)), reconcile = reconcile_actions
				try await HomeWorker.run {
					if reconcile { try BuilderAppRules.prune(document: id, nodes: active_nodes) }
					for action in result.actions {
						if action.kind == "app_gate" { try BuilderAppRules.set(document: id, node: action.id, active: action.active == true, names: action.groups ?? [], groups: groups) }
						else { try HomeEngine.grant_allowance(key: id + "." + action.id, minutes: Int(action.minutes ?? 0)) }
					}
				}
			}
			guard run_epoch == epoch, key == storage_key else { return }
			reconcile_actions = false
			let data = try JSONEncoder().encode(SavedBehaviors(graph: graph, state: result.state))
			UserDefaults.standard.set(data, forKey: key)
			state = result.state; outputs = result.signals; messages = Array((messages + result.messages.map(\.message)).suffix(8)); error = nil
			if !testing { for effect in result.messages {
				let content = UNMutableNotificationContent(); content.title = document.name; content.body = effect.message; content.sound = .default
				try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "behavior." + document.id + "." + effect.id + "." + String(state.sequence), content: content, trigger: nil))
			} }
		} catch { self.error = "Could not run behavior: " + error.localizedDescription; paused = true; release_gates() }
	}
}
