import XCTest
@testable import Pocketwork

final class BehaviorTests: XCTestCase {
	struct Fixture: Decodable {
		var name: String; var graph: BehaviorGraph; var steps: [Step]
		struct Step: Decodable { var now: Double; var tap: String?; var location: Bool?; var usage: Double?; var values: [String: Double]?; var messages: Int }
	}
	func testSharedRuntimeFixtures() throws {
		let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "behavior-fixtures", withExtension: "json"))
		let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
		for fixture in fixtures {
			var state = BehaviorState()
			for step in fixture.steps {
				let result = try BehaviorRuntime.run(fixture.graph, state: state, context: BehaviorContext(now: Date(timeIntervalSince1970: step.now), at_location: step.location, usage_minutes: step.usage, tap: step.tap))
				state = try JSONDecoder().decode(BehaviorState.self, from: JSONEncoder().encode(result.state))
				XCTAssertEqual(result.messages.count, step.messages, fixture.name)
				for (id,value) in step.values ?? [:] { XCTAssertEqual(state.values[id], value, fixture.name) }
			}
		}
	}
	func testRejectsCyclesAndMissingInputs() throws {
		let config = BehaviorConfig(label: "", value: 1, minutes: 1, time: "18:00", days: [1,2,3,4,5,6,7], message: "", operator: "gte")
		let graph = BehaviorGraph(nodes: [BehaviorNode(id: "a",kind: "not",x: 0,y: 0,config: config),BehaviorNode(id: "b",kind: "not",x: 0,y: 0,config: config)], connections: [BehaviorEdge(from: "a",output: "result",to: "b",input: "condition"),BehaviorEdge(from: "b",output: "result",to: "a",input: "condition")])
		XCTAssertThrowsError(try graph.ordered(external: [:]))
		XCTAssertThrowsError(try BehaviorGraph(nodes: graph.nodes,connections: []).ordered(external: [:]))
	}
	func testStreakUsesCalendarDays() throws {
		let config = BehaviorConfig(label: "", value: 1, minutes: 1, time: "18:00", days: [1,2,3,4,5,6,7], message: "", operator: "gte")
		let graph = BehaviorGraph(nodes: [BehaviorNode(id: "tap",kind: "check_in",x: 0,y: 0,config: config),BehaviorNode(id: "streak",kind: "streak",x: 0,y: 0,config: config)], connections: [BehaviorEdge(from: "tap",output: "done",to: "streak",input: "check_in")])
		var state = BehaviorState(); var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
		for (day,expected) in [(1,1.0),(1,1.0),(2,2.0),(4,1.0)] {
			let date = calendar.date(from: DateComponents(year: 2026,month: 9,day: day,hour: 12))!
			let result = try BehaviorRuntime.run(graph,state: state,context: BehaviorContext(now: date,tap: "tap",calendar: calendar)); state=result.state
			XCTAssertEqual(result.signals["streak"]?["days"]?.value,expected)
		}
	}

	func testFormatThreeLibraryRoundTrip() throws {
		let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "behavior-fixtures", withExtension: "json"))
		let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
		var document = AppDocument.blank()
		document.schema_version = 3; document.behaviors = fixtures[0].graph
		let decoded = try AppDocument.decode(JSONEncoder().encode(document))
		XCTAssertEqual(decoded, document)
		let library = try ToolLibrary.empty.upserting(document, now: .now)
		XCTAssertEqual(try ToolLibrary.decode(library.encoded()), library)
	}

	func testIfElsePreferenceRoundTrips() throws {
		let config = BehaviorConfig(label: "If", value: 1, minutes: 1, time: "18:00", days: [1,2,3,4,5,6,7], message: "", operator: "gte", else_enabled: true)
		let decoded = try JSONDecoder().decode(BehaviorConfig.self, from: JSONEncoder().encode(config))
		XCTAssertEqual(decoded.else_enabled, true)
	}

	func testGraphEditsPreserveProgressAndRemoveDetachedState() throws {
		let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "behavior-fixtures", withExtension: "json"))
		let old = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))[0].graph
		var next = old; next.nodes[1].config.label = "Gym visits"; next.nodes[1].x = 100
		var state = BehaviorState(); state.values["count"] = 7; state.days["tap"] = "2026-09-13"; state.fired["count.increment"] = "4"
		state.reconcile(from: old, to: next)
		XCTAssertEqual(state.values["count"], 7); XCTAssertEqual(state.days["tap"], "2026-09-13"); XCTAssertEqual(state.fired["count.increment"], "4")
		next.nodes.removeAll { $0.id == "count" }; next.connections.removeAll { $0.from == "count" || $0.to == "count" }
		state.reconcile(from: old, to: next)
		XCTAssertNil(state.values["count"]); XCTAssertNil(state.fired["count.increment"])
	}

	func testCalculatedScreenTimeRewardAndUsageHistory() throws {
		func config(_ label: String, operation: String? = nil, value: Double = 1, metric: String? = nil, field: String? = nil) -> BehaviorConfig {
			BehaviorConfig(label: label, value: value, minutes: 5, time: "18:00", days: [1,2,3,4,5,6,7], message: "", operator: "gte", field: field, operation: operation, metric: metric)
		}
		func node(_ id: String, _ kind: String, _ config: BehaviorConfig) -> BehaviorNode { BehaviorNode(id: id, kind: kind, x: 0, y: 0, config: config) }
		func edge(_ from: String, _ output: String, _ to: String, _ input: String) -> BehaviorEdge { BehaviorEdge(from: from, output: output, to: to, input: input) }
		let graph = BehaviorGraph(nodes: [
			node("weekend", "checkbox", config("Weekend")), node("steps", "health", config("Steps", metric: "steps")),
			node("step_size", "number_input", config("Step size", value: 3000)), node("groups", "calculate", config("Groups", operation: "divide")),
			node("whole", "calculate", config("Whole groups", operation: "floor")), node("reward_size", "number_input", config("Reward size", value: 40)),
			node("minutes", "calculate", config("Minutes", operation: "multiply")), node("reward", "add_allowance", config("Reward")),
			node("usage", "app_usage", config("Usage")), node("chart", "chart", config("Chart", field: "minutes")),
		], connections: [
			edge("steps", "value", "groups", "a"), edge("step_size", "value", "groups", "b"), edge("groups", "value", "whole", "a"),
			edge("whole", "value", "minutes", "a"), edge("reward_size", "value", "minutes", "b"), edge("weekend", "checked", "reward", "grant"),
			edge("minutes", "value", "reward", "minutes"), edge("usage", "history", "chart", "rows"),
		])
		let history = [BuilderEntry(id: "2026-09-29", at: 1, values: ["minutes":.number(42), "budget":.number(60)])]
		var result = try BehaviorRuntime.run(graph, state: BehaviorState(), context: BehaviorContext(now: Date(timeIntervalSince1970: 0), at_location: nil, usage_minutes: 42, usage_history: history, tap: nil, inputs: ["weekend":.boolean(true)], health: ["steps":7500]))
		XCTAssertEqual(result.actions.first?.minutes, 80); XCTAssertEqual(result.signals["chart"]?["rows"]?.rows, history)
		result = try BehaviorRuntime.run(graph, state: result.state, context: BehaviorContext(now: Date(timeIntervalSince1970: 1), at_location: nil, usage_minutes: 42, usage_history: history, tap: nil, health: ["steps":7500]))
		XCTAssertTrue(result.actions.isEmpty)
		result = try BehaviorRuntime.run(graph, state: result.state, context: BehaviorContext(now: Date(timeIntervalSince1970: 2), at_location: nil, usage_minutes: 42, usage_history: history, tap: nil, health: ["steps":9000]))
		XCTAssertEqual(result.actions.first?.minutes, 120)
		var document = AppDocument.blank(); document.schema_version = 5; document.behaviors = graph
		XCTAssertNoThrow(try document.validate()); document.schema_version = 4; XCTAssertThrowsError(try document.validate())
	}
}
