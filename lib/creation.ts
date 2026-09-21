import { behavior_catalog, behavior_config_schema, is_behavior, type BehaviorKind } from "./behaviors";
import { create_block, document_schema, new_id, remove_block, type AppDocument, type BlockType } from "./document";
import { compile_graph, connect, graph_from_document, make_node, node_catalog, node_ports, type LogicGraph, type LogicNode, type NodeKind } from "./logic-graph";
import { optional_input } from "./primitives";

export const page_kinds = new Set<BehaviorKind>(["button", "check_in", "number_input", "text_input", "checkbox", "form", "table", "chart", "progress", "count", "goal", "streak", "elapsed_timer", "variable", "app_usage", "calculate", "aggregate"]);
export type CreationKind = BlockType | BehaviorKind | "log";
export type PageSection = "routines" | "data";
const data_kinds = new Set<string>(["variable", "record", "form", "log", "save_entry", "table", "chart", "progress", "health", "app_usage", "number_input", "text_input", "count", "streak", "goal", "aggregate", "calculate", "counter"]);
export function page_section(kind: string): PageSection { return data_kinds.has(kind) ? "data" : "routines"; }
export const creation_catalog: { kind: CreationKind; title: string; detail: string; section: string }[] = [
	{ kind: "elapsed_timer", title: "Timer", detail: "Stopwatch or countdown", section: "Building blocks" },
	{ kind: "variable", title: "Variable", detail: "Store a number", section: "Building blocks" },
	{ kind: "change_value", title: "Change variable", detail: "Set, add, subtract, or reset a number", section: "Building blocks" },
	{ kind: "time_window", title: "Time window", detail: "Active between two times", section: "Building blocks" },
	{ kind: "note", title: "Text", detail: "Plain text", section: "On the page" },
	{ kind: "heading", title: "Heading", detail: "Section title", section: "On the page" },
	{ kind: "checklist", title: "Checklist", detail: "Check off tasks", section: "On the page" },
	{ kind: "counter", title: "Counter", detail: "Tap to count toward a goal", section: "On the page" },
	{ kind: "log", title: "Log", detail: "Fill out and save an entry", section: "Data & displays" },
	{ kind: "chart", title: "Chart", detail: "View entries on a graph", section: "Data & displays" },
	{ kind: "table", title: "Table", detail: "View entries in rows and columns", section: "Data & displays" },
	{ kind: "progress", title: "Progress", detail: "Show progress toward a target", section: "Data & displays" },
	{ kind: "health", title: "Apple Health", detail: "Steps, calories, and other health data", section: "Data & displays" },
	{ kind: "app_usage", title: "App usage", detail: "Apple Screen Time integration", section: "Data & displays" },
	{ kind: "record", title: "Record", detail: "Group values into one entry", section: "Data & displays" },
	{ kind: "save_entry", title: "Save entry", detail: "Add an entry to a log", section: "Data & displays" },
	{ kind: "button", title: "Button", detail: "Run an action when tapped", section: "Controls & events" },
	{ kind: "checkbox", title: "Switch", detail: "Turn on or off", section: "Controls & events" },
	{ kind: "number_input", title: "Number", detail: "Enter a number", section: "Controls & events" },
	{ kind: "text_input", title: "Text input", detail: "Enter text", section: "Controls & events" },
	{ kind: "check_in", title: "Check-in", detail: "Tap to check in", section: "Controls & events" },
	{ kind: "arrive", title: "Arrive at location", detail: "When you reach a saved place", section: "Controls & events" },
	{ kind: "leave", title: "Leave location", detail: "When you leave a saved place", section: "Controls & events" },
	{ kind: "clock", title: "At a time", detail: "At a set time", section: "Controls & events" },
	{ kind: "app_gate", title: "Control app access", detail: "Block selected apps", section: "Actions & logic" },
	{ kind: "reminder", title: "Show a message", detail: "Display a message", section: "Actions & logic" },
	{ kind: "count", title: "Count events", detail: "Count how many times something happens", section: "Actions & logic" },
	{ kind: "streak", title: "Streak", detail: "Count consecutive check-in days", section: "Actions & logic" },
	{ kind: "goal", title: "Goal reached", detail: "When a number reaches your target", section: "Actions & logic" },
	{ kind: "compare", title: "Compare a number", detail: "Greater than, less than, or equal to", section: "Actions & logic" },
	{ kind: "and", title: "Both conditions", detail: "True when both conditions are true", section: "Actions & logic" },
	{ kind: "or", title: "Either condition", detail: "True when at least one condition is true", section: "Actions & logic" },
	{ kind: "not", title: "Reverse condition", detail: "Flip true and false", section: "Actions & logic" },
	{ kind: "aggregate", title: "Summarize entries", detail: "Sum, average, or count entries", section: "Actions & logic" },
	{ kind: "calculate", title: "Calculate", detail: "Add, subtract, multiply, or divide", section: "Actions & logic" },
	{ kind: "timer", title: "Focus timer", detail: "Timed focus session", section: "Native presets" },
	{ kind: "schedule", title: "Schedule", detail: "Block apps on a weekly schedule", section: "Native presets" },
	{ kind: "screen_time", title: "App blocker", detail: "Block apps or set a daily limit", section: "Native presets" },
];

export function is_page_kind(kind: CreationKind): kind is BlockType {
	return ["note", "heading", "timer", "schedule", "screen_time", "checklist", "counter"].includes(kind);
}

export function checked_document(document: AppDocument): AppDocument {
	const parsed = document_schema.safeParse(document);
	if (!parsed.success) { throw new Error(parsed.error.issues[0].message); }
	return parsed.data;
}

export function insert_page_block(document: AppDocument, kind: BlockType, before?: string): AppDocument {
	if (["timer", "schedule", "screen_time"].includes(kind) && document.blocks.some(block => block.type === kind)) { throw new Error("That block is already on your page. Edit it in place."); }
	if ((kind === "timer" && document.blocks.some(block => block.type === "schedule")) || (kind === "schedule" && document.blocks.some(block => block.type === "timer"))) { throw new Error("Use a focus timer or a repeating schedule, not both. Remove the existing one to switch."); }
	const block = create_block(kind);
	if (block.type === "note") { block.title = "Text"; block.text = ""; }
	if (block.type === "heading") { block.title = "Heading"; block.subtitle = ""; }
	const placeholder = document.blocks.length === 1 && document.blocks[0].type === "note" && !document.blocks[0].text && document.blocks[0].title === "Text";
	const blocks = placeholder ? [] : [...document.blocks];
	const at = before ? blocks.findIndex(item => item.id === before) : -1;
	blocks.splice(at < 0 ? blocks.length : at, 0, block);
	const next = { ...document, blocks, rules: { ...document.rules } };
	if (kind === "screen_time" && !blocks.some(item => item.type === "timer" || item.type === "schedule")) { blocks.unshift(create_block("timer")); }
	if (kind === "schedule" && !blocks.some(item => item.type === "screen_time")) { blocks.push(create_block("screen_time")); }
	if (kind === "screen_time" || kind === "schedule") { next.rules.block_during_focus = true; }
	if (kind === "schedule") { next.enabled = false; }
	if (blocks.length > 20) { throw new Error("This page is full. Remove a block before adding another."); }
	return checked_document(next);
}

export function remove_page_block(document: AppDocument, id: string): AppDocument {
	const next = document.blocks.length === 1
		? { ...document, blocks: [{ id: new_id(), type: "note" as const, title: "Text", text: "" }], rules: { block_during_focus: false, notify_on_complete: false }, enabled: undefined }
		: remove_block(document, id);
	if (next.blocks.some(block => block.type === "schedule") && !next.blocks.some(block => block.type === "screen_time")) { throw new Error("This schedule needs an app blocker. Remove the schedule first."); }
	if (document.behaviors?.connections.some(edge => edge.from === id)) { throw new Error("Other blocks use this block. Disconnect them in Connections before removing it."); }
	return checked_document(next);
}

export function node_name(node: LogicNode): string { return node.config?.label || node.block?.title || node_catalog[node.kind].title; }
const readable_ports: Record<string, string> = { pressed: "when tapped", submitted: "when submitted", record: "entry fields", rows: "saved entries", saved: "when saved", active: "while active", finished: "when finished", present: "at the saved place", away: "away from the saved place", arrived: "on arrival", left: "on departure", due: "at the chosen time", checked: "switched on", changed: "when changed", done: "when checked in", value: "value", count: "entry count", result: "result", days: "streak days", reached: "goal reached", minutes: "minutes used", granted: "reward granted", outside: "outside the window" };
export function port_name(port: string): string { return readable_ports[port] ?? port.replaceAll("_", " "); }
export function input_name(kind: NodeKind, input: string): string {
	if (input === "when") { return "When"; }
	if (input === "amount") { return "Amount from (optional)"; }
	if (input === "threshold" || input === "target") { return "Target from (optional)"; }
	if (input === "duration") { return "Duration from (minutes, optional)"; }
	if (kind === "elapsed_timer") { return `${input === "start" ? "Start" : input === "pause" ? "Pause" : input === "stop" ? "Stop" : "Reset"} when (optional)`; }
	if (input === "rows") { return "Show data from"; }
	if (input === "value") { return "Use value from"; }
	if (input === "record") { return "Entry fields from"; }
	if (input === "closed") { return "Block apps when"; }
	if (input === "grant") { return "Award minutes when"; }
	if (input === "send") { return "Show message when"; }
	if (input === "save") { return "Save an entry when"; }
	if (input === "increment") { return "Count when"; }
	if (input === "check_in") { return "Check in when"; }
	if (input === "clear" || input === "reset") { return "Reset when (optional)"; }
	if (input === "a" || input === "b") { return `${kind === "calculate" ? "Number" : "Condition"} ${input === "a" ? "1" : "2"}`; }
	return input === "condition" ? "When" : port_name(input);
}

export function source_options(graph: LogicGraph, target: string, input: string) {
	const base = { ...graph, connections: graph.connections.filter(edge => !(edge.to === target && edge.input === input)) };
	return graph.nodes.filter(node => node.id !== target).flatMap(node => node_ports(node).outputs.flatMap(output => {
		try { connect(base, { from: node.id, output, to: target, input }); return [{ id: `${node.id}:${output}`, node: node.id, output, label: `${node_name(node)} · ${node.config?.fields?.find(field => field.id === output)?.label ?? port_name(output)}` }]; }
		catch { return []; }
	}));
}

export function set_source(graph: LogicGraph, target: string, input: string, value: string): LogicGraph {
	const base = { ...graph, connections: graph.connections.filter(edge => !(edge.to === target && edge.input === input)) };
	if (!value) { return base; }
	const source = source_options(graph, target, input).find(option => option.id === value);
	if (!source) { throw new Error("That source is incompatible or would create a loop."); }
	return connect(base, { from: source.node, output: source.output, to: target, input });
}

export function add_connected_block(graph: LogicGraph, kind: BehaviorKind | "log"): { graph: LogicGraph; selected: string } {
	const node = make_node(kind === "log" ? "form" : kind, 40, graph.nodes.length * 240);
	if (kind !== "log") { node.config!.label = creation_catalog.find(item => item.kind === kind)?.title ?? node.config!.label; }
	if (kind === "log") { node.config = behavior_config_schema.parse({ label: "My log", fields: [{ id: "value", label: "Value", type: "number", required: true }] }); }
	if (graph.nodes.filter(item => is_behavior(item.kind)).length + (kind === "log" ? 2 : 1) > 48) { throw new Error("Use at most 48 connected blocks in one routine."); }
	let next: LogicGraph = { ...graph, nodes: [...graph.nodes, node] };
	if (kind === "change_value") { const variables = graph.nodes.filter(item => item.kind === "variable"); if (variables.length === 1) { node.config!.variable_id = variables[0].id; } }
	if (kind === "log") {
		const storage = make_node("save_entry", 360, graph.nodes.length * 240);
		storage.config!.label = "Saved entries";
		next = { ...next, nodes: [...next.nodes, storage] };
		next = connect(next, { from: node.id, output: "record", to: storage.id, input: "record" });
		next = connect(next, { from: node.id, output: "submitted", to: storage.id, input: "save" });
	}
	for (const input of node_ports(node).inputs) {
		if (optional_input({ kind: node.kind as BehaviorKind, config: node.config! }, input)) { continue; }
		const options = source_options(next, node.id, input);
		if (options.length === 1) { next = set_source(next, node.id, input, options[0].id); }
	}
	return { graph: next, selected: node.id };
}

export function connected_summary(graph: LogicGraph, node: LogicNode): string {
	const sources = graph.connections.filter(edge => edge.to === node.id).map(edge => graph.nodes.find(item => item.id === edge.from)).filter((item): item is LogicNode => Boolean(item));
	return sources.length ? `From ${[...new Set(sources.map(node_name))].join(", ")}` : is_behavior(node.kind) ? behavior_catalog[node.kind].detail : node_catalog[node.kind].detail;
}

export function numeric_fields(graph: LogicGraph, node: LogicNode): { id: string; label: string }[] {
	const seen = new Set<string>();
	function visit(id: string): LogicNode | undefined {
		if (seen.has(id)) { return; } seen.add(id);
		const item = graph.nodes.find(entry => entry.id === id);
		if (item?.kind === "form" || item?.kind === "record") { return item; }
		for (const edge of graph.connections.filter(entry => entry.to === id && ["rows", "record"].includes(entry.input))) { const form = visit(edge.from); if (form) { return form; } }
	}
	const form = visit(node.id);
	return (form?.config?.fields ?? [{ id: "value", label: "Value", type: "number" }]).filter(field => field.type === "number").map(({ id, label }) => ({ id, label }));
}

export function validate_connections(base: AppDocument, graph: LogicGraph): string | null {
	try {
		for (const node of graph.nodes.filter(item => is_behavior(item.kind))) {
			for (const input of node_ports(node).inputs) {
				if (optional_input({ kind: node.kind as BehaviorKind, config: node.config! }, input)) { continue; }
				if (!graph.connections.some(edge => edge.to === node.id && edge.input === input)) { return `Connect ${node_name(node)}: ${input_name(node.kind, input).toLowerCase()}.`; }
			}
		}
		compile_graph(base, graph);
		for (const node of graph.nodes.filter(item => item.kind === "chart" || item.kind === "aggregate" && item.config?.operation !== "count")) {
			if (!numeric_fields(graph, node).some(field => field.id === (node.config?.field ?? "value"))) { return `Choose an existing numeric field for ${node_name(node)}.`; }
		}
		return null;
	}
	catch (failure) { return failure instanceof Error ? failure.message : "Check the connections before saving."; }
}
