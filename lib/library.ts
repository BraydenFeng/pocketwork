import { z } from "zod";
import { document_schema, group_name, MAX_GROUPS, new_id, referenced_groups, type AppDocument } from "./document";
import { describe_schedule } from "./schedule";
import { describe_shield } from "./document";
import { load_draft, type DraftStorage } from "./storage";

export const LIBRARY_KEY = "pocketwork.library.v1";
export const MAX_TOOLS = 50;

const entry_schema = z.object({ document: document_schema, updated_at: z.string().datetime() }).strict();
// App groups are named here and shared by every routine; which apps are in them is set on each phone.
const group_schema = z.object({ id: z.string().regex(/^[a-zA-Z0-9_-]{1,64}$/), name: group_name }).strict();

// `removed` remembers deletions (id → when) so a routine deleted on one device does not come back from another.
export const library_schema = z.object({ schema_version: z.literal(1), tools: z.array(entry_schema).max(MAX_TOOLS), groups_updated_at: z.string().datetime().optional(), removed: z.record(z.string(), z.string().datetime()).optional(), groups: z.array(group_schema).max(MAX_GROUPS).optional() }).strict().superRefine((library, context) => {
	if (library.tools.filter((entry) => entry.document.home_allowance).length > 1) { context.addIssue({ code: "custom", message: "One home allowance can run on this iPhone." }); }
	const ids = new Set<string>();
	for (const entry of library.tools) {
		if (ids.has(entry.document.id)) { context.addIssue({ code: "custom", message: "Every routine needs a unique ID." }); }
		ids.add(entry.document.id);
	}
	const names = new Set<string>();
	for (const group of library.groups ?? []) {
		const key = group.name.toLowerCase();
		if (names.has(key)) { context.addIssue({ code: "custom", message: `Two app groups are called "${group.name}".` }); }
		names.add(key);
	}
});

export type AppGroup = z.infer<typeof group_schema>;

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
	const with_groups = ensure_groups(library, document);
	return { ...with_groups, tools: exists ? with_groups.tools.map((item) => item.document.id === document.id ? entry : item) : [...with_groups.tools, entry] };
}

export function delete_tool(library: Library, id: string, now: number): Library {
	return { ...library, tools: library.tools.filter((entry) => entry.document.id !== id), removed: { ...library.removed, [id]: timestamp(now) } };
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

export function find_group(library: Library, name: string): AppGroup | undefined {
	return (library.groups ?? []).find((group) => group.name.toLowerCase() === name.trim().toLowerCase());
}

export function add_group(library: Library, name: string): Library {
	const clean = group_name.parse(name);
	if (find_group(library, clean)) { throw new Error(`There is already an app group called "${clean}".`); }
	const groups = library.groups ?? [];
	if (groups.length >= MAX_GROUPS) { throw new Error(`You can have up to ${MAX_GROUPS} app groups.`); }
	return { ...library, groups_updated_at: timestamp(Date.now()), groups: [...groups, { id: new_id(), name: clean }] };
}

// Renaming follows through to every routine that mentions the group, so nothing silently stops matching.
export function rename_group(library: Library, id: string, name: string, now: number): Library {
	const clean = group_name.parse(name);
	const group = (library.groups ?? []).find((entry) => entry.id === id);
	if (!group) { throw new Error("That app group no longer exists."); }
	const clash = find_group(library, clean);
	if (clash && clash.id !== id) { throw new Error(`There is already an app group called "${clean}".`); }
	const groups = (library.groups ?? []).map((entry) => entry.id === id ? { ...entry, name: clean } : entry);
	const tools = library.tools.map((entry) => {
		const uses = entry.document.blocks.some((block) => block.type === "screen_time" && (block.groups ?? []).some((entry_name) => entry_name.toLowerCase() === group.name.toLowerCase()));
		if (!uses) { return entry; }
		const blocks = entry.document.blocks.map((block) => block.type === "screen_time" ? { ...block, groups: (block.groups ?? []).map((entry_name) => entry_name.toLowerCase() === group.name.toLowerCase() ? clean : entry_name) } : block);
		return { document: { ...entry.document, blocks }, updated_at: timestamp(now) };
	});
	return { ...library, groups, tools, groups_updated_at: timestamp(now) };
}

// A group can only go once no routine depends on it; the caller decides what to tell the person.
export function remove_group(library: Library, id: string): Library {
	const group = (library.groups ?? []).find((entry) => entry.id === id);
	if (!group) { return library; }
	const users = routines_using_group(library, group.name);
	if (users.length) { throw new Error(`"${group.name}" is used by ${users.map((entry) => `"${entry.name}"`).join(", ")}. Take it out of those routines first.`); }
	const groups = (library.groups ?? []).filter((entry) => entry.id !== id);
	return { ...library, groups, groups_updated_at: timestamp(Date.now()) };
}

export function routines_using_group(library: Library, name: string): AppDocument[] {
	return library.tools.map((entry) => entry.document).filter((document) => referenced_groups(document).some((entry) => entry.toLowerCase() === name.toLowerCase()));
}

// Routines can mention groups that do not exist yet (an import, or an agent naming a new one); they get created empty.
export function ensure_groups(library: Library, document: AppDocument): Library {
	let next = library;
	for (const name of referenced_groups(document)) { if (!find_group(next, name)) { next = add_group(next, name); } }
	return next;
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
	if (document.home_allowance) { return "Home only · shared daily distraction allowance"; }
	const parts: string[] = [];
	const timer = document.blocks.find((block) => block.type === "timer");
	const schedule = document.blocks.find((block) => block.type === "schedule");
	if (timer && timer.type === "timer") { parts.push(`${timer.minutes} min session`); }
	if (schedule && schedule.type === "schedule") { parts.push(describe_schedule(schedule)); }
	const shield = document.blocks.find((block) => block.type === "screen_time");
	if (document.rules.block_during_focus && shield?.type === "screen_time") {
		const words = describe_shield(shield);
		// Lowercase the verb, never a group name: "blocks Social", "only Work", but "Work · 45 min limit".
		parts.push(!(shield.groups ?? []).length ? "blocks apps" : /^(Blocks|Only) /.test(words) ? words.charAt(0).toLowerCase() + words.slice(1) : words);
	}
	const tasks = document.blocks.filter((block) => block.type === "checklist").reduce((total, block) => total + (block.type === "checklist" ? block.items.length : 0), 0);
	if (tasks) { parts.push(`${tasks} task${tasks === 1 ? "" : "s"}`); }
	const counters = document.blocks.filter((block) => block.type === "counter").length;
	if (counters) { parts.push(`${counters} counter${counters === 1 ? "" : "s"}`); }
	return parts.length ? parts.join(" · ") : `${document.blocks.length} block${document.blocks.length === 1 ? "" : "s"}`;
}
