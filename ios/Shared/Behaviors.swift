import Foundation

struct BehaviorConfig: Codable, Equatable {
	var label: String
	var value: Double
	var minutes: Double
	var time: String
	var days: [Int]
	var message: String
	var `operator`: String
	var fields: [BuilderField]? = nil
	var field: String? = nil
	var text: String? = nil
	var operation: String? = nil
	var metric: String? = nil
	var groups: [String]? = nil
}
struct BehaviorNode: Codable, Equatable, Identifiable {
	var id: String
	var kind: String
	var x: Double
	var y: Double
	var config: BehaviorConfig
}
struct BehaviorEdge: Codable, Equatable, Hashable { var from: String; var output: String; var to: String; var input: String }
struct BehaviorGraph: Codable, Equatable {
	var nodes: [BehaviorNode]
	var connections: [BehaviorEdge]
	static let ports: [String: (inputs: [String: String], outputs: [String: String])] = [
		"location": ([:], ["present":"boolean", "away":"boolean"]),
		"button": ([:], ["pressed":"boolean"]), "check_in": ([:], ["done":"boolean"]),
		"arrive": ([:], ["arrived":"boolean"]), "leave": ([:], ["left":"boolean"]),
		"clock": ([:], ["due":"boolean"]), "app_usage": ([:], ["minutes":"number", "reached":"boolean"]),
		"and": (["a":"boolean", "b":"boolean"], ["result":"boolean"]), "or": (["a":"boolean", "b":"boolean"], ["result":"boolean"]),
		"not": (["condition":"boolean"], ["result":"boolean"]), "branch": (["condition":"boolean"], ["yes":"boolean", "no":"boolean"]),
		"delay": (["start":"boolean"], ["done":"boolean"]), "variable": (["set":"number"], ["value":"number"]),
		"count": (["increment":"boolean", "reset":"boolean"], ["value":"number"]),
		"compare": (["value":"number"], ["result":"boolean"]), "goal": (["value":"number"], ["reached":"boolean"]),
		"streak": (["check_in":"boolean"], ["days":"number"]), "reminder": (["send":"boolean"], ["sent":"boolean"])
	].merging(BuilderRuntime.ports) { first, _ in first }
	static func node_ports(_ kind: String, _ config: BehaviorConfig?) -> (inputs: [String: String], outputs: [String: String]) {
		var result = ports[kind] ?? (inputs: [:], outputs: [:])
		if kind == "form" { for field in config?.fields ?? BuilderRuntime.fields { result.outputs[field.id] = field.type } }
		return result
	}
	func ordered(external: [String: [String: String]], require_inputs: Bool = true) throws -> [BehaviorNode] {
		guard nodes.count <= 48, connections.count <= 128, Set(nodes.map(\.id)).count == nodes.count else { throw DocumentError.invalid("Too many or duplicate behavior nodes.") }
		for node in nodes {
			try AppDocument.validate_id(node.id)
			let c = node.config
			try BuilderRuntime.validate(node)
			guard Self.ports[node.kind] != nil, external[node.id] == nil, node.x.isFinite, node.y.isFinite, c.label.count <= 80, c.message.count <= 240, c.value.isFinite, abs(c.value) <= 1000000, c.minutes.isFinite, (1...1440).contains(c.minutes), ScheduleWindow.minutes(c.time) != nil, (1...7).contains(c.days.count), c.days.allSatisfy({ (1...7).contains($0) }), ["gte","gt","eq","lt","lte"].contains(c.operator) else { throw DocumentError.invalid("Invalid behavior settings.") }
		}
		var occupied = Set<String>()
		for edge in connections {
			let from = nodes.first { $0.id == edge.from }; let to = nodes.first { $0.id == edge.to }
			let output = from.flatMap { Self.node_ports($0.kind, $0.config).outputs[edge.output] } ?? external[edge.from]?[edge.output]
			guard let to, let output, output == Self.node_ports(to.kind, to.config).inputs[edge.input], occupied.insert(edge.to + "." + edge.input).inserted else { throw DocumentError.invalid("Incompatible or occupied behavior input.") }
		}
		for node in nodes { for port in Self.node_ports(node.kind, node.config).inputs.keys {
			if !require_inputs { continue }
			if (node.kind == "variable" && port == "set") || (node.kind == "count" && port == "reset") || (node.kind == "save_entry" && port == "clear") { continue }
			guard occupied.contains(node.id + "." + port) else { throw DocumentError.invalid("Connect the " + port + " input first.") }
		} }
		var remaining = nodes; var result: [BehaviorNode] = []
		while !remaining.isEmpty {
			guard let index = remaining.firstIndex(where: { node in !connections.contains { edge in edge.to == node.id && remaining.contains { $0.id == edge.from } } }) else { throw DocumentError.invalid("Behavior connections cannot contain a loop.") }
			result.append(remaining.remove(at: index))
		}
		return result
	}
}
struct BehaviorSignal { var value: Double; var token: String; var type: String = "boolean"; var available = true; var text: String?; var record: [String: BuilderValue]?; var rows: [BuilderEntry]? }
struct BehaviorPending: Codable { var id: String; var at: Double; var token: String }
struct BehaviorState: Codable {
	var values: [String: Double] = [:]
	var fired: [String: String] = [:]
	var days: [String: String] = [:]
	var pending: [BehaviorPending] = []
	var sequence = 0
	var data: BuilderState?
	var at_location: Bool?
}
struct BehaviorContext {
	var now: Date
	var at_location: Bool?
	var usage_minutes: Double?
	var tap: String?
	var external: [String: [String: BehaviorSignal]] = [:]
	var inputs: [String: BuilderValue] = [:]
	var submission: BuilderSubmission?
	var health: [String: Double] = [:]
	var reconcile_actions = false
	var calendar: Calendar = .current
}
struct BehaviorResult {
	var state: BehaviorState
	var signals: [String: [String: BehaviorSignal]]
	var messages: [(id: String, message: String)]
	var actions: [BuilderAction] = []
}
enum BehaviorRuntime {
	static func run(_ graph: BehaviorGraph, state previous: BehaviorState, context: BehaviorContext) throws -> BehaviorResult {
		var state = previous; state.sequence += 1
		var actions: [BuilderAction] = []
		var signals = context.external; var messages: [(id: String, message: String)] = []
		let external = context.external.mapValues { $0.mapValues(\.type) }
		let calendar = context.calendar
		func day_key(_ date: Date) -> String { let c = calendar.dateComponents([.year,.month,.day], from: date); return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0) }
		let day = day_key(context.now)
		let yesterday = day_key(calendar.date(byAdding: .day, value: -1, to: context.now) ?? context.now)
		let time = String(format: "%02d:%02d", calendar.component(.hour, from: context.now), calendar.component(.minute, from: context.now))
		for node in try graph.ordered(external: external) {
			let c = node.config; let pulse = String(state.sequence)
			var output: [String: BehaviorSignal] = [:]
			func input(_ port: String) -> BehaviorSignal { guard let edge = graph.connections.first(where: { $0.to == node.id && $0.input == port }) else { return BehaviorSignal(value: 0, token: "") }; return signals[edge.from]?[edge.output] ?? BehaviorSignal(value: 0, token: "") }
			func emit(_ port: String, _ value: Double, _ token: String? = nil) { output[port] = BehaviorSignal(value: value, token: token ?? String(value), type: BehaviorGraph.node_ports(node.kind, node.config).outputs[port] ?? "boolean") }
			func boolean(_ port: String, _ value: Bool, _ token: String? = nil) { emit(port, value ? 1 : 0, token) }
			func once(_ port: String) -> Bool { let signal = input(port); let key = node.id + "." + port; if signal.value == 0 { state.fired.removeValue(forKey: key); return false }; if state.fired[key] == signal.token { return false }; state.fired[key] = signal.token; return true }
			if node.kind != "variable" && graph.connections.contains(where: { $0.to == node.id && signals[$0.from]?[$0.output]?.available == false }) {
				for (port,type) in BehaviorGraph.node_ports(node.kind, node.config).outputs { output[port] = BehaviorSignal(value: 0,token: "",type: type,available: false) }
				signals[node.id] = output; continue
			}
			switch node.kind {
			case "location": boolean("present", context.at_location == true); boolean("away", context.at_location == false); output["present"]?.available = context.at_location != nil; output["away"]?.available = context.at_location != nil
			case "button": boolean("pressed", context.tap == node.id, pulse)
			case "check_in": boolean("done", context.tap == node.id, pulse); if context.tap == node.id { state.days[node.id] = day }
			case "arrive": boolean("arrived", context.at_location == true && previous.at_location == false, pulse)
			case "leave": boolean("left", context.at_location == false && previous.at_location == true, pulse)
			case "clock": boolean("due", c.days.contains(calendar.component(.weekday, from: context.now)) && c.time == time, day + c.time)
			case "app_usage": emit("minutes", context.usage_minutes ?? 0); boolean("reached", context.usage_minutes.map { $0 >= c.value } ?? false, day); output["minutes"]?.available = context.usage_minutes != nil; output["reached"]?.available = context.usage_minutes != nil
			case "and", "or": let a = input("a"), b = input("b"); boolean("result", node.kind == "and" ? a.value != 0 && b.value != 0 : a.value != 0 || b.value != 0, (a.value != 0 ? a.token : "") + ":" + (b.value != 0 ? b.token : ""))
			case "not": boolean("result", input("condition").value == 0)
			case "branch": boolean("yes", input("condition").value != 0, input("condition").token); boolean("no", input("condition").value == 0)
			case "delay":
				if once("start") { guard state.pending.count < 128 else { throw DocumentError.invalid("Too many pending delays.") }; state.pending.removeAll { $0.id == node.id }; state.pending.append(BehaviorPending(id: node.id, at: context.now.timeIntervalSince1970 + c.minutes * 60, token: pulse)) }
				let due = state.pending.filter { $0.id == node.id && $0.at <= context.now.timeIntervalSince1970 }
				state.pending.removeAll { $0.id == node.id && $0.at <= context.now.timeIntervalSince1970 }; boolean("done", !due.isEmpty, due.map(\.token).joined(separator: ":"))
			case "variable": if input("set").available && graph.connections.contains(where: { $0.to == node.id && $0.input == "set" }) { state.values[node.id] = input("set").value }; emit("value", state.values[node.id] ?? c.value)
			case "count": if once("reset") { state.values[node.id] = 0 }; if once("increment") { state.values[node.id] = min(1000000, (state.values[node.id] ?? 0) + c.value) }; emit("value", state.values[node.id] ?? 0)
			case "compare", "goal":
				let value = input("value").value
				let result: Bool
				switch node.kind == "goal" ? "gte" : c.operator { case "gt": result = value > c.value; case "eq": result = value == c.value; case "lt": result = value < c.value; case "lte": result = value <= c.value; default: result = value >= c.value }
				boolean(node.kind == "goal" ? "reached" : "result", result)
			case "streak": if once("check_in") && state.days[node.id] != day { state.values[node.id] = state.days[node.id] == yesterday ? (state.values[node.id] ?? 0)+1 : 1; state.days[node.id] = day }; emit("days", state.days[node.id] == day || state.days[node.id] == yesterday ? state.values[node.id] ?? 0 : 0)
			case "reminder": let send = once("send"); if send { messages.append((node.id, c.message)) }; boolean("sent", send, pulse)
			default: output = try BuilderRuntime.run(node, state: &state, context: context, signals: signals, connections: graph.connections, actions: &actions, day: day)
			}
			signals[node.id] = output
		}
		state.at_location = context.at_location
		return BehaviorResult(state: state, signals: signals, messages: messages, actions: actions)
	}
}
extension AppDocument {
	var behavior_external_ports: [String: [String: String]] {
		var ports: [String: [String: String]] = [:]
		for block in blocks { if block.type == .timer { ports[block.id] = ["active":"boolean", "finished":"boolean"] }; if block.type == .schedule { ports[block.id] = ["active":"boolean", "outside":"boolean"] } }
		if home_allowance != nil { ports["home-condition"] = ["present":"boolean"]; ports["usage-meter"] = ["used":"number"]; ports["daily-allowance"] = ["reached":"boolean"] }
		return ports
	}
}

extension BehaviorState {
	mutating func reconcile(from old: BehaviorGraph, to next: BehaviorGraph) {
		let live = Set(next.nodes.filter { node in old.nodes.contains { $0.id == node.id && $0.kind == node.kind } }.map(\.id))
		let stable = Set(next.nodes.filter { node in
			guard let previous = old.nodes.first(where: { $0.id == node.id && $0.kind == node.kind }) else { return false }
			var before = previous.config; var after = node.config; before.label = ""; after.label = ""
			return before == after && Set(old.connections.filter { $0.to == node.id }) == Set(next.connections.filter { $0.to == node.id })
		}.map(\.id))
		values = values.filter { live.contains($0.key) }; days = days.filter { live.contains($0.key) }
		fired = fired.filter { stable.contains(String($0.key.split(separator: ".").first ?? "")) }
		pending = pending.filter { stable.contains($0.id) }
		// Reading and writing `data` in one statement is an exclusivity violation; work on a copy and assign it back.
		if var builder = data {
			builder.inputs = builder.inputs.filter { live.contains($0.key) }
			builder.forms = builder.forms.filter { live.contains($0.key) }
			builder.entries = builder.entries.filter { live.contains($0.key) }
			builder.rewards = builder.rewards.filter { live.contains($0.key) }
			builder.gates = builder.gates.filter { live.contains($0.key) }
			data = builder
		}
		at_location = nil
	}
}
