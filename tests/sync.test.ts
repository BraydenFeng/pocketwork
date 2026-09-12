import { describe, expect, it } from "vitest";
import { starter_document, type AppDocument } from "../lib/document";
import { delete_tool, empty_library, upsert_tool, type Library } from "../lib/library";
import { merge_libraries, same_library, TOMBSTONE_DAYS } from "../lib/sync";

const NOW = Date.parse("2026-09-12T12:00:00.000Z");
const MINUTE = 60_000;

function doc(id: string, name = id): AppDocument { return { ...structuredClone(starter_document), id, name }; }

describe("merging a device copy with the account copy", () => {
	it("keeps routines that only one side has", () => {
		const local = upsert_tool(empty_library, doc("a"), NOW);
		const remote = upsert_tool(empty_library, doc("b"), NOW);
		expect(merge_libraries(local, remote, NOW).tools.map((entry) => entry.document.id)).toEqual(["a", "b"]);
	});
	it("takes the newer edit of the same routine, whichever side made it", () => {
		const local = upsert_tool(empty_library, doc("a", "Old name"), NOW - MINUTE);
		const remote = upsert_tool(empty_library, doc("a", "Newer name"), NOW);
		expect(merge_libraries(local, remote, NOW).tools[0].document.name).toBe("Newer name");
		expect(merge_libraries(remote, local, NOW).tools[0].document.name).toBe("Newer name");
	});
	it("a deletion on one side beats an older copy on the other", () => {
		const remote = upsert_tool(empty_library, doc("a"), NOW - 2 * MINUTE);
		const local = delete_tool(upsert_tool(empty_library, doc("a"), NOW - 2 * MINUTE), "a", NOW - MINUTE);
		const merged = merge_libraries(local, remote, NOW);
		expect(merged.tools).toHaveLength(0);
		expect(merged.removed).toEqual(local.removed);
	});
	it("an edit newer than the deletion brings the routine back and drops the tombstone", () => {
		const local = delete_tool(upsert_tool(empty_library, doc("a"), NOW - 2 * MINUTE), "a", NOW - MINUTE);
		const remote = upsert_tool(empty_library, doc("a", "Edited after"), NOW);
		const merged = merge_libraries(local, remote, NOW);
		expect(merged.tools.map((entry) => entry.document.name)).toEqual(["Edited after"]);
		expect(merged.removed).toBeUndefined();
	});
	it("forgets tombstones older than the horizon", () => {
		const stale = delete_tool(upsert_tool(empty_library, doc("a"), NOW), "a", NOW - (TOMBSTONE_DAYS + 1) * 86_400_000);
		expect(merge_libraries(stale, empty_library, NOW).removed).toBeUndefined();
	});
	it("is stable: merging twice changes nothing", () => {
		const local = upsert_tool(upsert_tool(empty_library, doc("a"), NOW), doc("b"), NOW - MINUTE);
		const remote = delete_tool(upsert_tool(empty_library, doc("c"), NOW), "b", NOW);
		const once = merge_libraries(local, remote, NOW);
		expect(same_library(merge_libraries(once, remote, NOW), once)).toBe(true);
		expect(same_library(merge_libraries(once, once, NOW), once)).toBe(true);
	});
	it("compares libraries regardless of order", () => {
		const one: Library = upsert_tool(upsert_tool(empty_library, doc("a"), NOW), doc("b"), NOW);
		const two: Library = upsert_tool(upsert_tool(empty_library, doc("b"), NOW), doc("a"), NOW);
		expect(same_library(one, two)).toBe(true);
		expect(same_library(one, upsert_tool(one, doc("c"), NOW))).toBe(false);
	});
});
