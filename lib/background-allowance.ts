import type { BehaviorNode, Behaviors } from "./behaviors";
import type { AppDocument } from "./document";
import { home_policy_schema, type HomePolicy } from "./home-policy";

type AllowanceAtom =
	| { kind: "location"; id: string }
	| { kind: "window"; id: string; days: number[]; start: string; end: string }
	| { kind: "allowance"; id: string; usage_id: string; minutes: number };

type AllowanceBranch = AllowanceAtom[];

export type CompiledHomeAllowance = {
	policy: HomePolicy;
	group: string;
	gate_id: string;
};

function source(graph: Behaviors, id: string, input: string) {
	return graph.connections.find(edge => edge.to === id && edge.input === input);
}

function node(graph: Behaviors, id: string): BehaviorNode | undefined {
	return graph.nodes.find(item => item.id === id);
}

function branches_from(graph: Behaviors, id: string, output: string, visiting: Set<string>): AllowanceBranch[] | null {
	const current = node(graph, id);
	if (!current) { return null; }
	const key = `${id}:${output}`;
	if (visiting.has(key)) { return null; }
	const next_visiting = new Set(visiting).add(key);
	if (current.kind === "location" && output === "present") { return [[{ kind: "location", id }]]; }
	if (current.kind === "time_window" && output === "active") {
		const end = current.config.end_time ?? "20:00";
		if (end <= current.config.time) { return null; }
		return [[{ kind: "window", id, days: [...current.config.days].sort((a, b) => a - b), start: current.config.time, end }]];
	}
	if (current.kind === "compare" && output === "result") {
		const value = source(graph, id, "value");
		const threshold = source(graph, id, "threshold");
		const usage = value ? node(graph, value.from) : undefined;
		if (current.config.operator !== "gte" || threshold || !value || value.output !== "minutes" || usage?.kind !== "app_usage" || !Number.isInteger(current.config.value) || current.config.value < 1 || current.config.value > 180) { return null; }
		return [[{ kind: "allowance", id, usage_id: usage.id, minutes: current.config.value }]];
	}
	if ((current.kind === "and" || current.kind === "or") && output === "result") {
		const a = source(graph, id, "a");
		const b = source(graph, id, "b");
		if (!a || !b) { return null; }
		const left = branches_from(graph, a.from, a.output, next_visiting);
		const right = branches_from(graph, b.from, b.output, next_visiting);
		if (!left || !right) { return null; }
		if (current.kind === "or") { return left.length + right.length <= 14 ? [...left, ...right] : null; }
		if (left.length * right.length > 14) { return null; }
		return left.flatMap(left_branch => right.map(right_branch => [...left_branch, ...right_branch]));
	}
	return null;
}

export function derive_home_allowance(graph: Behaviors | undefined): CompiledHomeAllowance | null {
	if (!graph) { return null; }
	const gates = graph.nodes.filter(item => item.kind === "app_gate");
	const groups = gates[0]?.config.groups;
	if (gates.length !== 1 || groups?.length !== 1) { return null; }
	const gate = gates[0];
	const closed = source(graph, gate.id, "closed");
	if (!closed) { return null; }
	const expanded = branches_from(graph, closed.from, closed.output, new Set());
	if (!expanded?.length) { return null; }

	const normalized: { location_id: string; usage_id: string; window: Extract<AllowanceAtom, { kind: "window" }>; minutes: number }[] = [];
	for (const branch of expanded) {
		const locations = branch.filter((atom): atom is Extract<AllowanceAtom, { kind: "location" }> => atom.kind === "location");
		const windows = branch.filter((atom): atom is Extract<AllowanceAtom, { kind: "window" }> => atom.kind === "window");
		const allowances = branch.filter((atom): atom is Extract<AllowanceAtom, { kind: "allowance" }> => atom.kind === "allowance");
		if (locations.length !== 1 || windows.length !== 1 || allowances.length !== 1 || branch.length !== 3) { return null; }
		normalized.push({ location_id: locations[0].id, usage_id: allowances[0].usage_id, window: windows[0], minutes: allowances[0].minutes });
	}
	if (new Set(normalized.map(item => item.location_id)).size !== 1 || new Set(normalized.map(item => item.usage_id)).size !== 1) { return null; }

	const unique = new Map<string, typeof normalized[number]>();
	for (const item of normalized) { unique.set(`${item.window.id}:${item.minutes}`, item); }
	const grouped = new Map<string, { days: number[]; allowance_minutes: number; windows: { start: string; end: string }[] }>();
	for (const item of unique.values()) {
		const key = `${item.window.days.join(",")}:${item.minutes}`;
		const rule = grouped.get(key) ?? { days: item.window.days, allowance_minutes: item.minutes, windows: [] };
		rule.windows.push({ start: item.window.start, end: item.window.end });
		grouped.set(key, rule);
	}
	const candidate = {
		timezone: "America/Los_Angeles" as const,
		away_usage_counts: false as const,
		outside_windows: "unrestricted" as const,
		rules: [...grouped.values()]
			.map(rule => ({ ...rule, windows: rule.windows.sort((a, b) => a.start.localeCompare(b.start)) })),
	};
	const parsed = home_policy_schema.safeParse(candidate);
	return parsed.success ? { policy: parsed.data, group: groups[0], gate_id: gate.id } : null;
}

export function same_home_policy(a: HomePolicy | undefined, b: HomePolicy | undefined): boolean {
	return Boolean(a && b && JSON.stringify(a) === JSON.stringify(b));
}

export function is_block_authored_home_allowance(document: Pick<AppDocument, "behaviors" | "home_allowance">): boolean {
	return same_home_policy(document.home_allowance, derive_home_allowance(document.behaviors)?.policy);
}
