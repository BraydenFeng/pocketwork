import XCTest
@testable import Pocketwork

final class PrimitiveTests: XCTestCase {
	private func node(_ id: String, _ kind: String, _ value: Double = 1) -> BehaviorNode {
		BehaviorNode(id: id, kind: kind, x: 0, y: 0, config: BehaviorConfig(label: id, value: value, minutes: 5, time: "18:00", days: [1,2,3,4,5,6,7], message: "", operator: "gte"))
	}
	private func edge(_ from: String, _ output: String, _ to: String, _ input: String) -> BehaviorEdge { BehaviorEdge(from: from, output: output, to: to, input: input) }
	private func run(_ graph: BehaviorGraph, _ state: BehaviorState = BehaviorState(), at: Double = 0, command: String? = nil, tap: String? = nil) throws -> BehaviorResult {
		try BehaviorRuntime.run(graph, state: state, context: BehaviorContext(now: Date(timeIntervalSince1970: at), tap: tap, timer_command: command.map { PrimitiveTimerCommand(node: "timer", action: $0) }))
	}
	func testVariableMutationsAndSameEvaluationRead() throws {
		var change = node("change", "change_value", 2.5); change.config.variable_id = "amount"
		let graph = BehaviorGraph(nodes: [node("amount", "variable", 30), node("tap", "button"), change, node("check", "compare", 32)], connections: [edge("tap", "pressed", "change", "when"), edge("amount", "value", "check", "value")])
		let first = try run(graph, tap: "tap")
		XCTAssertEqual(first.state.values["amount"], 32.5); XCTAssertEqual(first.signals["check"]?["result"]?.value, 1)
		XCTAssertEqual(try run(graph, first.state).state.values["amount"], 32.5)
		let restored = try JSONDecoder().decode(BehaviorState.self, from: JSONEncoder().encode(first.state))
		XCTAssertEqual(try run(graph, restored, tap: "tap").state.values["amount"], 35)
		for (operation, expected) in [("set", 2.5), ("subtract", 27.5), ("reset", 30.0)] {
			var copy = graph; copy.nodes[2].config.change = operation
			XCTAssertEqual(try run(copy, tap: "tap").state.values["amount"], expected)
		}
	}
	func testCountdownPauseResumeAndSingleCompletion() throws {
		var change = node("change", "change_value"); change.config.variable_id = "count"
		let graph = BehaviorGraph(nodes: [node("timer", "elapsed_timer", 2), node("count", "variable", 0), change], connections: [edge("timer", "finished", "change", "when")])
		var result = try run(graph, command: "start")
		result = try run(graph, result.state, at: 60, command: "pause"); XCTAssertEqual(result.signals["timer"]?["remaining"]?.value, 1)
		result = try run(graph, result.state, at: 600); XCTAssertEqual(result.signals["timer"]?["remaining"]?.value, 1)
		result = try run(graph, result.state, at: 600, command: "start")
		result = try run(graph, result.state, at: 660); XCTAssertEqual(result.state.values["count"], 1)
		result = try run(graph, result.state, at: 700); XCTAssertEqual(result.state.values["count"], 1)
		result = try run(graph, result.state, at: 700, command: "reset"); XCTAssertEqual(result.signals["timer"]?["elapsed"]?.value, 0)
	}
	func testStopwatchCreatesSavedRecord() throws {
		var timer = node("timer", "elapsed_timer"); timer.config.timer_mode = "stopwatch"
		let graph = BehaviorGraph(nodes: [timer, node("record", "record"), node("save", "save_entry")], connections: [edge("timer", "elapsed", "record", "value"), edge("record", "record", "save", "record"), edge("timer", "finished", "save", "save")])
		var result = try run(graph, command: "start")
		result = try run(graph, result.state, at: 2700, command: "stop")
		XCTAssertEqual(result.state.data?.entries["save"]?.first?.values["value"], .number(45))
		XCTAssertEqual(try run(graph, result.state, at: 3000).state.data?.entries["save"]?.count, 1)
		XCTAssertEqual(result.signals["timer"]?["remaining"]?.available, false)
	}
	func testHeldCompoundConditionsDoNotRepeat() throws {
		var change = node("change", "change_value"); change.config.variable_id = "amount"
		let graph = BehaviorGraph(nodes: [node("amount", "variable", 0), node("switch", "checkbox"), node("tap", "button"), node("either", "or"), change], connections: [edge("switch", "checked", "either", "a"), edge("tap", "pressed", "either", "b"), edge("either", "result", "change", "when")])
		var result = try BehaviorRuntime.run(graph, state: BehaviorState(), context: BehaviorContext(now: .now, inputs: ["switch": .boolean(true)]))
		XCTAssertEqual(result.state.values["amount"], 1)
		result = try run(graph, result.state, tap: "tap"); XCTAssertEqual(result.state.values["amount"], 2)
		result = try run(graph, result.state); XCTAssertEqual(result.state.values["amount"], 2)
	}
	func testRejectsFeedbackAndWrongFormat() throws {
		var change = node("change", "change_value"); change.config.variable_id = "amount"
		var graph = BehaviorGraph(nodes: [node("amount", "variable"), node("tap", "button"), change], connections: [edge("tap", "pressed", "change", "when")])
		var document = AppDocument.blank(); document.schema_version = 4; document.behaviors = graph
		XCTAssertEqual(try AppDocument.decode(JSONEncoder().encode(document)), document)
		document.schema_version = 3; XCTAssertThrowsError(try document.validate())
		graph.connections.append(edge("amount", "value", "change", "amount")); XCTAssertThrowsError(try graph.ordered(external: [:]))
	}
	func testConnectedTargetsAndWindowBoundary() throws {
		let graph = BehaviorGraph(nodes: [node("amount", "variable", 45), node("source", "number_input", 40), node("progress", "progress")], connections: [edge("source", "value", "progress", "value"), edge("amount", "value", "progress", "target")])
		let result = try run(graph); XCTAssertEqual(result.signals["progress"]?["target"]?.value, 45); XCTAssertEqual(try XCTUnwrap(result.signals["progress"]?["fraction"]?.value), 40.0 / 45, accuracy: 0.00001)
		var window = node("window", "time_window"); window.config.time = "22:00"; window.config.end_time = "07:00"; window.config.days = [2]
		var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
		for (hour, active) in [(6, true), (7, false)] { let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: hour))); XCTAssertEqual(PrimitiveRuntime.window_active(window, context: BehaviorContext(now: date, calendar: calendar)), active) }
	}
	func testUnavailableConditionReleasesItsGate() throws {
		var gate = node("gate", "app_gate"); gate.config.groups = ["Social"]
		let graph = BehaviorGraph(nodes: [node("location", "location"), gate], connections: [edge("location", "present", "gate", "closed")])
		let active = try BehaviorRuntime.run(graph, state: BehaviorState(), context: BehaviorContext(now: .now, at_location: true))
		XCTAssertEqual(active.actions.first?.active, true)
		let unavailable = try BehaviorRuntime.run(graph, state: active.state, context: BehaviorContext(now: .now, at_location: nil))
		XCTAssertEqual(unavailable.actions.first?.active, false)
	}
}
