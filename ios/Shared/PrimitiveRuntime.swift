import Foundation

struct PrimitiveTimerCommand { var node: String; var action: String }
struct PrimitiveTimerValue: Codable {
	var elapsed: Double = 0
	var started_at: Double?
	var duration: Double
	var cycle = 0
	var finished = false
}

enum PrimitiveRuntime {
	static let kinds = ["elapsed_timer", "change_value", "time_window", "record"]
	static let ports: [String: (inputs: [String: String], outputs: [String: String])] = [
		"elapsed_timer": (["start":"boolean", "pause":"boolean", "stop":"boolean", "reset":"boolean", "duration":"number"], ["elapsed":"number", "remaining":"number", "running":"boolean", "finished":"boolean"]),
		"change_value": (["when":"boolean", "amount":"number"], ["changed":"boolean", "value":"number"]),
		"time_window": ([:], ["active":"boolean", "outside":"boolean"]),
		"record": (["value":"number"], ["record":"record"])
	]
	static func requires_four(_ graph: BehaviorGraph) -> Bool {
		graph.nodes.contains { kinds.contains($0.kind) || $0.config.unit != nil } || graph.connections.contains { ["threshold", "target"].contains($0.input) }
	}
	static func optional(_ node: BehaviorNode, _ port: String) -> Bool {
		node.kind == "elapsed_timer" || node.kind == "change_value" && port == "amount" || node.kind == "compare" && port == "threshold" || node.kind == "progress" && port == "target" || node.kind == "variable" && port == "set" || node.kind == "count" && port == "reset" || node.kind == "save_entry" && port == "clear" || node.kind == "record" && node.config.fields?.first(where: { $0.id == port })?.required == false
	}
	static func dependencies(_ graph: BehaviorGraph, strict: Bool) throws -> [BehaviorEdge] {
		var result: [BehaviorEdge] = []
		for node in graph.nodes {
			let c = node.config
			if let unit = c.unit { guard unit.count <= 24 else { throw DocumentError.invalid("Use a unit name of 24 characters or less.") } }
			if let mode = c.timer_mode { guard ["countdown", "stopwatch"].contains(mode) else { throw DocumentError.invalid("Unknown timer mode.") } }
			if let change = c.change { guard ["set", "add", "subtract", "reset"].contains(change) else { throw DocumentError.invalid("Unknown variable action.") } }
			if let id = c.variable_id { try AppDocument.validate_id(id) }
			if let end = c.end_time { guard ScheduleWindow.minutes(end) != nil else { throw DocumentError.invalid("Enter a valid end time.") } }
			if node.kind == "elapsed_timer", c.timer_mode != "stopwatch" { guard ((1.0 / 60.0)...10080.0).contains(c.value) else { throw DocumentError.invalid("Countdown duration must be between one second and seven days.") } }
			if node.kind == "time_window" { guard c.time != (c.end_time ?? "20:00") else { throw DocumentError.invalid("A time window needs different start and end times.") } }
			if node.kind != "change_value" { continue }
			guard let target = graph.nodes.first(where: { $0.id == c.variable_id }), target.kind == "variable" else {
				if strict || c.variable_id != nil { throw DocumentError.invalid("Choose an existing variable for " + c.label + ".") }
				continue
			}
			guard !graph.connections.contains(where: { $0.to == target.id && $0.input == "set" }) else { throw DocumentError.invalid("Disconnect the variable's continuous source before using change actions.") }
			result.append(BehaviorEdge(from: node.id, output: "", to: target.id, input: ""))
		}
		return result
	}
	static func once(_ signal: BehaviorSignal, state: inout BehaviorState, key: String) -> Bool {
		guard signal.available else { return false }
		guard signal.value != 0 else { state.fired.removeValue(forKey: key); return false }
		let rising = state.fired[key] == nil
		state.fired[key] = "true"
		let fresh = signal.event_token.map { state.fired[key + ".event"] != $0 } ?? false
		if let token = signal.event_token { state.fired[key + ".event"] = token }
		return rising || fresh
	}
	static func mark_events(_ node: BehaviorNode, outputs: inout [String: BehaviorSignal], input: (String) -> BehaviorSignal) {
		let events = ["button":"pressed", "check_in":"done", "arrive":"arrived", "leave":"left", "clock":"due", "elapsed_timer":"finished", "change_value":"changed", "delay":"done", "reminder":"sent", "number_input":"changed", "text_input":"changed", "checkbox":"changed", "form":"submitted", "save_entry":"saved", "add_allowance":"granted"]
		if let port = events[node.kind], let signal = outputs[port], signal.value != 0, signal.available { outputs[port]?.event_token = node.id + ":" + signal.token }
		if ["and", "or", "branch"].contains(node.kind) {
			let port = node.kind == "branch" ? "yes" : "result"
			let sources = node.kind == "branch" ? [input("condition")] : [input("a"), input("b")]
			let tokens = sources.filter { $0.value != 0 && $0.available }.compactMap(\.event_token)
			if outputs[port]?.value != 0, !tokens.isEmpty { outputs[port]?.event_token = tokens.map { "\($0.count):\($0)" }.joined(separator: "|") }
		}
	}

	static func window_active(_ node: BehaviorNode, context: BehaviorContext) -> Bool {
		let calendar = context.calendar
		let minute = calendar.component(.hour, from: context.now) * 60 + calendar.component(.minute, from: context.now)
		let start = ScheduleWindow.minutes(node.config.time) ?? 0, end = ScheduleWindow.minutes(node.config.end_time ?? "20:00") ?? 0
		let day = calendar.component(.weekday, from: context.now), previous = day == 1 ? 7 : day - 1
		if end > start { return node.config.days.contains(day) && minute >= start && minute < end }
		return node.config.days.contains(day) && minute >= start || node.config.days.contains(previous) && minute < end
	}

	static func timer(_ node: BehaviorNode, state: inout BehaviorState, context: BehaviorContext, input: (String) -> BehaviorSignal, linked: (String) -> Bool) throws -> [String: BehaviorSignal] {
		var timer = state.timers?[node.id] ?? PrimitiveTimerValue(duration: node.config.value)
		let now = context.now.timeIntervalSince1970 * 1000
		let countdown = node.config.timer_mode != "stopwatch"
		let command = context.timer_command?.node == node.id ? context.timer_command?.action : nil
		let start = once(input("start"), state: &state, key: node.id + ".start")
		let pause = once(input("pause"), state: &state, key: node.id + ".pause")
		let stop = once(input("stop"), state: &state, key: node.id + ".stop")
		let reset = once(input("reset"), state: &state, key: node.id + ".reset")
		var elapsed = timer.elapsed + (timer.started_at.map { max(0, now - $0) / 60000 } ?? 0)
		if countdown, timer.started_at != nil, elapsed >= timer.duration { elapsed = timer.duration; timer.finished = true; timer.started_at = nil }
		timer.elapsed = elapsed
		if timer.started_at != nil { timer.started_at = now }
		if reset || command == "reset" { timer.elapsed = 0; timer.finished = false; timer.started_at = nil; timer.cycle += 1 }
		else if stop || command == "stop" { if timer.started_at != nil || timer.elapsed > 0 { timer.finished = true }; timer.started_at = nil }
		else if pause || command == "pause" { timer.started_at = nil }
		else if (start || command == "start"), timer.started_at == nil {
			if timer.finished { timer.elapsed = 0; timer.finished = false }
			if timer.elapsed == 0 {
				let duration = linked("duration") ? input("duration") : BehaviorSignal(value: node.config.value, token: "", type: "number")
				guard !countdown || duration.available && duration.value.isFinite && ((1.0 / 60.0)...10080.0).contains(duration.value) else { throw DocumentError.invalid("A countdown needs a duration between one second and seven days.") }
				timer.duration = duration.value; timer.cycle += 1
			}
			timer.started_at = now
		}
		var timers = state.timers ?? [:]; timers[node.id] = timer; state.timers = timers
		let token = node.id + ":" + String(timer.cycle)
		return ["elapsed": BehaviorSignal(value: timer.elapsed, token: String(timer.elapsed), type: "number"), "remaining": BehaviorSignal(value: countdown ? max(0, timer.duration - timer.elapsed) : 0, token: token, type: "number", available: countdown), "running": BehaviorSignal(value: timer.started_at == nil ? 0 : 1, token: token), "finished": BehaviorSignal(value: timer.finished ? 1 : 0, token: token)]
	}
}
