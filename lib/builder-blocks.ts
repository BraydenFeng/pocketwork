import { z } from "zod";
import type { BehaviorContext, BehaviorNode, BehaviorState, Signal } from "./behaviors";

export type PortType = "boolean" | "number" | "text" | "record" | "table";
export type Scalar = number | string | boolean;
export type Entry = { id: string; at: number; values: Record<string, Scalar> };
export type BuilderState = { inputs: Record<string, Scalar>; forms: Record<string, Record<string, Scalar>>; entries: Record<string, Entry[]>; rewards: Record<string, string>; gates: Record<string, boolean> };
export type BuilderAction = { id: string; kind: "app_gate" | "add_allowance"; token: string; active?: boolean; minutes?: number; groups?: string[] };
export const builder_kinds = ["number_input", "text_input", "checkbox", "form", "save_entry", "aggregate", "calculate", "text_compare", "table", "chart", "progress", "health", "app_gate", "add_allowance"] as const;
export const health_metrics = ["steps", "active_energy", "exercise_minutes", "protein", "carbohydrates", "fat", "water"] as const;
const scalar_schema = z.union([z.number().finite().min(-1000000).max(1000000), z.string().max(240), z.boolean()]);
export const form_field_schema = z.object({ id: z.string().regex(/^[a-zA-Z][a-zA-Z0-9_]{0,31}$/).refine(id => !["record", "submitted", "__proto__", "constructor", "prototype"].includes(id)), label: z.string().trim().min(1).max(80), type: z.enum(["number", "text", "boolean"]), required: z.boolean() }).strict();
export const builder_config_fields = {
	fields: z.array(form_field_schema).min(1).max(8).refine(fields => new Set(fields.map(f => f.id)).size === fields.length, "Form fields need unique IDs.").optional(),
	field: z.string().max(32).optional(), text: z.string().max(240).optional(),
	operation: z.enum(["add", "subtract", "multiply", "divide", "sum", "average", "minimum", "maximum", "count", "equals", "contains", "starts_with"]).optional(),
	metric: z.enum(health_metrics).optional(), groups: z.array(z.string().trim().min(1).max(40)).max(20).optional(),
};
export const default_fields: z.infer<typeof form_field_schema>[] = [{ id: "value", label: "Value", type: "number", required: true }];
const entry = (title: string, detail: string, category: string, inputs: Record<string, PortType>, outputs: Record<string, PortType>) => ({ title, detail, category, inputs, outputs });
export const builder_catalog = {
	number_input: entry("Number input", "A number the user can change", "Inputs", {}, { value: "number", changed: "boolean" }),
	text_input: entry("Text input", "Text the user can enter", "Inputs", {}, { value: "text", changed: "boolean" }),
	checkbox: entry("Checkbox", "A user-controlled condition", "Inputs", {}, { checked: "boolean", changed: "boolean" }),
	form: entry("Form", "Named fields submitted together", "Inputs", {}, { submitted: "boolean", record: "record" }),
	save_entry: entry("Save entry", "Keep submitted records and their timestamps", "Data", { record: "record", save: "boolean", clear: "boolean" }, { rows: "table", count: "number", saved: "boolean" }),
	aggregate: entry("Summarize data", "Sum, average, count or find a range", "Data", { rows: "table" }, { value: "number" }),
	calculate: entry("Calculate", "Arithmetic on two connected numbers", "Logic", { a: "number", b: "number" }, { value: "number" }),
	text_compare: entry("Compare text", "Match text or look for a phrase", "Logic", { text: "text" }, { result: "boolean" }),
	table: entry("Table", "Display saved entries", "Display", { rows: "table" }, { rows: "table" }),
	chart: entry("Chart", "Plot a numeric field over time", "Display", { rows: "table" }, { rows: "table" }),
	progress: entry("Progress bar", "Show a number against a target", "Display", { value: "number", target: "number" }, { value: "number", fraction: "number", target: "number" }),
	health: entry("Apple Health", "Read a daily health metric on iPhone", "Inputs", {}, { value: "number" }),
	app_gate: entry("App gate", "Block selected groups while a condition is true", "Actions", { closed: "boolean" }, { active: "boolean" }),
	add_allowance: entry("Add screen time", "Add minutes to the active home allowance, once per day", "Actions", { grant: "boolean" }, { granted: "boolean" }),
};
export function form_fields(node: BehaviorNode) { return node.config.fields ?? default_fields; }
export function blank_builder(): BuilderState { return { inputs: {}, forms: {}, entries: {}, rewards: {}, gates: {} }; }
export function builder_node(node: BehaviorNode, state: BehaviorState, context: BehaviorContext, input: (port: string) => Signal, emit: (port: string, value: Signal["value"], token?: string) => void, once: (port: string) => boolean, actions: BuilderAction[], day: string): void {
	const data = state.data ??= blank_builder(); const c = node.config; const pulse = String(state.sequence);
	const unavailable = (port: string) => ({ port, signal: { value: 0, token: "", available: false } });
	function number_result(value: number) { emit("value", value); return Number.isFinite(value) && Math.abs(value) <= 1000000; }
	if (["number_input", "text_input", "checkbox"].includes(node.kind)) {
		const incoming = context.inputs?.[node.id]; const changed = incoming !== undefined;
		if (changed) { const value = scalar_schema.parse(incoming); const type = node.kind === "number_input" ? "number" : node.kind === "text_input" ? "string" : "boolean"; if (typeof value !== type) { throw new Error("The input value does not match its field type."); } data.inputs[node.id] = value; }
		emit(node.kind === "checkbox" ? "checked" : "value", data.inputs[node.id] ?? (node.kind === "number_input" ? c.value : node.kind === "text_input" ? c.text ?? "" : false)); emit("changed", changed, pulse); return;
	}
	switch (node.kind) {
		case "form": {
			const submitted = context.submission?.node === node.id;
			if (submitted) {
				const record: Record<string, Scalar> = {};
				for (const field of form_fields(node)) { const raw = context.submission!.values[field.id]; if (raw === undefined || (typeof raw === "string" && !raw.trim())) { if (field.required) { throw new Error(`Fill in ${field.label}.`); } record[field.id] = field.type === "text" ? "" : field.type === "number" ? 0 : false; continue; } const value = scalar_schema.parse(raw); if (typeof value !== (field.type === "text" ? "string" : field.type)) { throw new Error(`${field.label} has the wrong type.`); } record[field.id] = value; }
				data.forms[node.id] = record;
			}
			const values = data.forms[node.id]; emit("record", values ?? {}, pulse); emit("submitted", submitted, pulse);
			for (const field of form_fields(node)) { emit(field.id, values?.[field.id] ?? (field.type === "text" ? "" : field.type === "number" ? 0 : false)); }
			break;
		}
		case "save_entry": {
			if (once("clear")) { data.entries[node.id] = []; }
			const saved = once("save");
			if (saved) { const values = z.record(z.string().max(32), scalar_schema).parse(input("record").value); if (Object.keys(values).length > 8) { throw new Error("An entry supports at most eight fields."); } const rows = data.entries[node.id] ?? []; data.entries[node.id] = [...rows, { id: `${node.id}-${pulse}`, at: context.now, values }].slice(-200); }
			const rows = data.entries[node.id] ?? []; emit("rows", rows); emit("count", rows.length); emit("saved", saved, pulse); break;
		}
		case "aggregate": {
			const rows = input("rows").value as Entry[]; const values = rows.map(row => row.values[c.field ?? "value"]).filter((value): value is number => typeof value === "number");
			const op = c.operation ?? "sum";
			const value = op === "count" ? rows.length : values.length === 0 ? 0 : op === "average" ? values.reduce((a,b) => a+b,0)/values.length : op === "minimum" ? Math.min(...values) : op === "maximum" ? Math.max(...values) : values.reduce((a,b) => a+b,0);
			number_result(value); break;
		}
		case "calculate": { const a = Number(input("a").value), b = Number(input("b").value); number_result(c.operation === "subtract" ? a-b : c.operation === "multiply" ? a*b : c.operation === "divide" ? a/b : a+b); break; }
		case "text_compare": { const value = String(input("text").value), target = c.text ?? ""; emit("result", c.operation === "contains" ? value.includes(target) : c.operation === "starts_with" ? value.startsWith(target) : value === target); break; }
		case "table": case "chart": emit("rows", input("rows").value); break;
		case "progress": { const value = Number(input("value").value); const source = input("target"); const target = source.token === "" ? c.value : Number(source.value); emit("value", value); emit("target", target); emit("fraction", target > 0 ? Math.max(0,Math.min(1,value/target)) : 0); break; }
		case "health": emit("value", context.health?.[c.metric ?? "steps"] ?? unavailable("value").signal.value); break;
		case "app_gate": { const active = Boolean(input("closed").value); if (data.gates[node.id] !== active || context.reconcile_actions) { actions.push({ id: node.id, kind: "app_gate", token: `${node.id}:${active}`, active, groups: c.groups ?? [] }); data.gates[node.id] = active; } emit("active", active); break; }
		case "add_allowance": { const grant = Boolean(input("grant").value) && data.rewards[node.id] !== day; if (grant) { actions.push({ id: node.id, kind: "add_allowance", token: `${node.id}:${day}`, minutes: c.minutes }); data.rewards[node.id] = day; } emit("granted", grant, day); break; }
	}
}
