import { z } from "zod";
import { behavior_ports, behavior_catalog, behavior_config_schema, behavior_kinds, behavior_order, behaviors_schema, is_behavior, type BehaviorConfig, type BehaviorKind, type Behaviors } from "./behaviors";
import { home_policy_schema } from "./home-policy";
import { block_schema, create_block, document_schema, type AppDocument, type Block } from "./document";
import type { HomePolicy } from "./home-policy";

export type NodeKind = BehaviorKind | "timer" | "schedule" | "apps" | "notification" | "home" | "usage" | "allowance";
export type LogicNode = { id: string; kind: NodeKind; x: number; y: number; block?: Block; policy?: HomePolicy; config?: BehaviorConfig };
export type Connection = { from: string; output: string; to: string; input: string };
export type LogicGraph = { nodes: LogicNode[]; connections: Connection[] };
export const NODE_WIDTH = 232;
export const PORT_TOP = 100;
export const PORT_GAP = 28;
export const node_catalog: Record<NodeKind, { title: string; detail: string; inputs: string[]; outputs: string[] }> = {
	...Object.fromEntries(Object.entries(behavior_catalog).map(([kind, entry]) => [kind, { ...entry, inputs: Object.keys(entry.inputs), outputs: Object.keys(entry.outputs) }])) as unknown as Record<BehaviorKind, { title: string; detail: string; inputs: string[]; outputs: string[] }>,
	timer: { title: "Timer", detail: "Starts when you press Start", inputs: [], outputs: ["active", "finished"] },
	schedule: { title: "Time window", detail: "Days and hours that repeat", inputs: [], outputs: ["active", "outside"] },
	home: { title: "At location", detail: "Your iPhone's saved location", inputs: [], outputs: ["present"] },
	usage: { title: "Count usage", detail: "Only while both conditions hold", inputs: ["home", "window"], outputs: ["used"] },
	allowance: { title: "Daily allowance", detail: "One budget across your windows", inputs: ["used"], outputs: ["reached"] },
	apps: { title: "Control apps", detail: "Apply a rule to an app group", inputs: ["gate", "home", "outside"], outputs: [] },
	notification: { title: "Notify me", detail: "When a timer finishes", inputs: ["finished"], outputs: [] },
};
export const graph_schema = z.object({
	nodes: z.array(z.object({ id: z.string().regex(/^[a-zA-Z0-9_-]{1,64}$/), kind: z.enum(["timer", "schedule", "apps", "notification", "home", "usage", "allowance", ...behavior_kinds]), x: z.number().finite(), y: z.number().finite(), block: block_schema.optional(), policy: home_policy_schema.optional(), config: behavior_config_schema.optional() }).strict()).max(55),
	connections: z.array(z.object({ from: z.string(), output: z.string(), to: z.string(), input: z.string() }).strict()).max(144),
}).strict();
const supported = new Set([
	"timer.active>apps.gate", "timer.finished>notification.finished", "schedule.active>apps.gate",
	"home.present>usage.home", "schedule.active>usage.window", "usage.used>allowance.used",
	"allowance.reached>apps.gate", "home.present>apps.home", "schedule.outside>apps.outside",
]);
export function connection_key(edge: Connection): string { return `${edge.from}.${edge.output}>${edge.to}.${edge.input}`; }
export function node_ports(node: LogicNode) { if (is_behavior(node.kind)) { const ports = behavior_ports({ kind: node.kind, config: node.config ?? behavior_config_schema.parse({}) }); return { inputs: Object.keys(ports.inputs), outputs: Object.keys(ports.outputs) }; } return node_catalog[node.kind]; }
export function node_height(node: LogicNode): number { const ports = node_ports(node); return PORT_TOP + Math.max(ports.inputs.length, ports.outputs.length) * PORT_GAP + 16; }
export function make_node(kind: NodeKind, x = 48, y = 48): LogicNode {
	if (is_behavior(kind)) { return { id: crypto.randomUUID(), kind, x, y, config: behavior_config_schema.parse({ label: behavior_catalog[kind].title }) }; }
	const block = kind === "timer" || kind === "schedule" ? create_block(kind) : kind === "apps" ? create_block("screen_time") : undefined;
	const policy: HomePolicy | undefined = kind === "allowance" ? { timezone: "America/Los_Angeles", away_usage_counts: false, outside_windows: "unrestricted", rules: [{ days: [1, 2, 3, 4, 5, 6, 7], allowance_minutes: 30, windows: [{ start: "06:30", end: "20:30" }] }] } : undefined;
	return { id: block?.id ?? crypto.randomUUID(), kind, x, y, ...(block ? { block } : {}), ...(policy ? { policy } : {}) };
}
export function connect(graph: LogicGraph, edge: Connection): LogicGraph {
	const from = graph.nodes.find((node) => node.id === edge.from);
	const to = graph.nodes.find((node) => node.id === edge.to);
	if (!from || !to) { throw new Error("Both ends of the connection need a node."); }
	if (is_behavior(to.kind)) {
		const output = is_behavior(from.kind) ? behavior_ports({ kind: from.kind, config: from.config ?? behavior_config_schema.parse({}) }).outputs[edge.output] : legacy_ports(from)[edge.output];
		if (!output || output !== behavior_ports({ kind: to.kind, config: to.config ?? behavior_config_schema.parse({}) }).inputs[edge.input]) { throw new Error("These ports do not match. Connect the same value type."); }
	} else if (!supported.has(`${from.kind}.${edge.output}>${to.kind}.${edge.input}`)) { throw new Error("These ports do not match. Choose a compatible input."); }
	if (graph.connections.some((item) => item.to === edge.to && item.input === edge.input)) { throw new Error("This input is already connected. Remove its connection first."); }
	const result = { ...graph, connections: [...graph.connections, edge] };
	behavior_order(behavior_part(result), external_ports(result));
	return result;
}
export function graph_from_document(document: AppDocument): LogicGraph {
	const nodes: LogicNode[] = document.blocks.flatMap((block) => {
		const kind: NodeKind | null = block.type === "screen_time" ? "apps" : block.type === "timer" || block.type === "schedule" ? block.type : null;
		return kind ? [{ id: block.id, kind, block: structuredClone(block), x: kind === "apps" ? 940 : 40, y: kind === "apps" ? 180 : 320 }] : [];
	});
	let graph: LogicGraph = { nodes, connections: [] };
	const add_edge = (from: NodeKind, output: string, to: NodeKind, input: string) => {
		const a = nodes.find((node) => node.kind === from); const b = nodes.find((node) => node.kind === to);
		if (a && b) { graph = connect(graph, { from: a.id, output, to: b.id, input }); }
	};
	if (document.home_allowance) {
		nodes.push({ id: "home-condition", kind: "home", x: 40, y: 40 }, { id: "usage-meter", kind: "usage", x: 340, y: 180 }, { id: "daily-allowance", kind: "allowance", x: 640, y: 180, policy: structuredClone(document.home_allowance) });
		add_edge("home", "present", "usage", "home"); add_edge("schedule", "active", "usage", "window"); add_edge("usage", "used", "allowance", "used"); add_edge("allowance", "reached", "apps", "gate"); add_edge("home", "present", "apps", "home");
		if (document.home_allowance.outside_windows === "block_at_home") { add_edge("schedule", "outside", "apps", "outside"); }
	} else if (document.rules.block_during_focus) { add_edge(nodes.some((node) => node.kind === "timer") ? "timer" : "schedule", "active", "apps", "gate"); }
	if (document.rules.notify_on_complete) { nodes.push({ id: "completion-notification", kind: "notification", x: 640, y: 40 }); add_edge("timer", "finished", "notification", "finished"); }
	if (document.behaviors) { graph.nodes.push(...structuredClone(document.behaviors.nodes)); graph.connections.push(...structuredClone(document.behaviors.connections)); }
	return graph;
}
export function compile_graph(base: AppDocument, graph: LogicGraph): AppDocument {
	if (graph.nodes.length > 55 || new Set(graph.nodes.map((node) => node.id)).size !== graph.nodes.length) { throw new Error("Use unique node IDs and at most 55 logic nodes."); }
	const by_kind = (kind: NodeKind) => graph.nodes.find((node) => node.kind === kind);
	for (const kind of Object.keys(node_catalog) as NodeKind[]) { if (!is_behavior(kind) && graph.nodes.filter((node) => node.kind === kind).length > 1) { throw new Error(`This iPhone runtime supports one ${node_catalog[kind].title.toLowerCase()} per routine.`); } }
	let checked: LogicGraph = { nodes: graph.nodes, connections: [] };
	for (const edge of graph.connections) { checked = connect(checked, edge); }
	const linked = (from: NodeKind, output: string, to: NodeKind, input: string) => graph.connections.some((edge) => edge.from === by_kind(from)?.id && edge.output === output && edge.to === by_kind(to)?.id && edge.input === input);
	const home = Boolean(by_kind("home") || by_kind("usage") || by_kind("allowance"));
	const result = structuredClone(base);
	const blocks: Block[] = [];
	for (const node of graph.nodes) {
		const kind = node.kind === "apps" ? "screen_time" : node.kind;
		if (kind === "timer" || kind === "schedule" || kind === "screen_time") {
			if (!node.block || node.block.type !== kind || node.block.id !== node.id) { throw new Error("A logic node must contain its matching page block."); }
			blocks.push(structuredClone(node.block));
		}
	}
	result.blocks = base.blocks.flatMap((block) => {
		if (!["timer", "schedule", "screen_time"].includes(block.type)) { return [block]; }
		return blocks.filter((replacement) => replacement.id === block.id);
	});
	for (const block of blocks) { if (!result.blocks.some((item) => item.id === block.id)) { result.blocks.push(block); } }
	result.rules = { block_during_focus: linked("timer", "active", "apps", "gate") || linked("schedule", "active", "apps", "gate"), notify_on_complete: linked("timer", "finished", "notification", "finished") };
	if (by_kind("notification") && !result.rules.notify_on_complete) { throw new Error("Connect the timer's finished output to Notify me."); }
	if (home) {
		const required: [NodeKind, string, NodeKind, string][] = [["home", "present", "usage", "home"], ["schedule", "active", "usage", "window"], ["usage", "used", "allowance", "used"], ["allowance", "reached", "apps", "gate"], ["home", "present", "apps", "home"]];
		if (by_kind("timer") || !required.every((edge) => linked(...edge))) { throw new Error("Home allowances need Home + Time window → Count usage → Daily allowance → Control apps, plus a Home connection to Control apps."); }
		const policy = by_kind("allowance")?.policy;
		if (!policy) { throw new Error("Set the daily allowances and windows."); }
		result.home_allowance = structuredClone(policy);
		// The optional Outside wire is the only way to get the older "block outside the windows" behavior.
		result.home_allowance.outside_windows = linked("schedule", "outside", "apps", "outside") ? "block_at_home" : "unrestricted"; result.schema_version = 2; result.rules.block_during_focus = true;
		const schedule = result.blocks.find((block) => block.type === "schedule")!;
		if (schedule.type === "schedule") { schedule.days = [1, 2, 3, 4, 5, 6, 7]; schedule.start = "00:00"; schedule.end = "23:59"; }
	} else { delete result.home_allowance; result.schema_version = 1; }
	if (by_kind("schedule")) { result.enabled = base.blocks.some((block) => block.id === by_kind("schedule")?.id) ? base.enabled ?? false : false; } else { delete result.enabled; }
	const behaviors = behavior_part(graph);
	if (behaviors.nodes.length) { behavior_order(behaviors, external_ports(graph), true); result.behaviors = behaviors_schema.parse(behaviors); result.schema_version = 3; } else { delete result.behaviors; }
	const parsed = document_schema.safeParse(result);
	if (!parsed.success) { throw new Error(parsed.error.issues[0].message); }
	return parsed.data;
}

export function legacy_ports(node: LogicNode): Record<string, "boolean" | "number"> {
	return Object.fromEntries(node_catalog[node.kind].outputs.map(port => [port, node.kind === "usage" && port === "used" ? "number" : "boolean"]));
}
export function external_ports(graph: LogicGraph) { return Object.fromEntries(graph.nodes.filter(n => !is_behavior(n.kind)).map(n => [n.id, legacy_ports(n)])); }
export function behavior_part(graph: LogicGraph): Behaviors {
	return { nodes: graph.nodes.filter(n => is_behavior(n.kind)).map(n => ({ id: n.id, kind: n.kind as BehaviorKind, x: n.x, y: n.y, config: n.config ?? behavior_config_schema.parse({}) })), connections: graph.connections.filter(e => graph.nodes.some(n => n.id === e.to && is_behavior(n.kind))) };
}
