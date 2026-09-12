import { z } from "zod";
import { document_schema, new_id, type AppDocument } from "./document";
import { describe_schedule } from "./schedule";
import { load_draft, type DraftStorage } from "./storage";

export const LIBRARY_KEY = "pocketwork.library.v1";
export const MAX_TOOLS = 50;

const entry_schema = z.object({ document: document_schema, updated_at: z.string().datetime() }).strict();
export const library_schema = z.object({ schema_version: z.literal(1), tools: z.array(entry_schema).max(MAX_TOOLS) }).strict().superRefine((library, context) => {
	const ids = new Set<string>();
	for (const entry of library.tools) {
		if (ids.has(entry.document.id)) { context.addIssue({ code: "custom", message: "Every routine needs a unique ID." }); }
		ids.add(entry.document.id);
	}
});

export type Library = z.infer<typeof library_schema>;
export type LibraryEntry = Library["tools"][number];

export const empty_library: Library = { schema_version: 1, tools: [] };

function timestamp(now: number): string { return new Date(now).toISOString(); }

// A browser that only has a v1 single draft is upgraded in memory; the old key is left untouched so nothing is lost if saving fails.
export function load_library(storage: DraftStorage, now: number): Library | null {
	let raw: string | null;
	try { raw = storage.getItem(LIBRARY_KEY); }
	catch (error) { throw new Error(`Your saved tools could not be opened. They have not been overwritten. ${error instanceof Error ? error.message : "Storage unavailable."}`); }
	if (raw !== null) {
		let value: unknown;
		try { value = JSON.parse(raw); } catch { throw new Error("Your saved tools could not be opened. They have not been overwritten. The stored data is not valid JSON."); }
		const result = library_schema.safeParse(value);
		if (!result.success) { throw new Error(`Your saved tools could not be opened. They have not been overwritten. ${result.error.issues[0].message}`); }
		return result.data;
	}
	const legacy = load_draft(storage);
	return legacy ? { schema_version: 1, tools: [{ document: legacy, updated_at: timestamp(now) }] } : null;
}

export function save_library(storage: DraftStorage, library: Library): void {
	try { storage.setItem(LIBRARY_KEY, JSON.stringify(library_schema.parse(library))); }
	catch (error) { throw new Error(`Could not save to this browser. Export a backup. ${error instanceof Error ? error.message : "Storage unavailable."}`); }
}

export function find_tool(library: Library, id: string): AppDocument | undefined {
	return library.tools.find((entry) => entry.document.id === id)?.document;
}

export function upsert_tool(library: Library, document: AppDocument, now: number): Library {
	const entry = { document, updated_at: timestamp(now) };
	const exists = library.tools.some((item) => item.document.id === document.id);
	if (!exists && library.tools.length >= MAX_TOOLS) { throw new Error(`You can keep up to ${MAX_TOOLS} routines. Delete one to add another.`); }
	return { ...library, tools: exists ? library.tools.map((item) => item.document.id === document.id ? entry : item) : [...library.tools, entry] };
}

export function delete_tool(library: Library, id: string): Library {
	return { ...library, tools: library.tools.filter((entry) => entry.document.id !== id) };
}

export function duplicate_tool(library: Library, id: string, now: number): { library: Library; document: AppDocument } {
	const source = find_tool(library, id);
	if (!source) { throw new Error("That routine no longer exists."); }
	const document = { ...source, id: new_id(), name: `${source.name} copy`.slice(0, 80) };
	return { library: upsert_tool(library, document, now), document };
}

// Imported files keep their content but never collide with a tool already in the library.
export function import_tool(library: Library, document: AppDocument, now: number): { library: Library; document: AppDocument } {
	const next = find_tool(library, document.id) ? { ...document, id: new_id() } : document;
	return { library: upsert_tool(library, next, now), document: next };
}

export function sorted_tools(library: Library): LibraryEntry[] {
	return [...library.tools].sort((left, right) => right.updated_at.localeCompare(left.updated_at));
}

export function format_edited(updated_at: string, now: number): string {
	const elapsed = Math.max(0, now - Date.parse(updated_at));
	const minutes = Math.floor(elapsed / 60_000);
	if (minutes < 1) { return "Edited just now"; }
	if (minutes < 60) { return `Edited ${minutes} min ago`; }
	const hours = Math.floor(minutes / 60);
	if (hours < 24) { return `Edited ${hours} hr ago`; }
	const days = Math.floor(hours / 24);
	return days === 1 ? "Edited yesterday" : `Edited ${days} days ago`;
}

// A one-line, plain-language description of what a routine does, for cards.
export function summarize_tool(document: AppDocument): string {
	const parts: string[] = [];
	const timer = document.blocks.find((block) => block.type === "timer");
	const schedule = document.blocks.find((block) => block.type === "schedule");
	if (timer && timer.type === "timer") { parts.push(`${timer.minutes} min session`); }
	if (schedule && schedule.type === "schedule") { parts.push(describe_schedule(schedule)); }
	if (document.rules.block_during_focus) { parts.push("blocks apps"); }
	const tasks = document.blocks.filter((block) => block.type === "checklist").reduce((total, block) => total + (block.type === "checklist" ? block.items.length : 0), 0);
	if (tasks) { parts.push(`${tasks} task${tasks === 1 ? "" : "s"}`); }
	const counters = document.blocks.filter((block) => block.type === "counter").length;
	if (counters) { parts.push(`${counters} counter${counters === 1 ? "" : "s"}`); }
	return parts.length ? parts.join(" · ") : `${document.blocks.length} block${document.blocks.length === 1 ? "" : "s"}`;
}
