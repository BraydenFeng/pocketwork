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
}
