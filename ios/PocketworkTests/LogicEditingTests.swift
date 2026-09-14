import XCTest
@testable import Pocketwork

final class LogicEditingTests: XCTestCase {
	func testCreatesConnectedRoutineAndRoundTrips() throws {
		var base = AppDocument.blank(); base.blocks.append(BlockDocument.make(.note))
		var graph = LogicEditing(document: base)
		let tap = try graph.add("check_in"), count = try graph.add("count"), goal = try graph.add("goal"), reminder = try graph.add("reminder")
		try graph.connect(BehaviorEdge(from: tap, output: "done", to: count, input: "increment"))
		try graph.connect(BehaviorEdge(from: count, output: "value", to: goal, input: "value"))
		try graph.connect(BehaviorEdge(from: goal, output: "reached", to: reminder, input: "send"))
		let result = try graph.compile(base: base)
		XCTAssertEqual(result.schema_version, 3); XCTAssertEqual(result.blocks, base.blocks)
		XCTAssertEqual(result.behaviors?.nodes.count, 4)
		let decoded = try AppDocument.decode(JSONEncoder().encode(result))
		XCTAssertEqual(try LogicEditing(document: decoded).compile(base: decoded), result)
		let runtime = try BehaviorRuntime.run(try XCTUnwrap(result.behaviors), state: BehaviorState(), context: BehaviorContext(now: .now, tap: tap))
		XCTAssertEqual(runtime.messages.count, 1)
	}
	func testConnectionValidationIsAtomicAndAllowsDrafts() throws {
		var graph = LogicEditing(document: .blank())
		let tap = try graph.add("button"), count = try graph.add("count"), a = try graph.add("not"), b = try graph.add("not")
		XCTAssertThrowsError(try graph.connect(BehaviorEdge(from: count, output: "value", to: a, input: "condition")))
		XCTAssertTrue(graph.connections.isEmpty)
		try graph.connect(BehaviorEdge(from: tap, output: "pressed", to: a, input: "condition"))
		XCTAssertThrowsError(try graph.connect(BehaviorEdge(from: b, output: "result", to: a, input: "condition")))
		graph.connections = []
		try graph.connect(BehaviorEdge(from: a, output: "result", to: b, input: "condition"))
		XCTAssertThrowsError(try graph.connect(BehaviorEdge(from: b, output: "result", to: a, input: "condition")))
		XCTAssertEqual(graph.connections.count, 1)
		XCTAssertThrowsError(try graph.compile(base: .blank()))
	}
	func testLegacyTimerAndBlockingConnections() throws {
		let base = AppDocument.blank(); var graph = LogicEditing(document: base)
		let timer = try graph.add("timer"), apps = try graph.add("apps"), notification = try graph.add("notification")
		try graph.connect(BehaviorEdge(from: timer, output: "active", to: apps, input: "gate"))
		try graph.connect(BehaviorEdge(from: timer, output: "finished", to: notification, input: "finished"))
		let result = try graph.compile(base: base)
		XCTAssertTrue(result.rules.block_during_focus); XCTAssertTrue(result.rules.notify_on_complete)
		XCTAssertEqual(result.schema_version, 1)
		XCTAssertThrowsError(try graph.add("timer")); XCTAssertThrowsError(try graph.add("schedule"))
		XCTAssertEqual(try LogicEditing(document: result).compile(base: result), result)
		graph.remove(notification)
		XCTAssertFalse(try graph.compile(base: base).rules.notify_on_complete)
	}
	func testPreservesHomeAllowanceAndRejectsBrokenTopology() throws {
		var base = AppDocument.blank()
		base.blocks.append(BlockDocument.make(.schedule)); base.blocks.append(BlockDocument.make(.screen_time))
		base.blocks[2].groups = ["Distractions"]
		base.enabled = true; base.schema_version = 2; base.rules.block_during_focus = true
		base.blocks[1].days = [1,2,3,4,5,6,7]; base.blocks[1].start = "00:00"; base.blocks[1].end = "23:59"
		base.home_allowance = HomePolicy(timezone: "America/Los_Angeles", away_usage_counts: false, outside_windows: "block_at_home", rules: [HomeDayRule(days: [1,2,3,4,5,6,7], allowance_minutes: 120, windows: [HomeWindow(start: "06:30", end: "20:30")])])
		try base.validate()
		var graph = LogicEditing(document: base)
		XCTAssertEqual(try graph.compile(base: base), base)
		let counter = try graph.add("variable")
		let next = try graph.compile(base: base)
		XCTAssertEqual(next.home_allowance, base.home_allowance); XCTAssertEqual(next.enabled, true)
		graph.remove(counter); graph.connections.removeFirst()
		XCTAssertThrowsError(try graph.compile(base: base))
	}
	func testOutsideWindowsIsUnrestrictedUnlessWired() throws {
		var base = AppDocument.blank()
		base.blocks = [BlockDocument.make(.heading), BlockDocument.make(.schedule), BlockDocument.make(.screen_time)]
		base.blocks[2].groups = ["Distractions"]; base.schema_version = 2; base.rules.block_during_focus = true; base.enabled = false
		base.blocks[1].days = [1,2,3,4,5,6,7]; base.blocks[1].start = "00:00"; base.blocks[1].end = "23:59"
		base.home_allowance = HomePolicy(timezone: "America/Los_Angeles", away_usage_counts: false, outside_windows: "unrestricted", rules: [HomeDayRule(days: [1,2,3,4,5,6,7], allowance_minutes: 30, windows: [HomeWindow(start: "18:00", end: "20:00")])])
		try base.validate()
		XCTAssertFalse(base.home_allowance!.blocks_outside)
		var graph = LogicEditing(document: base)
		XCTAssertFalse(graph.connections.contains { $0.input == "outside" })
		XCTAssertEqual(try graph.compile(base: base).home_allowance?.outside_windows, "unrestricted")
		let schedule = try XCTUnwrap(graph.nodes.first { $0.kind == "schedule" }), apps = try XCTUnwrap(graph.nodes.first { $0.kind == "apps" })
		try graph.connect(BehaviorEdge(from: schedule.id, output: "outside", to: apps.id, input: "outside"))
		XCTAssertEqual(try graph.compile(base: base).home_allowance?.outside_windows, "block_at_home")
		var legacy = base; legacy.home_allowance?.outside_windows = "block_at_home"
		let migrated = try ToolLibrary.empty.upserting(legacy, now: .now).migrated()
		XCTAssertEqual(migrated.tools.first?.document.home_allowance?.outside_windows, "unrestricted")
	}
	func testDeleteRemovesWiresAndReturningToLegacyFormat() throws {
		let base = AppDocument.blank(); var graph = LogicEditing(document: base)
		let timer = try graph.add("timer"), reminder = try graph.add("reminder")
		try graph.connect(BehaviorEdge(from: timer, output: "finished", to: reminder, input: "send"))
		let result = try graph.compile(base: base)
		XCTAssertEqual(result.schema_version, 3)
		graph.remove(timer); XCTAssertTrue(graph.connections.isEmpty)
		XCTAssertThrowsError(try graph.compile(base: result))
		graph.remove(reminder)
		let empty = try graph.compile(base: result)
		XCTAssertEqual(empty.schema_version, 1); XCTAssertNil(empty.behaviors)
		XCTAssertEqual(empty.blocks, base.blocks)
	}
	func testEveryBehaviorCanBeAddedAndPositionsDoNotOverlap() throws {
		// The catalog grows over time; what matters is that every kind can be added once and none of them land on top of each other.
		var graph = LogicEditing(document: .blank())
		let kinds = BehaviorGraph.ports.keys.sorted()
		for kind in kinds { _ = try graph.add(kind) }
		XCTAssertEqual(graph.nodes.count, kinds.count)
		for (index, node) in graph.nodes.enumerated() { for other in graph.nodes.dropFirst(index + 1) { XCTAssertTrue(abs(node.x - other.x) >= 280 || abs(node.y - other.y) >= 220) } }
		for _ in kinds.count..<48 { _ = try graph.add("button") }
		XCTAssertThrowsError(try graph.add("button"))
	}
}
