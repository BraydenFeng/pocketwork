import { z } from "zod";

const identifier = z.string().regex(/^[a-zA-Z0-9_-]{1,64}$/);
const short_text = z.string().trim().min(1).max(80);
const base_fields = { id: identifier, title: short_text };
const clock_time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Times look like 22:00.");
export const group_name = z.string().trim().min(1).max(40);
export const MAX_GROUPS = 20;

export const block_schema = z.discriminatedUnion("type", [
	z.object({ ...base_fields, type: z.literal("heading"), subtitle: z.string().max(200) }).strict(),
	z.object({ ...base_fields, type: z.literal("timer"), minutes: z.number().int().min(15).max(120) }).strict(),
	z.object({ ...base_fields, type: z.literal("checklist"), items: z.array(z.object({ id: identifier, text: short_text }).strict()).min(1).max(20) }).strict(),
	z.object({ ...base_fields, type: z.literal("counter"), target: z.number().int().min(1).max(1000) }).strict(),
	z.object({ ...base_fields, type: z.literal("note"), text: z.string().max(1000) }).strict(),
	// What happens to which apps. Groups are named on the web and filled on the phone; no groups means "choose apps for this routine on the phone".
	// block: lock the groups. allow_only: lock everything except the groups. limit: lock the groups after limit_minutes of use inside the routine's window.
	z.object({ ...base_fields, type: z.literal("screen_time"), mode: z.enum(["block", "allow_only", "limit"]).optional(), groups: z.array(group_name).max(MAX_GROUPS).optional(), limit_minutes: z.number().int().min(15).max(1440).optional() }).strict(),
	// A standing routine: instead of a timer you start, a window that turns itself on. Days use 1 = Sunday … 7 = Saturday.
	z.object({ ...base_fields, type: z.literal("schedule"), days: z.array(z.number().int().min(1).max(7)).min(1).max(7), start: clock_time, end: clock_time }).strict(),
]);

function window_minutes(start: string, end: string): number {
	const [start_hours, start_minutes] = start.split(":").map(Number);
	const [end_hours, end_minutes] = end.split(":").map(Number);
	const from = start_hours * 60 + start_minutes;
	const to = end_hours * 60 + end_minutes;
	return to > from ? to - from : 24 * 60 - from + to;
}

export const document_schema = z.object({
	schema_version: z.literal(1),
	id: identifier,
	name: short_text,
	description: z.string().max(200),
	blocks: z.array(block_schema).min(1).max(20),
	rules: z.object({ block_during_focus: z.boolean(), notify_on_complete: z.boolean() }).strict(),
	// Only meaningful for a standing routine: whether the person has switched it on.
	enabled: z.boolean().optional(),
}).strict().superRefine((document, context) => {
	const ids = new Set<string>();
	for (const block of document.blocks) {
		for (const id of [block.id, ...(block.type === "checklist" ? block.items.map((item) => item.id) : [])]) {
			if (ids.has(id)) { context.addIssue({ code: "custom", message: "Every block and task needs a unique ID." }); }
			ids.add(id);
		}
	}
	for (const type of ["timer", "screen_time", "schedule"]) {
		if (document.blocks.filter((block) => block.type === type).length > 1) {
			context.addIssue({ code: "custom", message: `Version 1 supports one ${type.replace("_", " ")} block.` });
		}
	}
	const has_timer = document.blocks.some((block) => block.type === "timer");
	const has_screen_time = document.blocks.some((block) => block.type === "screen_time");
	const schedule = document.blocks.find((block) => block.type === "schedule");
	if (schedule && schedule.type === "schedule") {
		if (has_timer) { context.addIssue({ code: "custom", message: "A routine either runs on a schedule or when you start it, not both. Remove the timer or the schedule." }); }
		if (!has_screen_time || !document.rules.block_during_focus) { context.addIssue({ code: "custom", message: "A scheduled routine needs a Screen Time block with blocking turned on, otherwise it has nothing to do." }); }
		if (new Set(schedule.days).size !== schedule.days.length) { context.addIssue({ code: "custom", message: "Each day can only be chosen once." }); }
		if (schedule.start === schedule.end) { context.addIssue({ code: "custom", message: "A schedule needs a start time and a different end time." }); }
		else if (window_minutes(schedule.start, schedule.end) < 15) { context.addIssue({ code: "custom", message: "A scheduled window must last at least 15 minutes; iOS cannot monitor anything shorter." }); }
	} else if (document.enabled !== undefined) {
		context.addIssue({ code: "custom", message: "Only a scheduled routine can be switched on or off." });
	}
	const shield = document.blocks.find((block) => block.type === "screen_time");
	if (shield && shield.type === "screen_time") {
		const groups = shield.groups ?? [];
		if (new Set(groups.map((name) => name.toLowerCase())).size !== groups.length) { context.addIssue({ code: "custom", message: "Each group can only be listed once." }); }
		if ((shield.mode === "allow_only" || shield.mode === "limit") && groups.length === 0) { context.addIssue({ code: "custom", message: `"${shield.mode === "limit" ? "Limit" : "Only these"}" needs at least one app group.` }); }
		if (shield.mode === "limit" && shield.limit_minutes === undefined) { context.addIssue({ code: "custom", message: "A limit needs a number of minutes." }); }
		if (shield.mode !== "limit" && shield.limit_minutes !== undefined) { context.addIssue({ code: "custom", message: "Minutes only apply to a limit." }); }
	}
	if (document.rules.block_during_focus && !has_screen_time) {
		context.addIssue({ code: "custom", message: "Blocking needs a Screen Time block." });
	}
	if (document.rules.block_during_focus && !has_timer && !schedule) {
		context.addIssue({ code: "custom", message: "Blocking needs either a timer or a schedule." });
	}
	if (document.rules.notify_on_complete && !has_timer) {
		context.addIssue({ code: "custom", message: "Completion notifications need a timer." });
	}
});

export type AppDocument = z.infer<typeof document_schema>;
export type Block = z.infer<typeof block_schema>;
export type BlockType = Block["type"];
export const MAX_DOCUMENT_BYTES = 100_000;

export function is_standing(document: AppDocument): boolean { return document.blocks.some((block) => block.type === "schedule"); }

export type ShieldMode = "block" | "allow_only" | "limit";
export function shield_mode(block: Extract<Block, { type: "screen_time" }>): ShieldMode { return block.mode ?? "block"; }

// Group names a routine refers to, in document order, without duplicates.
export function referenced_groups(document: AppDocument): string[] {
	const names: string[] = [];
	for (const block of document.blocks) {
		if (block.type !== "screen_time") { continue; }
		for (const name of block.groups ?? []) { if (!names.some((entry) => entry.toLowerCase() === name.toLowerCase())) { names.push(name); } }
	}
	return names;
}

// Plain words for what the Screen Time block does, used on cards, in the preview, and on the phone.
export function describe_shield(block: Extract<Block, { type: "screen_time" }>): string {
	const groups = block.groups ?? [];
	if (groups.length === 0) { return "Apps chosen on iPhone"; }
	const list = groups.length <= 3 ? groups.join(", ") : `${groups.slice(0, 2).join(", ")} + ${groups.length - 2} more`;
	switch (shield_mode(block)) {
		case "block": return `Blocks ${list}`;
		case "allow_only": return `Only ${list}`;
		case "limit": return `${list} · ${block.limit_minutes} min limit`;
	}
}

export function parse_document(text: string): AppDocument {
	if (new TextEncoder().encode(text).length > MAX_DOCUMENT_BYTES) {
		throw new Error("This file is too large. Routines must be under 100 KB.");
	}
	let value: unknown;
	try { value = JSON.parse(text); } catch { throw new Error("This is not a valid JSON file."); }
	const result = document_schema.safeParse(value);
	if (!result.success) { throw new Error(`Cannot open this routine: ${result.error.issues[0].message}`); }
	return result.data;
}

export function serialize_document(document: AppDocument): string {
	return JSON.stringify(document_schema.parse(document), null, 2);
}

export function new_id(): string { return crypto.randomUUID(); }

export function create_block(type: BlockType): Block {
	const id = new_id();
	switch (type) {
		case "heading": return { id, type, title: "Make room for what matters.", subtitle: "A little space, just for you." };
		case "timer": return { id, type, title: "Focus session", minutes: 25 };
		case "checklist": return { id, type, title: "On my list", items: [{ id: new_id(), text: "My first task" }] };
		case "counter": return { id, type, title: "Small wins", target: 5 };
		case "note": return { id, type, title: "A note to myself", text: "One thing at a time." };
		case "screen_time": return { id, type, title: "Fewer distractions" };
		case "schedule": return { id, type, title: "Every evening", days: [1, 2, 3, 4, 5, 6, 7], start: "22:00", end: "07:00" };
	}
}

export function remove_block(document: AppDocument, block_id: string): AppDocument {
	if (document.blocks.length === 1) { return document; }
	const blocks = document.blocks.filter((block) => block.id !== block_id);
	const has_timer = blocks.some((block) => block.type === "timer");
	const has_screen_time = blocks.some((block) => block.type === "screen_time");
	const has_schedule = blocks.some((block) => block.type === "schedule");
	const next: AppDocument = { ...document, blocks, rules: {
		block_during_focus: document.rules.block_during_focus && (has_timer || has_schedule) && has_screen_time,
		notify_on_complete: document.rules.notify_on_complete && has_timer,
	} };
	if (!has_schedule) { delete next.enabled; }
	return next;
}

export function move_block(document: AppDocument, block_id: string, direction: -1 | 1): AppDocument {
	const index = document.blocks.findIndex((block) => block.id === block_id);
	const destination = index + direction;
	if (index < 0 || destination < 0 || destination >= document.blocks.length) { return document; }
	const blocks = [...document.blocks];
	[blocks[index], blocks[destination]] = [blocks[destination], blocks[index]];
	return { ...document, blocks };
}

export const starter_document: AppDocument = {
	schema_version: 1, id: "my-focus-space", name: "My focus space", description: "A quieter place to get things done.",
	blocks: [
		{ id: "welcome", type: "heading", title: "A little less noise.", subtitle: "A little more room for your next good idea." },
		{ id: "focus", type: "timer", title: "Make some headway", minutes: 25 },
		{ id: "tasks", type: "checklist", title: "What matters today", items: [{ id: "task-one", text: "Choose one thing to work on" }, { id: "task-two", text: "Give it my full attention" }, { id: "task-three", text: "Leave a note for next time" }] },
		{ id: "shield", type: "screen_time", title: "Leave distractions outside" },
	],
	rules: { block_during_focus: true, notify_on_complete: true },
};
