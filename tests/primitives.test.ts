import { describe, expect, it } from "vitest";
import { behavior_config_schema, behavior_order, initial_behaviors, run_behaviors, type BehaviorKind, type BehaviorConfig, type BehaviorNode, type Behaviors } from "../lib/behaviors";
import { document_schema, starter_document } from "../lib/document";
import { compile_graph, graph_from_document } from "../lib/logic-graph";
import { blank_tool } from "../lib/templates";
import { add_connected_block } from "../lib/creation";
import { cloud_compatible_library, merge_libraries } from "../lib/sync";
import type { Library } from "../lib/library";

function node(id: string, kind: BehaviorKind, config: Partial<BehaviorConfig> = {}): BehaviorNode { return { id, kind, x: 0, y: 0, config: behavior_config_schema.parse({ label: id, ...config }) }; }
function wire(from: string, output: string, to: string, input: string) { return { from, output, to, input }; }
function allowance(change: "set" | "add" | "subtract" | "reset" = "add"): Behaviors {
	return { nodes: [node("allowance", "variable", { value: 30, unit: "minutes" }), node("button", "button"), node("change", "change_value", { variable_id: "allowance", change, value: 15 }), node("compare", "compare", { value: 40 })], connections: [wire("button", "pressed", "change", "when"), wire("allowance", "value", "compare", "value")] };
}

describe("user-defined variables", () => {
	it("changes a named variable before downstream rules in the same evaluation", () => {
		const result = run_behaviors(allowance(), initial_behaviors(), { now: 0, tap: "button" });
		expect(result.state.values.allowance).toBe(45); expect(result.signals.allowance.value.value).toBe(45); expect(result.signals.compare.result.value).toBe(true);
		expect(run_behaviors(allowance(), result.state, { now: 1000 }).state.values.allowance).toBe(45);
		expect(run_behaviors(allowance(), JSON.parse(JSON.stringify(result.state)), { now: 2000, tap: "button" }).state.values.allowance).toBe(60);
	});
	it.each([["set", 15], ["subtract", 15], ["reset", 30]] as const)("supports %s without a built-in reward policy", (operation, expected) => {
		const state = initial_behaviors(); state.values.allowance = 30;
		expect(run_behaviors(allowance(operation), state, { now: 0, tap: "button" }).state.values.allowance).toBe(expected);
	});
	it("uses connected fractional amounts and keeps a held condition from repeating", () => {
		const graph = allowance(); graph.nodes[1] = node("button", "checkbox"); graph.nodes.push(node("amount", "number_input", { value: 2.5 })); graph.connections[0].output = "checked"; graph.connections.push(wire("amount", "value", "change", "amount"));
		let result = run_behaviors(graph, initial_behaviors(), { now: 0, inputs: { button: true } }); expect(result.state.values.allowance).toBe(32.5);
		result = run_behaviors(graph, result.state, { now: 1000 }); expect(result.state.values.allowance).toBe(32.5);
		result = run_behaviors(graph, result.state, { now: 2000, inputs: { button: false } });
		result = run_behaviors(graph, result.state, { now: 3000, inputs: { button: true } }); expect(result.state.values.allowance).toBe(35);
	});
	it("rejects writes to measured usage, missing variables, and feedback loops", () => {
		const graph = allowance(); graph.nodes[0].kind = "app_usage"; graph.connections[1].output = "minutes"; expect(() => behavior_order(graph, {}, true)).toThrow("variable");
		const loop = allowance(); loop.connections.push(wire("allowance", "value", "change", "amount")); expect(() => behavior_order(loop, {}, true)).toThrow("loop");
		const missing = allowance(); missing.nodes[2].config.variable_id = "gone"; expect(() => behavior_order(missing, {}, true)).toThrow("variable");
	});
	it("keeps combined conditions latched while allowing repeated gated events", () => {
		const graph = allowance(); graph.nodes.push(node("condition", "checkbox"), node("combine", "or"));
		graph.connections[0] = wire("combine", "result", "change", "when");
		graph.connections.push(wire("condition", "checked", "combine", "a"), wire("button", "pressed", "combine", "b"));
		let result = run_behaviors(graph, initial_behaviors(), { now: 0, inputs: { condition: true } }); expect(result.state.values.allowance).toBe(45);
		result = run_behaviors(graph, result.state, { now: 1000, tap: "button" }); expect(result.state.values.allowance).toBe(60);
		result = run_behaviors(graph, result.state, { now: 2000 }); expect(result.state.values.allowance).toBe(60);
		result = run_behaviors(graph, result.state, { now: 3000, tap: "button" }); expect(result.state.values.allowance).toBe(75);
		result = run_behaviors(graph, result.state, { now: 4000 }); expect(result.state.values.allowance).toBe(75);
		graph.nodes.find(item => item.id === "combine")!.kind = "and";
		result = run_behaviors(graph, result.state, { now: 5000 });
		result = run_behaviors(graph, result.state, { now: 6000, tap: "button" }); expect(result.state.values.allowance).toBe(90);
		result = run_behaviors(graph, result.state, { now: 7000, tap: "button" }); expect(result.state.values.allowance).toBe(105);
	});
	it("rejects mixed continuous and event-based writers and overflows atomically", () => {
		const graph = allowance(); graph.nodes.push(node("source", "number_input")); graph.connections.push(wire("source", "value", "allowance", "set")); expect(() => behavior_order(graph, {}, true)).toThrow("continuous");
		const state = initial_behaviors(); state.values.allowance = 1000000; expect(() => run_behaviors(allowance(), state, { now: 0, tap: "button" })).toThrow("1,000,000"); expect(state.fired).toEqual({}); expect(state.values.allowance).toBe(1000000);
	});
	it("supports connected comparison and progress targets", () => {
		const graph = allowance(); graph.nodes.push(node("usage", "app_usage"), node("progress", "progress")); graph.connections = [wire("button", "pressed", "change", "when"), wire("usage", "minutes", "compare", "value"), wire("allowance", "value", "compare", "threshold"), wire("usage", "minutes", "progress", "value"), wire("allowance", "value", "progress", "target")];
		const result = run_behaviors(graph, initial_behaviors(), { now: 0, usage_minutes: 40, tap: "button" }); expect(result.signals.compare.result.value).toBe(false); expect(result.signals.progress.target.value).toBe(45); expect(result.signals.progress.fraction.value).toBeCloseTo(40 / 45);
	});
});

describe("general timers and records", () => {
	it("adds no blocking or native focus session automatically", () => {
		const base = blank_tool(); const result = add_connected_block(graph_from_document(base), "elapsed_timer"); const document = compile_graph(base, result.graph);
		expect(document.schema_version).toBe(4); expect(document.blocks).toEqual(base.blocks); expect(document.rules.block_during_focus).toBe(false);
		expect(document_schema.safeParse({ ...document, schema_version: 3 }).success).toBe(false);
	});
	it("counts down, pauses, resumes, finishes once, resets and restarts", () => {
		const graph: Behaviors = { nodes: [node("timer", "elapsed_timer", { value: 2 }), node("visits", "variable", { value: 0 }), node("change", "change_value", { variable_id: "visits", value: 1 })], connections: [wire("timer", "finished", "change", "when")] };
		let result = run_behaviors(graph, initial_behaviors(), { now: 0, timer_command: { node: "timer", action: "start" } });
		result = run_behaviors(graph, result.state, { now: 60000, timer_command: { node: "timer", action: "pause" } }); expect(result.signals.timer.remaining.value).toBe(1);
		result = run_behaviors(graph, result.state, { now: 600000 }); expect(result.signals.timer.remaining.value).toBe(1);
		result = run_behaviors(graph, JSON.parse(JSON.stringify(result.state)), { now: 600000, timer_command: { node: "timer", action: "start" } });
		result = run_behaviors(graph, result.state, { now: 660000 }); expect(result.signals.timer.finished.value).toBe(true); expect(result.state.values.visits).toBe(1);
		result = run_behaviors(graph, result.state, { now: 670000 }); expect(result.state.values.visits).toBe(1);
		result = run_behaviors(graph, result.state, { now: 680000, timer_command: { node: "timer", action: "reset" } }); expect(result.signals.timer.elapsed.value).toBe(0);
		result = run_behaviors(graph, result.state, { now: 680000, timer_command: { node: "timer", action: "start" } });
		result = run_behaviors(graph, result.state, { now: 800000 }); expect(result.state.values.visits).toBe(2);
	});
	it("builds a record from stopwatch duration and saves it on stop", () => {
		const graph: Behaviors = { nodes: [node("timer", "elapsed_timer", { timer_mode: "stopwatch" }), node("record", "record", { fields: [{ id: "minutes", label: "Gym minutes", type: "number", required: true }] }), node("save", "save_entry")], connections: [wire("timer", "elapsed", "record", "minutes"), wire("record", "record", "save", "record"), wire("timer", "finished", "save", "save")] };
		let result = run_behaviors(graph, initial_behaviors(), { now: 0, timer_command: { node: "timer", action: "start" } });
		result = run_behaviors(graph, result.state, { now: 2700000, timer_command: { node: "timer", action: "stop" } });
		expect(result.signals.timer.elapsed.value).toBe(45); expect(result.signals.timer.remaining.available).toBe(false); expect(result.state.data?.entries.save[0].values.minutes).toBe(45);
		result = run_behaviors(graph, result.state, { now: 3000000 }); expect(result.state.data?.entries.save).toHaveLength(1);
	});
	it("captures a connected duration on start rather than moving the end during a run", () => {
		const graph: Behaviors = { nodes: [node("duration", "number_input", { value: 3 }), node("start", "button"), node("timer", "elapsed_timer")], connections: [wire("duration", "value", "timer", "duration"), wire("start", "pressed", "timer", "start")] };
		let result = run_behaviors(graph, initial_behaviors(), { now: 0, tap: "start" });
		result = run_behaviors(graph, result.state, { now: 60000, inputs: { duration: 10 } }); expect(result.signals.timer.remaining.value).toBe(2);
	});
	it("evaluates overnight windows using the previous day without blocking anything", () => {
		const graph: Behaviors = { nodes: [node("window", "time_window", { time: "22:00", end_time: "07:00", days: [2] })], connections: [] };
		expect(run_behaviors(graph, initial_behaviors(), { now: new Date(2026, 8, 22, 6).getTime() }).signals.window.active.value).toBe(true);
		expect(run_behaviors(graph, initial_behaviors(), { now: new Date(2026, 8, 22, 7).getTime() }).signals.window.active.value).toBe(false);
	});
	it("uses typed defaults for optional record fields", () => {
		const graph: Behaviors = { nodes: [node("record", "record", { fields: [{ id: "minutes", label: "Minutes", type: "number", required: false }, { id: "note", label: "Note", type: "text", required: false }] })], connections: [] };
		expect(run_behaviors(graph, initial_behaviors(), { now: 0 }).signals.record.record.value).toEqual({ minutes: 0, note: "" });
	});
	it("controls app access only through explicit timer and window connections", () => {
		const graph: Behaviors = { nodes: [node("timer", "elapsed_timer", { value: 120 }), node("window", "time_window", { time: "08:00", end_time: "10:00" }), node("both", "and"), node("gate", "app_gate", { groups: ["Social"] })], connections: [wire("timer", "running", "both", "a"), wire("window", "active", "both", "b"), wire("both", "result", "gate", "closed")] };
		const now = new Date(2026, 8, 20, 9, 59).getTime();
		let result = run_behaviors(graph, initial_behaviors(), { now }); expect(result.signals.gate.active.value).toBe(false);
		result = run_behaviors(graph, result.state, { now, timer_command: { node: "timer", action: "start" } }); expect(result.actions).toContainEqual(expect.objectContaining({ kind: "app_gate", active: true, groups: ["Social"] }));
		result = run_behaviors(graph, result.state, { now: now + 60000 }); expect(result.signals.timer.running.value).toBe(true); expect(result.actions).toContainEqual(expect.objectContaining({ kind: "app_gate", active: false }));
	});
});

describe("phone compatibility", () => {
	it("preserves old routine formats and keeps new primitives away from cloud sync", () => {
		expect(compile_graph(starter_document, graph_from_document(starter_document))).toEqual(starter_document);
		const document = compile_graph(starter_document, { ...graph_from_document(starter_document), nodes: [...graph_from_document(starter_document).nodes, node("timer2", "elapsed_timer")] });
		const remote: Library = { schema_version: 1, tools: [{ document: starter_document, updated_at: "2026-09-20T10:00:00Z" }] };
		const local: Library = { schema_version: 1, tools: [{ document, updated_at: "2026-09-20T09:00:00Z" }] };
		expect(merge_libraries(local, remote, Date.now()).tools[0].document.schema_version).toBe(4);
		expect(cloud_compatible_library(local, remote).tools[0].document).toEqual(starter_document);
		expect(cloud_compatible_library(local, null).tools).toHaveLength(0);
	});
});
