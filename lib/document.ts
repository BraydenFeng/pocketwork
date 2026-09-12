import { z } from "zod";

const identifier = z.string().regex(/^[a-zA-Z0-9_-]{1,64}$/);
const short_text = z.string().trim().min(1).max(80);
const base_fields = { id: identifier, title: short_text };

export const block_schema = z.discriminatedUnion("type", [
	z.object({ ...base_fields, type: z.literal("heading"), subtitle: z.string().max(200) }).strict(),
	z.object({ ...base_fields, type: z.literal("timer"), minutes: z.number().int().min(15).max(120) }).strict(),
	z.object({ ...base_fields, type: z.literal("checklist"), items: z.array(z.object({ id: identifier, text: short_text }).strict()).min(1).max(20) }).strict(),
	z.object({ ...base_fields, type: z.literal("counter"), target: z.number().int().min(1).max(1000) }).strict(),
	z.object({ ...base_fields, type: z.literal("note"), text: z.string().max(1000) }).strict(),
	z.object({ ...base_fields, type: z.literal("screen_time") }).strict(),
]);

export const document_schema = z.object({
	schema_version: z.literal(1),
	id: identifier,
	name: short_text,
	description: z.string().max(200),
	blocks: z.array(block_schema).min(1).max(20),
	rules: z.object({ block_during_focus: z.boolean(), notify_on_complete: z.boolean() }).strict(),
}).strict().superRefine((document, context) => {
	const ids = new Set<string>();
	for (const block of document.blocks) {
		for (const id of [block.id, ...(block.type === "checklist" ? block.items.map((item) => item.id) : [])]) {
			if (ids.has(id)) { context.addIssue({ code: "custom", message: "Every block and task needs a unique ID." }); }
			ids.add(id);
		}
	}
	for (const type of ["timer", "screen_time"]) {
		if (document.blocks.filter((block) => block.type === type).length > 1) {
			context.addIssue({ code: "custom", message: `Version 1 supports one ${type.replace("_", " ")} block.` });
		}
	}
	const has_timer = document.blocks.some((block) => block.type === "timer");
	const has_screen_time = document.blocks.some((block) => block.type === "screen_time");
	if (document.rules.block_during_focus && (!has_timer || !has_screen_time)) {
		context.addIssue({ code: "custom", message: "Focus blocking needs both a timer and a Screen Time block." });
	}
	if (document.rules.notify_on_complete && !has_timer) {
		context.addIssue({ code: "custom", message: "Completion notifications need a timer." });
	}
});

export type AppDocument = z.infer<typeof document_schema>;
export type Block = z.infer<typeof block_schema>;
export type BlockType = Block["type"];
export const MAX_DOCUMENT_BYTES = 100_000;

export function parse_document(text: string): AppDocument {
	if (new TextEncoder().encode(text).length > MAX_DOCUMENT_BYTES) {
		throw new Error("This file is too large. Personal tools must be under 100 KB.");
	}
	let value: unknown;
	try { value = JSON.parse(text); } catch { throw new Error("This is not a valid JSON file."); }
	const result = document_schema.safeParse(value);
	if (!result.success) { throw new Error(`Cannot open this tool: ${result.error.issues[0].message}`); }
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
	}
}

export function remove_block(document: AppDocument, block_id: string): AppDocument {
	if (document.blocks.length === 1) { return document; }
	const blocks = document.blocks.filter((block) => block.id !== block_id);
	const has_timer = blocks.some((block) => block.type === "timer");
	const has_screen_time = blocks.some((block) => block.type === "screen_time");
	return { ...document, blocks, rules: {
		block_during_focus: document.rules.block_during_focus && has_timer && has_screen_time,
		notify_on_complete: document.rules.notify_on_complete && has_timer,
	} };
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
