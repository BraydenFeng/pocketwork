import { behavior_catalog, behavior_config_schema, is_behavior } from "./behaviors";
import { add_connected_block, checked_document, creation_catalog, generated_storage, input_name, insert_page_block, is_page_kind, node_name, page_section, port_name, remove_connected_block, remove_page_block, set_source, visible_outputs, type CreationKind } from "./creation";
import { block_schema, type AppDocument, type Block } from "./document";
import { home_policy_schema } from "./home-policy";
import { compile_graph, graph_from_document, node_catalog, node_ports, type LogicGraph, type LogicNode } from "./logic-graph";

export const home_allowance_block_id = "home-allowance-settings";
export type BlockSource = { block_id: string; output: string };
export type BlockInputs = Record<string, BlockSource | null>;
type SnapshotBlock = {
	id: string;
	kind: string;
	name: string;
	settings: unknown;
	inputs: Record<string, unknown>;
	outputs: { block_id: string; output: string; label: string }[];
};

const setting_names: Partial<Record<CreationKind, string[]>> = {
	note: ["text"], heading: ["subtitle"], checklist: ["items"], counter: ["target"], timer: ["minutes"], schedule: ["days", "start", "end"], screen_time: ["mode", "groups", "limit_minutes"],
	elapsed_timer: ["timer_mode", "value"], variable: ["value", "unit"], change_value: ["variable_id", "change", "value"], time_window: ["time", "end_time", "days"],
	log: ["fields"], form: ["fields"], record: ["fields"], chart: ["field"], aggregate: ["field", "operation"], calculate: ["operation"], text_compare: ["text", "operation"],
	progress: ["value"], health: ["metric"], app_gate: ["groups"], add_allowance: ["minutes"], reminder: ["message"], delay: ["minutes"], clock: ["time", "days"],
	interval: ["value", "interval_unit"],
	number_input: ["value"], text_input: ["text"], count: ["value"], compare: ["operator", "value"], goal: ["value"], app_usage: ["value"],
	branch: ["else_enabled"],
};

function behavior_kind(kind: CreationKind): string { return kind === "log" ? "form" : kind; }

function is_log(graph: LogicGraph, node: LogicNode): boolean {
	return node.kind === "form" && graph.nodes.some(item => generated_storage(graph, item) && graph.connections.some(edge => edge.from === node.id && edge.to === item.id));
}

function block_outputs(graph: LogicGraph, node: LogicNode | undefined) {
	if (!node) { return []; }
	return visible_outputs(graph, node).map(output => ({ block_id: node.id, output, label: port_name(output, node.kind) }));
}

function block_inputs(graph: LogicGraph, node: LogicNode) {
	return Object.fromEntries(node_ports(node).inputs.map(input => {
		const edge = graph.connections.find(item => item.to === node.id && item.input === input);
		return [input, { label: input_name(node.kind, input), source: edge ? { block_id: edge.from, output: edge.output } : null }];
	}));
}

function native_settings(block: Block) {
	const { id: _id, type: _type, title: _title, ...settings } = block;
	return settings;
}

function behavior_settings(node: LogicNode) {
	const { label: _label, ...settings } = node.config!;
	return settings;
}

export function block_catalog() {
	return creation_catalog.map(entry => {
		const kind = behavior_kind(entry.kind);
		const behavior = is_behavior(kind) ? behavior_catalog[kind] : null;
		const native_kind = entry.kind === "screen_time" ? "apps" : entry.kind;
		const native = Object.hasOwn(node_catalog, native_kind) ? node_catalog[native_kind as keyof typeof node_catalog] : null;
		return {
			kind: entry.kind,
			name: entry.title,
			description: entry.detail,
			section: is_page_kind(entry.kind) ? "page" : page_section(entry.kind),
			settings: setting_names[entry.kind] ?? [],
			inputs: behavior ? Object.keys(behavior.inputs).map(input => ({ input, label: input_name(kind as LogicNode["kind"], input), type: behavior.inputs[input] })) : [],
			outputs: behavior ? Object.keys(behavior.outputs).map(output => ({ output, label: port_name(output, entry.kind), type: behavior.outputs[output], optional: entry.kind === "branch" && output === "no" })) : native ? native.outputs.map(output => ({ output, label: port_name(output, entry.kind), type: output === "active" || output === "finished" || output === "outside" ? "boolean" : "unknown", optional: false })) : [],
		};
	});
}

export function page_snapshot(document: AppDocument) {
	const graph = graph_from_document(document);
	const hidden_native = document.home_allowance ? new Set(document.blocks.filter(block => block.type === "schedule" || block.type === "screen_time").map(block => block.id)) : new Set<string>();
	const page: SnapshotBlock[] = document.blocks.filter(block => !hidden_native.has(block.id)).map(block => {
		const node = graph.nodes.find(item => item.id === block.id);
		return { id: block.id, kind: block.type, name: block.title, settings: native_settings(block), inputs: {}, outputs: block_outputs(graph, node) };
	});
	const custom: SnapshotBlock[] = graph.nodes.filter(node => is_behavior(node.kind) && !generated_storage(graph, node)).map(node => ({
		id: node.id,
		kind: is_log(graph, node) ? "log" : node.kind,
		name: node_name(node),
		settings: behavior_settings(node),
		inputs: block_inputs(graph, node),
		outputs: block_outputs(graph, node),
	}));
	const routines = custom.filter(block => page_section(block.kind) === "routines");
	if (document.home_allowance) {
		routines.unshift({
			id: home_allowance_block_id,
			kind: "home_allowance",
			name: "Home screen-time allowance",
			settings: document.home_allowance,
			inputs: {},
			outputs: [
				{ block_id: "home-condition", output: "present", label: "at home" },
				{ block_id: "usage-meter", output: "used", label: "minutes used" },
				{ block_id: "daily-allowance", output: "reached", label: "daily limit reached" },
			],
		});
	}
	return { id: document.id, name: document.name, description: document.description, sections: { page, routines, data: custom.filter(block => page_section(block.kind) === "data") } };
}

function patch_native(document: AppDocument, id: string, name: string | undefined, settings: Record<string, unknown>): AppDocument {
	const block = document.blocks.find(item => item.id === id);
	if (!block) { throw new Error("That block is no longer on this page."); }
	const updated = block_schema.parse({ ...block, ...settings, id: block.id, type: block.type, title: name ?? block.title });
	return checked_document({ ...document, blocks: document.blocks.map(item => item.id === id ? updated : item) });
}

function apply_inputs(graph: LogicGraph, id: string, inputs: BlockInputs): LogicGraph {
	let next = graph;
	for (const [input, source] of Object.entries(inputs)) { next = set_source(next, id, input, source ? `${source.block_id}:${source.output}` : ""); }
	return next;
}

export function add_actual_block(document: AppDocument, kind: CreationKind, options: { name?: string; settings?: Record<string, unknown>; inputs?: BlockInputs; before_block_id?: string } = {}) {
	const settings = options.settings ?? {};
	const inputs = options.inputs ?? {};
	if (is_page_kind(kind)) {
		if (Object.keys(inputs).length) { throw new Error("Page blocks do not take connected inputs."); }
		const existing = new Set(document.blocks.map(block => block.id));
		let next = insert_page_block(document, kind, options.before_block_id);
		const added = next.blocks.find(block => !existing.has(block.id) && block.type === kind);
		if (!added) { throw new Error("The block could not be added."); }
		next = patch_native(next, added.id, options.name, settings);
		return { document: next, block_id: added.id };
	}
	const created = add_connected_block(graph_from_document(document), kind);
	let graph = created.graph;
	const node = graph.nodes.find(item => item.id === created.selected)!;
	node.config = behavior_config_schema.parse({ ...node.config!, ...settings, label: options.name ?? node.config!.label });
	graph = apply_inputs(graph, node.id, inputs);
	return { document: compile_graph(document, graph), block_id: node.id };
}

export function update_actual_block(document: AppDocument, id: string, options: { name?: string; settings?: Record<string, unknown>; inputs?: BlockInputs }) {
	const settings = options.settings ?? {};
	const inputs = options.inputs ?? {};
	if (id === home_allowance_block_id) {
		if (!document.home_allowance) { throw new Error("This page does not have a home allowance block."); }
		if (options.name || Object.keys(inputs).length) { throw new Error("Home allowance has a fixed name and does not take connected inputs."); }
		return checked_document({ ...document, home_allowance: home_policy_schema.parse({ ...document.home_allowance, ...settings, outside_windows: "unrestricted" }) });
	}
	if (document.blocks.some(block => block.id === id)) {
		if (Object.keys(inputs).length) { throw new Error("Page blocks do not take connected inputs."); }
		return patch_native(document, id, options.name, settings);
	}
	let graph = graph_from_document(document);
	const node = graph.nodes.find(item => item.id === id && is_behavior(item.kind));
	if (!node) { throw new Error("That block is no longer on this page."); }
	node.config = behavior_config_schema.parse({ ...node.config!, ...settings, label: options.name ?? node.config!.label });
	if (node.kind === "branch" && settings.else_enabled === false) {
		if (graph.connections.some(edge => edge.from === node.id && edge.output === "no")) { throw new Error("Else is still used by another block. Remove that block before removing Else."); }
		graph = { ...graph, connections: graph.connections.filter(edge => edge.from !== node.id || edge.output !== "no") };
	}
	graph = apply_inputs(graph, id, inputs);
	return compile_graph(document, graph);
}

export function remove_actual_block(document: AppDocument, id: string): AppDocument {
	if (id === home_allowance_block_id) { throw new Error("Home allowance cannot be removed as a single block. Delete the page if you no longer want it."); }
	if (document.blocks.some(block => block.id === id)) { return remove_page_block(document, id); }
	return compile_graph(document, remove_connected_block(graph_from_document(document), id));
}
