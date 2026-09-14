import Foundation

struct BuilderField: Codable, Equatable, Identifiable { var id: String; var label: String; var type: String; var required: Bool }
enum BuilderValue: Codable, Equatable {
	case number(Double), text(String), boolean(Bool)
	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if let value = try? container.decode(Bool.self) { self = .boolean(value) }
		else if let value = try? container.decode(Double.self), value.isFinite, abs(value) <= 1000000 { self = .number(value) }
		else if let value = try? container.decode(String.self), value.count <= 240 { self = .text(value) }
		else { throw DocumentError.invalid("Invalid field value.") }
	}
	func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); switch self { case .number(let value): try container.encode(value); case .text(let value): try container.encode(value); case .boolean(let value): try container.encode(value) } }
	var type: String { switch self { case .number: return "number"; case .text: return "text"; case .boolean: return "boolean" } }
	var display: String { switch self { case .number(let value): return value.formatted(); case .text(let value): return value; case .boolean(let value): return value ? "Yes" : "No" } }
	var number: Double? { if case .number(let value) = self { return value }; return nil }
}
struct BuilderEntry: Codable, Equatable, Identifiable { var id: String; var at: Double; var values: [String: BuilderValue] }
struct BuilderState: Codable {
	var inputs: [String: BuilderValue] = [:]
	var forms: [String: [String: BuilderValue]] = [:]
	var entries: [String: [BuilderEntry]] = [:]
	var rewards: [String: String] = [:]
	var gates: [String: Bool] = [:]
}
struct BuilderSubmission { var node: String; var values: [String: BuilderValue] }
struct BuilderAction { var id: String; var kind: String; var token: String; var active: Bool?; var minutes: Double?; var groups: [String]? }
enum BuilderRuntime {
	static let fields = [BuilderField(id: "value", label: "Value", type: "number", required: true)]
	static let health_metrics = ["steps", "active_energy", "exercise_minutes", "protein", "carbohydrates", "fat", "water"]
	static let names = ["number_input":"Number input", "text_input":"Text input", "checkbox":"Checkbox", "form":"Form", "save_entry":"Save entry", "aggregate":"Summarize data", "calculate":"Calculate", "text_compare":"Compare text", "table":"Table", "chart":"Chart", "progress":"Progress bar", "health":"Apple Health", "app_gate":"App gate", "add_allowance":"Add screen time"]
	static let ports: [String: (inputs: [String: String], outputs: [String: String])] = [
		"number_input": ([:], ["value":"number", "changed":"boolean"]), "text_input": ([:], ["value":"text", "changed":"boolean"]), "checkbox": ([:], ["checked":"boolean", "changed":"boolean"]),
		"form": ([:], ["submitted":"boolean", "record":"record"]), "save_entry": (["record":"record", "save":"boolean", "clear":"boolean"], ["rows":"table", "count":"number", "saved":"boolean"]),
		"aggregate": (["rows":"table"], ["value":"number"]), "calculate": (["a":"number", "b":"number"], ["value":"number"]), "text_compare": (["text":"text"], ["result":"boolean"]),
		"table": (["rows":"table"], ["rows":"table"]), "chart": (["rows":"table"], ["rows":"table"]), "progress": (["value":"number"], ["value":"number", "fraction":"number"]),
		"health": ([:], ["value":"number"]), "app_gate": (["closed":"boolean"], ["active":"boolean"]), "add_allowance": (["grant":"boolean"], ["granted":"boolean"])
	]
	static func validate(_ node: BehaviorNode) throws {
		let c = node.config
		if let fields = c.fields {
			guard (1...8).contains(fields.count), Set(fields.map(\.id)).count == fields.count else { throw DocumentError.invalid("Use one to eight fields with unique IDs.") }
			for field in fields { guard field.id.range(of: "^[a-zA-Z][a-zA-Z0-9_]{0,31}$", options: .regularExpression) != nil, !["record", "submitted", "__proto__", "constructor", "prototype"].contains(field.id), !field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, field.label.count <= 80, ["number","text","boolean"].contains(field.type) else { throw DocumentError.invalid("Invalid form field.") } }
		}
		guard (c.field?.count ?? 0) <= 32, (c.text?.count ?? 0) <= 240, c.metric == nil || health_metrics.contains(c.metric!), (c.groups?.count ?? 0) <= 20, c.groups?.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 40 }) ?? true else { throw DocumentError.invalid("Invalid block settings.") }
		let allowed = ["calculate":["add","subtract","multiply","divide"], "aggregate":["sum","average","minimum","maximum","count"], "text_compare":["equals","contains","starts_with"]]
		if let operation = c.operation { guard ["add","subtract","multiply","divide","sum","average","minimum","maximum","count","equals","contains","starts_with"].contains(operation), allowed[node.kind]?.contains(operation) ?? true else { throw DocumentError.invalid("Choose an operation supported by this block.") } }
		if node.kind == "app_gate" { guard !(c.groups ?? []).isEmpty else { throw DocumentError.invalid("Choose at least one app group for App gate.") } }
	}
	static func run(_ node: BehaviorNode, state: inout BehaviorState, context: BehaviorContext, signals: [String: [String: BehaviorSignal]], connections: [BehaviorEdge], actions: inout [BuilderAction], day: String) throws -> [String: BehaviorSignal] {
		var data = state.data ?? BuilderState(); let c = node.config; let pulse = String(state.sequence); var output: [String: BehaviorSignal] = [:]
		func input(_ port: String) -> BehaviorSignal { guard let edge = connections.first(where: { $0.to == node.id && $0.input == port }) else { return BehaviorSignal(value: 0, token: "") }; return signals[edge.from]?[edge.output] ?? BehaviorSignal(value: 0, token: "", available: false) }
		func emit(_ port: String, _ value: Double, token: String? = nil) { let valid = value.isFinite && abs(value) <= 1000000; output[port] = BehaviorSignal(value: valid ? value : 0, token: token ?? String(value), type: BehaviorGraph.node_ports(node.kind, c).outputs[port] ?? "number", available: valid) }
		func scalar(_ port: String, _ value: BuilderValue) { switch value { case .number(let number): emit(port, number); case .boolean(let boolean): emit(port, boolean ? 1 : 0); case .text(let text): output[port] = BehaviorSignal(value: 0, token: text, type: "text", text: text) } }
		func once(_ port: String) -> Bool { let value = input(port); let key = node.id + "." + port; if value.value == 0 { state.fired.removeValue(forKey: key); return false }; if state.fired[key] == value.token { return false }; state.fired[key] = value.token; return true }
		switch node.kind {
		case "number_input", "text_input", "checkbox":
			let incoming = context.inputs[node.id]
			if let incoming { let expected = node.kind == "number_input" ? "number" : node.kind == "text_input" ? "text" : "boolean"; guard incoming.type == expected else { throw DocumentError.invalid("Input value has the wrong type.") }; data.inputs[node.id] = incoming }
			scalar(node.kind == "checkbox" ? "checked" : "value", data.inputs[node.id] ?? (node.kind == "number_input" ? .number(c.value) : node.kind == "text_input" ? .text(c.text ?? "") : .boolean(false))); emit("changed", incoming == nil ? 0 : 1, token: pulse)
		case "form":
			let submitted = context.submission?.node == node.id
			if submitted {
				var record: [String: BuilderValue] = [:]
				for field in c.fields ?? fields {
					let value = context.submission?.values[field.id]
					if value == nil || (value?.type == "text" && value?.display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) { guard !field.required else { throw DocumentError.invalid("Fill in " + field.label + ".") }; record[field.id] = field.type == "text" ? .text("") : field.type == "number" ? .number(0) : .boolean(false) }
					else { guard value!.type == field.type else { throw DocumentError.invalid("Wrong value type for " + field.label + ".") }; record[field.id] = value }
				}
				data.forms[node.id] = record
			}
			let record = data.forms[node.id]
			output["record"] = BehaviorSignal(value: 0, token: pulse, type: "record", available: record != nil, record: record ?? [:]); emit("submitted", submitted ? 1 : 0, token: pulse)
			for field in c.fields ?? fields { scalar(field.id, record?[field.id] ?? (field.type == "text" ? .text("") : field.type == "number" ? .number(0) : .boolean(false))); output[field.id]?.available = record != nil }
		case "save_entry":
			if once("clear") { data.entries[node.id] = [] }
			let saved = once("save")
			if saved { let record = input("record").record ?? [:]; guard record.count <= 8 else { throw DocumentError.invalid("An entry supports at most eight fields.") }; data.entries[node.id] = Array(((data.entries[node.id] ?? []) + [BuilderEntry(id: node.id + "-" + pulse, at: context.now.timeIntervalSince1970 * 1000, values: record)]).suffix(200)) }
			let rows = data.entries[node.id] ?? []; output["rows"] = BehaviorSignal(value: 0, token: pulse, type: "table", rows: rows); emit("count", Double(rows.count)); emit("saved", saved ? 1 : 0, token: pulse)
		case "aggregate":
			let rows = input("rows").rows ?? []; let values = rows.compactMap { $0.values[c.field ?? "value"]?.number }; let operation = c.operation ?? "sum"
			let value: Double
			switch operation { case "count": value = Double(rows.count); case "average": value = values.isEmpty ? 0 : values.reduce(0,+)/Double(values.count); case "minimum": value = values.min() ?? 0; case "maximum": value = values.max() ?? 0; default: value = values.reduce(0,+) }; emit("value", value)
		case "calculate":
			let a = input("a").value, b = input("b").value; let value: Double
			switch c.operation ?? "add" { case "subtract": value = a-b; case "multiply": value = a*b; case "divide": value = a/b; default: value = a+b }; emit("value", value)
		case "text_compare": let text = input("text").text ?? "", target = c.text ?? ""; let matches = c.operation == "contains" ? text.contains(target) : c.operation == "starts_with" ? text.hasPrefix(target) : text == target; emit("result", matches ? 1 : 0)
		case "table", "chart": output["rows"] = input("rows")
		case "progress": let value = input("value").value; emit("value", value); emit("fraction", c.value > 0 ? max(0,min(1,value/c.value)) : 0)
		case "health": let value = context.health[c.metric ?? "steps"]; emit("value", value ?? 0); output["value"]?.available = value != nil
		case "app_gate": let active = input("closed").value != 0; if data.gates[node.id] != active || context.reconcile_actions { actions.append(BuilderAction(id: node.id, kind: node.kind, token: node.id + ":" + String(active), active: active, groups: c.groups ?? [])); data.gates[node.id] = active }; emit("active", active ? 1 : 0)
		case "add_allowance": let grant = input("grant").value != 0 && data.rewards[node.id] != day; if grant { actions.append(BuilderAction(id: node.id, kind: node.kind, token: node.id + ":" + day, minutes: c.minutes)); data.rewards[node.id] = day }; emit("granted", grant ? 1 : 0, token: day)
		default: throw DocumentError.invalid("Unknown building block.")
		}
		state.data = data
		return output
	}
}
