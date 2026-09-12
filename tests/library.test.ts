import { describe, expect, it } from "vitest";
import { describe_shield, document_schema, serialize_document, starter_document, type AppDocument } from "../lib/document";
import { add_group, delete_tool, duplicate_tool, empty_library, find_group, find_tool, format_edited, import_tool, LIBRARY_KEY, load_library, MAX_TOOLS, remove_group, rename_group, save_library, sorted_tools, summarize_tool, upsert_tool, type Library } from "../lib/library";
import { DRAFT_KEY } from "../lib/storage";
import { blank_tool, templates } from "../lib/templates";
import routines_fixture from "../public/routines.pocketwork.json";

const NOW = Date.parse("2026-09-10T12:00:00.000Z");

function memory_storage(seed: Record<string, string> = {}) {
	const values = new Map(Object.entries(seed));
	return { values, getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => { values.set(key, value); } };
}

function copy(): AppDocument { return structuredClone(starter_document); }

describe("tool library", () => {
	it("starts empty in a fresh browser", () => { expect(load_library(memory_storage(), NOW)).toBeNull(); });
	it("upgrades a v1 single draft into a one-tool library without touching the old key", () => {
		const storage = memory_storage({ [DRAFT_KEY]: serialize_document(copy()) });
		const library = load_library(storage, NOW);
		expect(library?.tools).toHaveLength(1);
		expect(library?.tools[0].document).toEqual(starter_document);
		expect(storage.values.has(LIBRARY_KEY)).toBe(false);
		expect(storage.values.get(DRAFT_KEY)).toBe(serialize_document(copy()));
	});
	it("round trips through storage", () => {
		const storage = memory_storage();
		const library = upsert_tool(empty_library, copy(), NOW);
		save_library(storage, library);
		expect(load_library(storage, NOW)).toEqual(library);
	});
	it("refuses corrupt libraries without overwriting them", () => {
		for (const raw of ["broken", "[]", JSON.stringify({ schema_version: 2, tools: [] }), JSON.stringify({ schema_version: 1, tools: [{ document: copy(), updated_at: "yesterday" }] })]) {
			const storage = memory_storage({ [LIBRARY_KEY]: raw });
			expect(() => load_library(storage, NOW)).toThrow("not been overwritten");
			expect(storage.values.get(LIBRARY_KEY)).toBe(raw);
		}
	});
	it("rejects duplicate tool IDs", () => {
		const entry = { document: copy(), updated_at: new Date(NOW).toISOString() };
		expect(() => save_library(memory_storage(), { schema_version: 1, tools: [entry, entry] })).toThrow();
	});
	it("surfaces quota failures with a backup hint", () => {
		expect(() => save_library({ getItem: () => null, setItem: () => { throw new Error("Quota exceeded"); } }, empty_library)).toThrow("Export a backup");
	});
	it("upserts by ID, stamping the edit time", () => {
		let library = upsert_tool(empty_library, copy(), NOW);
		library = upsert_tool(library, { ...copy(), name: "Renamed" }, NOW + 60_000);
		expect(library.tools).toHaveLength(1);
		expect(find_tool(library, "my-focus-space")?.name).toBe("Renamed");
		expect(library.tools[0].updated_at).toBe(new Date(NOW + 60_000).toISOString());
	});
	it("caps the number of tools", () => {
		let library: Library = empty_library;
		for (let index = 0; index < MAX_TOOLS; index++) { library = upsert_tool(library, { ...copy(), id: `tool-${index}` }, NOW); }
		expect(() => upsert_tool(library, { ...copy(), id: "one-more" }, NOW)).toThrow("up to 50");
		expect(upsert_tool(library, { ...copy(), id: "tool-0", name: "Still fits" }, NOW).tools).toHaveLength(MAX_TOOLS);
	});
	it("deletes, duplicates with a fresh ID, and imports around collisions", () => {
		const library = upsert_tool(empty_library, copy(), NOW);
		const deleted = delete_tool(library, "my-focus-space", NOW);
		expect(deleted.tools).toHaveLength(0);
		expect(deleted.removed).toEqual({ "my-focus-space": new Date(NOW).toISOString() });
		const copied = duplicate_tool(library, "my-focus-space", NOW);
		expect(copied.document.id).not.toBe("my-focus-space");
		expect(copied.document.name).toBe("My focus space copy");
		expect(copied.library.tools).toHaveLength(2);
		expect(() => duplicate_tool(library, "missing", NOW)).toThrow("no longer exists");
		const imported = import_tool(library, copy(), NOW);
		expect(imported.document.id).not.toBe("my-focus-space");
		expect(imported.library.tools).toHaveLength(2);
		expect(import_tool(library, { ...copy(), id: "fresh" }, NOW).document.id).toBe("fresh");
	});
	it("lists most recently edited first", () => {
		let library = upsert_tool(empty_library, { ...copy(), id: "older" }, NOW - 1000);
		library = upsert_tool(library, { ...copy(), id: "newer" }, NOW);
		expect(sorted_tools(library).map((entry) => entry.document.id)).toEqual(["newer", "older"]);
	});
	it("describes tools and edit times in plain words", () => {
		expect(summarize_tool(copy())).toBe("25 min session · blocks apps · 3 tasks");
		expect(summarize_tool(blank_tool())).toBe("1 block");
		const stamp = (offset: number) => new Date(NOW - offset).toISOString();
		expect(format_edited(stamp(0), NOW)).toBe("Edited just now");
		expect(format_edited(stamp(5 * 60_000), NOW)).toBe("Edited 5 min ago");
		expect(format_edited(stamp(3 * 3_600_000), NOW)).toBe("Edited 3 hr ago");
		expect(format_edited(stamp(24 * 3_600_000), NOW)).toBe("Edited yesterday");
		expect(format_edited(stamp(72 * 3_600_000), NOW)).toBe("Edited 3 days ago");
	});
});

describe("routine templates", () => {
	it("every routine and the blank tool are valid, exportable documents", () => {
		for (const build of [...templates.map((template) => template.build), blank_tool]) {
			const document = build();
			expect(document_schema.safeParse(document).success, document.name).toBe(true);
			expect(() => serialize_document(document)).not.toThrow();
		}
	});
	it("gives each new tool its own ID so two of the same routine can coexist", () => {
		const first = templates[0].build(); const second = templates[0].build();
		expect(first.id).not.toBe(second.id);
		expect(upsert_tool(upsert_tool(empty_library, first, NOW), second, NOW).tools).toHaveLength(2);
	});
	it("keeps the iPhone routines fixture identical to the editor templates", () => {
		expect(routines_fixture.routines.map((entry) => entry.template_id)).toEqual(templates.map((template) => template.id));
		for (const [index, template] of templates.entries()) {
			expect(routines_fixture.routines[index].tagline).toBe(template.tagline);
			expect(routines_fixture.routines[index].document).toEqual({ ...template.build(), id: template.id });
		}
	});
	it("every routine enforces something, not just tracks it", () => {
		for (const template of templates) { expect(template.build().rules.block_during_focus, template.name).toBe(true); }
	});
});

describe("app groups", () => {
	it("adds, renames through every routine, and refuses to delete a group in use", () => {
		let library = add_group(empty_library, " Social ");
		expect(library.groups).toEqual([{ id: expect.any(String), name: "Social" }]);
		expect(() => add_group(library, "social")).toThrow("already");
		const routine = { ...copy(), blocks: copy().blocks.map((block) => block.type === "screen_time" ? { ...block, mode: "block" as const, groups: ["Social"] } : block) };
		library = upsert_tool(library, routine, NOW);
		expect(summarize_tool(routine)).toBe("25 min session · blocks Social · 3 tasks");
		const id = library.groups![0].id;
		library = rename_group(library, id, "Feeds", NOW + 1000);
		const shield = library.tools[0].document.blocks.find((block) => block.type === "screen_time");
		expect(shield?.type === "screen_time" && shield.groups).toEqual(["Feeds"]);
		expect(library.tools[0].updated_at).toBe(new Date(NOW + 1000).toISOString());
		expect(() => remove_group(library, id)).toThrow("used by");
		const unused = add_group(empty_library, "Unused");
		expect(remove_group(unused, unused.groups![0].id).groups).toBeUndefined();
	});
	it("creates groups a routine mentions but the library does not have yet", () => {
		const routine = { ...copy(), blocks: copy().blocks.map((block) => block.type === "screen_time" ? { ...block, mode: "allow_only" as const, groups: ["Work", "Study"] } : block) };
		const library = upsert_tool(empty_library, routine, NOW);
		expect(library.groups?.map((group) => group.name)).toEqual(["Work", "Study"]);
		expect(find_group(library, "work")?.name).toBe("Work");
	});
	it("validates the three functions", () => {
		const shield = (extra: Record<string, unknown>) => ({ ...copy(), blocks: copy().blocks.map((block) => block.type === "screen_time" ? { ...block, ...extra } : block) });
		expect(document_schema.safeParse(shield({ mode: "allow_only" })).success).toBe(false);
		expect(document_schema.safeParse(shield({ mode: "limit", groups: ["Social"] })).success).toBe(false);
		expect(document_schema.safeParse(shield({ mode: "limit", groups: ["Social"], limit_minutes: 30 })).success).toBe(true);
		expect(document_schema.safeParse(shield({ mode: "block", groups: ["Social"], limit_minutes: 30 })).success).toBe(false);
		expect(document_schema.safeParse(shield({ groups: ["Social", "social"] })).success).toBe(false);
		expect(document_schema.safeParse(shield({})).success).toBe(true);
		expect(describe_shield({ id: "s", type: "screen_time", title: "S", mode: "limit", groups: ["Social"], limit_minutes: 30 })).toBe("Social · 30 min limit");
		expect(describe_shield({ id: "s", type: "screen_time", title: "S", mode: "allow_only", groups: ["Work"] })).toBe("Only Work");
		expect(describe_shield({ id: "s", type: "screen_time", title: "S" })).toBe("Apps chosen on iPhone");
	});
});
