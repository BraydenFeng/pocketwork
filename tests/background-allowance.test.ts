import { describe, expect, it } from "vitest";
import { derive_home_allowance, is_block_authored_home_allowance } from "../lib/background-allowance";
import { behavior_config_schema, type BehaviorKind, type Behaviors } from "../lib/behaviors";
import { requested_home_policy } from "../lib/home-policy";
import { compile_graph, graph_from_document, type LogicGraph } from "../lib/logic-graph";
import { page_snapshot } from "../lib/page-blocks";
import { blank_tool } from "../lib/templates";

function allowance_graph(): Behaviors {
	const definitions: [string, BehaviorKind, Record<string, unknown>?][] = [
		["home", "location"],
		["usage", "app_usage"],
		["mon-thu-early", "time_window", { days: [2, 3, 4, 5], time: "18:00", end_time: "18:30" }],
		["mon-thu-late", "time_window", { days: [2, 3, 4, 5], time: "19:00", end_time: "20:50" }],
		["friday", "time_window", { days: [6], time: "14:30", end_time: "20:20" }],
		["weekend", "time_window", { days: [1, 7], time: "06:30", end_time: "20:30" }],
		["weekday-window", "or"],
		["weekday-used", "compare", { value: 30, operator: "gte" }],
		["friday-used", "compare", { value: 120, operator: "gte" }],
		["weekend-used", "compare", { value: 180, operator: "gte" }],
		["weekday-limit", "and"],
		["friday-limit", "and"],
		["weekend-limit", "and"],
		["first-limits", "or"],
		["all-limits", "or"],
		["home-limit", "and"],
		["block-apps", "app_gate", { groups: ["Distractions"] }],
	];
	const nodes = definitions.map(([id, kind, settings]) => ({ id, kind, x: 0, y: 0, config: behavior_config_schema.parse({ label: id, ...settings }) }));
	const edge = (from: string, output: string, to: string, input: string) => ({ from, output, to, input });
	return { nodes, connections: [
		edge("mon-thu-early", "active", "weekday-window", "a"), edge("mon-thu-late", "active", "weekday-window", "b"),
		edge("usage", "minutes", "weekday-used", "value"), edge("usage", "minutes", "friday-used", "value"), edge("usage", "minutes", "weekend-used", "value"),
		edge("weekday-window", "result", "weekday-limit", "a"), edge("weekday-used", "result", "weekday-limit", "b"),
		edge("friday", "active", "friday-limit", "a"), edge("friday-used", "result", "friday-limit", "b"),
		edge("weekend", "active", "weekend-limit", "a"), edge("weekend-used", "result", "weekend-limit", "b"),
		edge("weekday-limit", "result", "first-limits", "a"), edge("friday-limit", "result", "first-limits", "b"),
		edge("first-limits", "result", "all-limits", "a"), edge("weekend-limit", "result", "all-limits", "b"),
		edge("home", "present", "home-limit", "a"), edge("all-limits", "result", "home-limit", "b"),
		edge("home-limit", "result", "block-apps", "closed"),
	] };
}

describe("block-authored background allowances", () => {
	it("derives the exact native home policy from ordinary blocks", () => {
		expect(derive_home_allowance(allowance_graph())).toMatchObject({ policy: requested_home_policy, group: "Distractions" });
	});

	it("compiles native enforcement while keeping the ordinary blocks visible", () => {
		const behaviors = allowance_graph();
		const graph: LogicGraph = { nodes: behaviors.nodes, connections: behaviors.connections };
		const document = compile_graph(blank_tool(), graph);
		expect(document.home_allowance).toEqual(requested_home_policy);
		expect(document.blocks).toEqual(expect.arrayContaining([
			expect.objectContaining({ type: "schedule", days: [1, 2, 3, 4, 5, 6, 7], start: "00:00", end: "23:59" }),
			expect.objectContaining({ type: "screen_time", mode: "block", groups: ["Distractions"] }),
		]));
		expect(is_block_authored_home_allowance(document)).toBe(true);
		const snapshot = page_snapshot(document);
		expect(snapshot.sections.routines.some(block => block.kind === "home_allowance")).toBe(false);
		expect(snapshot.sections.routines).toEqual(expect.arrayContaining([
			expect.objectContaining({ id: "home", kind: "location" }),
			expect.objectContaining({ id: "block-apps", kind: "app_gate" }),
		]));
		expect(snapshot.sections.data).toContainEqual(expect.objectContaining({ id: "usage", kind: "app_usage" }));
		expect(compile_graph(document, graph_from_document(document))).toEqual(document);
	});

	it("does not compile a foreground gate that lacks the location guard", () => {
		const graph = allowance_graph();
		graph.connections = graph.connections.filter(edge => edge.from !== "home");
		expect(derive_home_allowance(graph)).toBeNull();
	});
});
