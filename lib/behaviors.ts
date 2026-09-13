import { z } from "zod";

export const behavior_kinds = ["location", "button", "check_in", "arrive", "leave", "clock", "app_usage", "and", "or", "not", "branch", "delay", "variable", "count", "compare", "goal", "streak", "reminder"] as const;
export type BehaviorKind = typeof behavior_kinds[number];
export const behavior_config_schema = z.object({
	label: z.string().max(80).default(""), value: z.number().finite().min(-1000000).max(1000000).default(1),
	minutes: z.number().min(1).max(1440).default(5), time: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).default("18:00"),
	days: z.array(z.number().int().min(1).max(7)).min(1).max(7).default([1,2,3,4,5,6,7]),
	message: z.string().max(240).default("Time for your routine."), operator: z.enum(["gte", "gt", "eq", "lt", "lte"]).default("gte"),
}).strict();
export type BehaviorConfig = z.infer<typeof behavior_config_schema>;
export const behavior_node_schema = z.object({ id: z.string().regex(/^[a-zA-Z0-9_-]{1,64}$/), kind: z.enum(behavior_kinds), x: z.number().finite(), y: z.number().finite(), config: behavior_config_schema }).strict();
export const edge_schema = z.object({ from: z.string(), output: z.string(), to: z.string(), input: z.string() }).strict();
export const behaviors_schema = z.object({ nodes: z.array(behavior_node_schema).max(48), connections: z.array(edge_schema).max(128) }).strict();
export type Behaviors = z.infer<typeof behaviors_schema>;
export type BehaviorNode = Behaviors["nodes"][number];
type PortType = "boolean" | "number";
export const behavior_catalog: Record<BehaviorKind, { title: string; detail: string; category: string; inputs: Record<string, PortType>; outputs: Record<string, PortType> }> = {
	location: { title: "At location", detail: "Inside the saved place on your phone", category: "Triggers", inputs: {}, outputs: { present: "boolean", away: "boolean" } },
	button: { title: "Button", detail: "Run a connection with one tap", category: "Triggers", inputs: {}, outputs: { pressed: "boolean" } },
	check_in: { title: "Check-in", detail: "Record showing up", category: "Accountability", inputs: {}, outputs: { done: "boolean" } },
	arrive: { title: "Arrive at location", detail: "When you enter the saved place", category: "Triggers", inputs: {}, outputs: { arrived: "boolean" } },
	leave: { title: "Leave location", detail: "When you exit the saved place", category: "Triggers", inputs: {}, outputs: { left: "boolean" } },
	clock: { title: "At a time", detail: "A chosen time and days", category: "Triggers", inputs: {}, outputs: { due: "boolean" } },
	app_usage: { title: "App usage", detail: "Minutes from the phone's allowance meter", category: "Triggers", inputs: {}, outputs: { minutes: "number", reached: "boolean" } },
	and: { title: "AND", detail: "Both conditions are true", category: "Logic", inputs: { a: "boolean", b: "boolean" }, outputs: { result: "boolean" } },
	or: { title: "OR", detail: "Either condition is true", category: "Logic", inputs: { a: "boolean", b: "boolean" }, outputs: { result: "boolean" } },
	not: { title: "NOT", detail: "Reverse a condition", category: "Logic", inputs: { condition: "boolean" }, outputs: { result: "boolean" } },
	branch: { title: "If / else", detail: "Take the matching branch", category: "Logic", inputs: { condition: "boolean" }, outputs: { yes: "boolean", no: "boolean" } },
	delay: { title: "Delay", detail: "Wait before the next action", category: "Logic", inputs: { start: "boolean" }, outputs: { done: "boolean" } },
	variable: { title: "Variable", detail: "Store a number for later", category: "Logic", inputs: { set: "number" }, outputs: { value: "number" } },
	count: { title: "Counter", detail: "Count events; optionally reset", category: "Accountability", inputs: { increment: "boolean", reset: "boolean" }, outputs: { value: "number" } },
	compare: { title: "Compare", detail: "Compare a number to a value", category: "Logic", inputs: { value: "number" }, outputs: { result: "boolean" } },
	goal: { title: "Goal", detail: "Reach a target number", category: "Accountability", inputs: { value: "number" }, outputs: { reached: "boolean" } },
	streak: { title: "Streak", detail: "Consecutive days checked in", category: "Accountability", inputs: { check_in: "boolean" }, outputs: { days: "number" } },
	reminder: { title: "Reminder", detail: "Show a message when triggered", category: "Actions", inputs: { send: "boolean" }, outputs: { sent: "boolean" } },
};
export function is_behavior(kind: string): kind is BehaviorKind { return Object.hasOwn(behavior_catalog, kind); }
export function behavior_order(graph: Behaviors, external: Record<string, Record<string, PortType>>, require_inputs = false): BehaviorNode[] {
	const ids = new Set(graph.nodes.map(n => n.id));
	if (ids.size !== graph.nodes.length || graph.nodes.some(n => Object.hasOwn(external, n.id))) { throw new Error("Every node needs a unique ID."); }
	const occupied = new Set<string>();
	for (const edge of graph.connections) {
		const from = graph.nodes.find(n => n.id === edge.from); const to = graph.nodes.find(n => n.id === edge.to);
		const output = from ? behavior_catalog[from.kind].outputs[edge.output] : external[edge.from]?.[edge.output];
		if (!to || !output || output !== behavior_catalog[to.kind].inputs[edge.input]) { throw new Error("These ports do not match. Connect the same value type."); }
		const input = `${edge.to}.${edge.input}`;
		if (occupied.has(input)) { throw new Error("This input is already connected."); } occupied.add(input);
	}
	if (require_inputs) {
		for (const node of graph.nodes) { for (const port of Object.keys(behavior_catalog[node.kind].inputs)) {
			if ((node.kind === "variable" && port === "set") || (node.kind === "count" && port === "reset")) { continue; }
			if (!occupied.has(`${node.id}.${port}`)) { throw new Error(`Connect ${behavior_catalog[node.kind].title}'s ${port} input first.`); }
		} }
	}
	const ordered: BehaviorNode[] = []; const remaining = [...graph.nodes];
	while (remaining.length) {
		const index = remaining.findIndex(n => !graph.connections.some(e => e.to === n.id && remaining.some(p => p.id === e.from)));
		if (index < 0) { throw new Error("Connections cannot loop back. Use stored counters or variables instead."); }
		ordered.push(remaining.splice(index, 1)[0]);
	}
	return ordered;
}
export type Signal = { value: number | boolean; token: string; available?: boolean };
export type BehaviorState = { values: Record<string, number>; fired: Record<string, string>; days: Record<string, string>; pending: { id: string; at: number; token: string }[]; sequence: number; at_location?: boolean };
export type BehaviorContext = { now: number; at_location?: boolean; usage_minutes?: number; tap?: string; external?: Record<string, Record<string, Signal>> };
export function initial_behaviors(): BehaviorState { return { values: {}, fired: {}, days: {}, pending: [], sequence: 0 }; }
export function run_behaviors(graph: Behaviors, previous: BehaviorState, context: BehaviorContext) {
	const state = structuredClone(previous); state.sequence += 1;
	const signals: Record<string, Record<string, Signal>> = { ...context.external };
	const effects: { id: string; message: string }[] = [];
	const external_types = Object.fromEntries(Object.entries(context.external ?? {}).map(([id, ports]) => [id, Object.fromEntries(Object.entries(ports).map(([name, signal]) => [name, typeof signal.value as PortType]))]));
	const ordered = behavior_order(graph, external_types, true);
	const date = new Date(context.now); const day = `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,"0")}-${String(date.getDate()).padStart(2,"0")}`;
	const yesterday_date = new Date(date); yesterday_date.setDate(date.getDate()-1);
	const yesterday = `${yesterday_date.getFullYear()}-${String(yesterday_date.getMonth()+1).padStart(2,"0")}-${String(yesterday_date.getDate()).padStart(2,"0")}`;
	const time = `${String(date.getHours()).padStart(2,"0")}:${String(date.getMinutes()).padStart(2,"0")}`;
	for (const node of ordered) {
		const c = node.config; const out: Record<string, Signal> = {}; signals[node.id] = out;
		const input = (port: string): Signal => { const edge = graph.connections.find(e => e.to === node.id && e.input === port); return edge ? signals[edge.from]?.[edge.output] ?? { value: false, token: "" } : { value: false, token: "" }; };
		const emit = (port: string, value: boolean | number, token = String(value)) => { out[port] = { value, token }; };
		const once = (port: string) => { const signal = input(port); const key = `${node.id}.${port}`; if (!signal.value) { delete state.fired[key]; return false; } if (state.fired[key] === signal.token) { return false; } state.fired[key] = signal.token; return true; };
		const pulse = String(state.sequence);
		if (node.kind !== "variable" && graph.connections.some(e => e.to === node.id && signals[e.from]?.[e.output]?.available === false)) { for (const [port,type] of Object.entries(behavior_catalog[node.kind].outputs)) { out[port] = { value: type === "number" ? 0 : false, token: "", available: false }; } continue; }
		switch (node.kind) {
			case "location": emit("present", context.at_location === true); emit("away", context.at_location === false); for (const port of Object.keys(out)) { out[port].available = context.at_location !== undefined; } break;
			case "button": emit("pressed", context.tap === node.id, pulse); break;
			case "check_in": emit("done", context.tap === node.id, pulse); if (context.tap === node.id) { state.days[node.id] = day; } break;
			case "arrive": emit("arrived", context.at_location === true && previous.at_location === false, pulse); break;
			case "leave": emit("left", context.at_location === false && previous.at_location === true, pulse); break;
			case "clock": emit("due", c.days.includes(date.getDay()+1) && time === c.time, day + c.time); break;
			case "app_usage": emit("minutes", context.usage_minutes ?? 0); emit("reached", context.usage_minutes !== undefined && context.usage_minutes >= c.value, day); out.minutes.available = out.reached.available = context.usage_minutes !== undefined; break;
			case "and": case "or": { const a = input("a"), b = input("b"); emit("result", node.kind === "and" ? Boolean(a.value && b.value) : Boolean(a.value || b.value), `${a.value ? a.token : ""}:${b.value ? b.token : ""}`); break; }
			case "not": emit("result", !input("condition").value); break;
			case "branch": emit("yes", Boolean(input("condition").value), input("condition").token); emit("no", !input("condition").value); break;
			case "delay": { if (once("start")) { if (state.pending.length >= 128) { throw new Error("Too many pending delays. Reset the routine before adding more."); } state.pending = state.pending.filter(p => p.id !== node.id); state.pending.push({ id: node.id, at: context.now + c.minutes * 60000, token: pulse }); } const due = state.pending.filter(p => p.id === node.id && p.at <= context.now); state.pending = state.pending.filter(p => p.id !== node.id || p.at > context.now); emit("done", due.length > 0, due.map(p => p.token).join(":")); break; }
			case "variable": { const edge = graph.connections.some(e => e.to === node.id && e.input === "set"); if (edge && input("set").available !== false) { state.values[node.id] = Number(input("set").value); } emit("value", state.values[node.id] ?? c.value); break; }
			case "count": if (once("reset")) { state.values[node.id] = 0; } if (once("increment")) { state.values[node.id] = Math.min(1000000,(state.values[node.id] ?? 0)+c.value); } emit("value", state.values[node.id] ?? 0); break;
			case "compare": case "goal": { const value = Number(input("value").value); const result = node.kind === "goal" || c.operator === "gte" ? value >= c.value : c.operator === "gt" ? value > c.value : c.operator === "eq" ? value === c.value : c.operator === "lt" ? value < c.value : value <= c.value; emit(node.kind === "goal" ? "reached" : "result", result); break; }
			case "streak": if (once("check_in") && state.days[node.id] !== day) { state.values[node.id] = state.days[node.id] === yesterday ? (state.values[node.id] ?? 0)+1 : 1; state.days[node.id] = day; } emit("days", state.days[node.id] === day || state.days[node.id] === yesterday ? state.values[node.id] ?? 0 : 0); break;
			case "reminder": { const send = once("send"); if (send) { effects.push({ id: node.id, message: c.message }); } emit("sent", send, pulse); break; }
		}
	}
	state.at_location = context.at_location;
	return { state, signals, effects };
}
