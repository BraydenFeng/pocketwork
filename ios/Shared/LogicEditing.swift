import Foundation

struct LogicItem: Equatable, Identifiable {
	var id: String
	var kind: String
	var x: Double
	var y: Double
	var block: BlockDocument?
	var policy: HomePolicy?
	var config: BehaviorConfig?
	var title: String { config?.label.isEmpty == false ? config!.label : block?.title ?? LogicEditing.title(kind) }
	var inputs: [String: String] { BehaviorGraph.ports[kind] != nil ? BehaviorGraph.node_ports(kind, config).inputs : LogicEditing.legacy_ports[kind]?.inputs ?? [:] }
	var outputs: [String: String] { BehaviorGraph.ports[kind] != nil ? BehaviorGraph.node_ports(kind, config).outputs : LogicEditing.legacy_ports[kind]?.outputs ?? [:] }
	var height: Double { 78 + Double(max(inputs.count, outputs.count)) * 44 }
}

struct LogicEditing: Equatable {
	var nodes: [LogicItem]
	var connections: [BehaviorEdge]
	static let legacy_ports: [String: (inputs: [String: String], outputs: [String: String])] = [
		"timer": ([:], ["active":"boolean", "finished":"boolean"]),
		"schedule": ([:], ["active":"boolean", "outside":"boolean"]),
		"home": ([:], ["present":"boolean"]), "usage": (["home":"boolean", "window":"boolean"], ["used":"number"]),
		"allowance": (["used":"number"], ["reached":"boolean"]), "apps": (["gate":"boolean", "home":"boolean", "outside":"boolean"], [:]),
		"notification": (["finished":"boolean"], [:])
	]
	static let sections: [(title: String, kinds: [String])] = [
		("Inputs", ["number_input", "text_input", "checkbox", "form", "health"]),
		("Time & location", ["timer", "schedule", "clock", "location", "arrive", "leave", "delay"]),
		("Data", ["variable", "count", "streak", "usage", "app_usage", "allowance", "save_entry", "aggregate"]),
		("Logic", ["compare", "and", "or", "not", "branch", "goal", "calculate", "text_compare"]),
		("Actions", ["button", "check_in", "apps", "notification", "reminder", "app_gate", "add_allowance"]),
		("Display", ["table", "chart", "progress"])
	]
	static let names = ["timer":"Timer", "schedule":"Time window", "home":"At location", "location":"At location", "usage":"Count usage", "allowance":"Daily allowance", "apps":"Control apps", "notification":"Notify me", "button":"Button", "check_in":"Check in", "arrive":"Arrive", "leave":"Leave", "clock":"At a time", "app_usage":"App usage", "and":"All conditions", "or":"Any condition", "not":"Not", "branch":"Branch", "delay":"Delay", "variable":"Variable", "count":"Counter", "compare":"Compare", "goal":"Goal", "streak":"Streak", "reminder":"Reminder"].merging(BuilderRuntime.names) { first, _ in first }
	static func title(_ kind: String) -> String { names[kind] ?? kind }
	static let supported: Set<String> = ["timer.active>apps.gate", "timer.finished>notification.finished", "schedule.active>apps.gate", "home.present>usage.home", "schedule.active>usage.window", "usage.used>allowance.used", "allowance.reached>apps.gate", "home.present>apps.home", "schedule.outside>apps.outside"]

	init(document: AppDocument) {
		nodes = document.blocks.compactMap { block in
			guard [.timer, .schedule, .screen_time].contains(block.type) else { return nil }
			let kind = block.type == .screen_time ? "apps" : block.type.rawValue
			return LogicItem(id: block.id, kind: kind, x: kind == "apps" ? 940 : 40, y: kind == "apps" ? 180 : 320, block: block)
		}
		connections = []
		if let policy = document.home_allowance {
			nodes += [LogicItem(id: "home-condition", kind: "home", x: 40, y: 40), LogicItem(id: "usage-meter", kind: "usage", x: 340, y: 180), LogicItem(id: "daily-allowance", kind: "allowance", x: 640, y: 180, policy: policy)]
			link("home", "present", "usage", "home"); link("schedule", "active", "usage", "window"); link("usage", "used", "allowance", "used")
			link("allowance", "reached", "apps", "gate"); link("home", "present", "apps", "home"); link("schedule", "outside", "apps", "outside")
		} else if document.rules.block_during_focus { link(document.has_timer ? "timer" : "schedule", "active", "apps", "gate") }
		if document.rules.notify_on_complete {
			nodes.append(LogicItem(id: "completion-notification", kind: "notification", x: 640, y: 40)); link("timer", "finished", "notification", "finished")
		}
		if let graph = document.behaviors {
			nodes += graph.nodes.map { LogicItem(id: $0.id, kind: $0.kind, x: $0.x, y: $0.y, config: $0.config) }
			connections += graph.connections
		}
	}
	private mutating func link(_ from: String, _ output: String, _ to: String, _ input: String) {
		if let a = nodes.first(where: { $0.kind == from }), let b = nodes.first(where: { $0.kind == to }) { connections.append(BehaviorEdge(from: a.id, output: output, to: b.id, input: input)) }
	}
	var external: [String: [String: String]] { Dictionary(uniqueKeysWithValues: nodes.filter { $0.config == nil }.map { ($0.id, $0.outputs) }) }
	var behaviors: BehaviorGraph { BehaviorGraph(nodes: nodes.compactMap { node in node.config.map { BehaviorNode(id: node.id, kind: node.kind, x: node.x, y: node.y, config: $0) } }, connections: connections.filter { edge in nodes.contains { $0.id == edge.to && $0.config != nil } }) }
	mutating func connect(_ edge: BehaviorEdge) throws {
		guard let a = nodes.first(where: { $0.id == edge.from }), let b = nodes.first(where: { $0.id == edge.to }) else { throw DocumentError.invalid("Choose both ends of the connection.") }
		if b.config != nil {
			guard let output = a.outputs[edge.output], output == b.inputs[edge.input] else { throw DocumentError.invalid("Connect matching value types: number to number, condition to condition.") }
		} else if !Self.supported.contains("\(a.kind).\(edge.output)>\(b.kind).\(edge.input)") { throw DocumentError.invalid("These ports cannot be connected.") }
		guard !connections.contains(where: { $0.to == edge.to && $0.input == edge.input }) else { throw DocumentError.invalid("Disconnect this input before replacing its connection.") }
		var next = self; next.connections.append(edge)
		_ = try next.behaviors.ordered(external: next.external, require_inputs: false)
		self = next
	}
	mutating func remove(_ id: String) { nodes.removeAll { $0.id == id }; connections.removeAll { $0.from == id || $0.to == id } }
	mutating func add(_ kind: String) throws -> String {
		guard Self.names[kind] != nil, nodes.count < 55 else { throw DocumentError.invalid("This routine has reached its block limit.") }
		let is_behavior = BehaviorGraph.ports[kind] != nil
		guard is_behavior || !nodes.contains(where: { $0.kind == kind }) else { throw DocumentError.invalid("This routine already has a \(Self.title(kind)).") }
		guard !((kind == "timer" && nodes.contains { $0.kind == "schedule" }) || (kind == "schedule" && nodes.contains { $0.kind == "timer" })) else { throw DocumentError.invalid("Use either a timer or a repeating time window in a routine.") }
		guard !is_behavior || behaviors.nodes.count < 48 else { throw DocumentError.invalid("Use at most 48 behaviors.") }
		let block: BlockDocument? = kind == "apps" ? BlockDocument.make(.screen_time) : kind == "timer" ? BlockDocument.make(.timer) : kind == "schedule" ? BlockDocument.make(.schedule) : nil
		let fixed = ["home":"home-condition", "usage":"usage-meter", "allowance":"daily-allowance", "notification":"completion-notification"]
		let id = block?.id ?? fixed[kind] ?? UUID().uuidString
		guard !nodes.contains(where: { $0.id == id }) else { throw DocumentError.invalid("This block ID is already in use.") }
		let config: BehaviorConfig? = is_behavior ? BehaviorConfig(label: Self.title(kind), value: 1, minutes: 5, time: "18:00", days: [1,2,3,4,5,6,7], message: "Time for your routine.", operator: "gte") : nil
		let policy: HomePolicy? = kind == "allowance" ? HomePolicy(timezone: "America/Los_Angeles", away_usage_counts: false, outside_windows: "block_at_home", rules: [HomeDayRule(days: [1,2,3,4,5,6,7], allowance_minutes: 30, windows: [HomeWindow(start: "06:30", end: "20:30")])]) : nil
		var position = 0
		while nodes.contains(where: { abs($0.x - Double(position % 3) * 300 - 40) < 280 && abs($0.y - Double(position / 3) * 260 - 40) < max($0.height, 220) }) { position += 1 }
		nodes.append(LogicItem(id: id, kind: kind, x: Double(position % 3) * 300 + 40, y: Double(position / 3) * 260 + 40, block: block, policy: policy, config: config))
		return id
	}
	func compile(base: AppDocument) throws -> AppDocument {
		guard nodes.count <= 55, Set(nodes.map(\.id)).count == nodes.count else { throw DocumentError.invalid("Use unique blocks and at most 55 nodes.") }
		for kind in Self.legacy_ports.keys { guard nodes.filter({ $0.kind == kind }).count <= 1 else { throw DocumentError.invalid("Only one \(Self.title(kind)) is supported.") } }
		var checked = self; checked.connections = []
		for edge in connections { try checked.connect(edge) }
		func linked(_ a: String, _ output: String, _ b: String, _ input: String) -> Bool {
			connections.contains { $0.from == nodes.first(where: { $0.kind == a })?.id && $0.output == output && $0.to == nodes.first(where: { $0.kind == b })?.id && $0.input == input }
		}
		var result = base
		let replacements = nodes.compactMap(\.block)
		result.blocks = base.blocks.compactMap { block in [.timer,.schedule,.screen_time].contains(block.type) ? replacements.first(where: { $0.id == block.id }) : block }
		for block in replacements where !result.blocks.contains(where: { $0.id == block.id }) { result.blocks.append(block) }
		result.rules = RuleDocument(block_during_focus: linked("timer","active","apps","gate") || linked("schedule","active","apps","gate"), notify_on_complete: linked("timer","finished","notification","finished"))
		if nodes.contains(where: { $0.kind == "notification" }), !result.rules.notify_on_complete { throw DocumentError.invalid("Connect Timer → finished to Notify me.") }
		if nodes.contains(where: { ["home","usage","allowance"].contains($0.kind) }) {
			guard !result.has_timer, linked("home","present","usage","home"), linked("schedule","active","usage","window"), linked("usage","used","allowance","used"), linked("allowance","reached","apps","gate"), linked("home","present","apps","home"), linked("schedule","outside","apps","outside"), let policy = nodes.first(where: { $0.kind == "allowance" })?.policy else { throw DocumentError.invalid("Connect At location and Time window → Count usage → Daily allowance → Control apps, plus location and outside to Control apps.") }
			result.home_allowance = policy; result.rules.block_during_focus = true
			if let index = result.blocks.firstIndex(where: { $0.type == .schedule }) { result.blocks[index].days = [1,2,3,4,5,6,7]; result.blocks[index].start = "00:00"; result.blocks[index].end = "23:59" }
		} else { result.home_allowance = nil }
		result.enabled = result.is_standing ? (base.schedule?.id == result.schedule?.id ? base.enabled ?? false : false) : nil
		result.behaviors = behaviors.nodes.isEmpty ? nil : behaviors
		result.schema_version = result.behaviors != nil ? 3 : result.home_allowance != nil ? 2 : 1
		try result.validate()
		return result
	}
}
