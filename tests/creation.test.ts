import { describe, expect, it } from "vitest";
import { add_connected_block, creation_catalog, insert_page_block, numeric_fields, remove_page_block, set_source, source_options, validate_connections } from "../lib/creation";
import { document_schema, starter_document } from "../lib/document";
import { blank_tool } from "../lib/templates";
import { compile_graph, graph_from_document, make_node } from "../lib/logic-graph";
import { behavior_catalog, initial_behaviors, run_behaviors } from "../lib/behaviors";

describe("block descriptions", () => {
	it.each([
		["elapsed_timer", "Stopwatch or countdown"],
		["variable", "Store a number"],
		["time_window", "Active between two times"],
		["app_usage", "Apple Screen Time integration"],
	] as const)("uses the same plain description for %s in the picker and connections", (kind, detail) => {
		expect(creation_catalog.find(item => item.kind === kind)?.detail).toBe(detail);
		expect(behavior_catalog[kind].detail).toBe(detail);
	});
});

describe("document-first creation", () => {
	it("starts with empty editable text, not sample content", () => {
		const document = blank_tool(); expect(document_schema.safeParse(document).success).toBe(true);
		expect(document.blocks).toMatchObject([{ type: "note", title: "Text", text: "" }]);
	});
	it("adds a working blocker and its timer atomically", () => {
		const document = insert_page_block(blank_tool(), "screen_time");
		expect(document.blocks.map(block => block.type)).toEqual(["timer", "screen_time"]);
		expect(document.rules.block_during_focus).toBe(true);
	});
	it("adds a disabled native schedule together with its blocker", () => {
		const document = insert_page_block(blank_tool(), "schedule");
		expect(document.blocks.map(block => block.type)).toEqual(["schedule", "screen_time"]);
		expect(document.enabled).toBe(false); expect(document_schema.safeParse(document).success).toBe(true);
	});
	it("does not replace an existing engine or duplicate a singleton", () => {
		expect(() => insert_page_block(starter_document, "schedule")).toThrow("not both");
		expect(() => insert_page_block(starter_document, "timer")).toThrow("already on your page");
	});
	it("keeps insertion position and does not erase existing nonblank text", () => {
		const document = insert_page_block(starter_document, "note", "focus");
		expect(document.blocks[1].type).toBe("note"); expect(document.blocks[0]).toEqual(starter_document.blocks[0]);
	});
	it("keeps the minimum blank page after removing its last block", () => {
		const document = blank_tool(); const result = remove_page_block(document, document.blocks[0].id);
		expect(result.blocks).toHaveLength(1); expect(document_schema.safeParse(result).success).toBe(true);
	});
	it("protects downstream behavior connections when removing a page block", () => {
		const graph = add_connected_block(graph_from_document(starter_document), "count").graph;
		const node = graph.nodes.find(item => item.kind === "count")!;
		const document = compile_graph(starter_document, set_source(graph, node.id, "increment", "focus:finished"));
		expect(() => remove_page_block(document, "focus")).toThrow("Other blocks use");
	});
	it("counts dependencies toward the native block limit", () => {
		let document = blank_tool();
		for (let i = 0; i < 19; i++) { document = insert_page_block(document, "heading"); }
		expect(() => insert_page_block(document, "screen_time")).toThrow("page is full");
	});
});

describe("named connections", () => {
	it("makes a log with a real submission-to-storage connection", () => {
		const base = blank_tool(); const result = add_connected_block(graph_from_document(base), "log");
		expect(result.graph.nodes.map(node => node.kind)).toEqual(["form", "save_entry"]);
		expect(validate_connections(base, result.graph)).toBeNull();
		const document = compile_graph(base, result.graph); const form = document.behaviors!.nodes.find(node => node.kind === "form")!;
		const run = run_behaviors(document.behaviors!, initial_behaviors(), { now: 1000, submission: { node: form.id, values: { value: 42 } } });
		expect(Object.values(run.state.data!.entries)[0][0].values.value).toBe(42);
	});
	it("connects a chart to the only compatible log and renders real entries", () => {
		const base = blank_tool(); const log = add_connected_block(graph_from_document(base), "log");
		const result = add_connected_block(log.graph, "chart"); const document = compile_graph(base, result.graph);
		const form = document.behaviors!.nodes.find(node => node.kind === "form")!;
		const run = run_behaviors(document.behaviors!, initial_behaviors(), { now: 1000, submission: { node: form.id, values: { value: 12 } } });
		expect(run.signals[result.selected].rows.value).toMatchObject([{ values: { value: 12 } }]);
		expect(numeric_fields(result.graph, result.graph.nodes.find(node => node.id === result.selected)!)).toEqual([{ id: "value", label: "Value" }]);
	});
	it("does not guess which of several compatible sources to use", () => {
		const base = blank_tool(); const first = add_connected_block(graph_from_document(base), "log"); const second = add_connected_block(first.graph, "log");
		const chart = add_connected_block(second.graph, "chart");
		expect(chart.graph.connections.filter(edge => edge.to === chart.selected)).toHaveLength(0);
		expect(validate_connections(base, chart.graph)).toContain("Connect");
	});
	it("offers only compatible inputs and excludes loops", () => {
		const base = blank_tool(); const log = add_connected_block(graph_from_document(base), "log"); const chart = add_connected_block(log.graph, "chart");
		expect(source_options(chart.graph, chart.selected, "rows")).toHaveLength(1);
		expect(() => set_source(chart.graph, chart.selected, "rows", `${log.selected}:submitted`)).toThrow("incompatible");
		const extra = make_node("table"); const graph = { ...chart.graph, nodes: [...chart.graph.nodes, extra] };
		const linked = set_source(graph, extra.id, "rows", `${chart.selected}:rows`);
		expect(source_options(linked, chart.selected, "rows").some(option => option.node === extra.id)).toBe(false);
	});
	it("validates the numeric chart field, rather than silently displaying nothing", () => {
		const base = blank_tool(); const log = add_connected_block(graph_from_document(base), "log"); const chart = add_connected_block(log.graph, "chart");
		chart.graph.nodes.find(node => node.id === log.selected)!.config!.fields = [{ id: "minutes", label: "Gym minutes", type: "number", required: true }];
		expect(validate_connections(base, chart.graph)).toContain("numeric field");
		chart.graph.nodes.find(node => node.id === chart.selected)!.config!.field = "minutes";
		expect(validate_connections(base, chart.graph)).toBeNull();
	});
	it("preserves existing native rules and MCP-compatible serialized format", () => {
		const graph = add_connected_block(graph_from_document(starter_document), "button").graph;
		const compiled = compile_graph(starter_document, graph);
		expect(compiled.rules).toEqual(starter_document.rules); expect(compiled.blocks).toEqual(starter_document.blocks);
		expect(document_schema.parse(JSON.parse(JSON.stringify(compiled)))).toEqual(compiled);
	});
});
