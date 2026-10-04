import { describe, expect, it } from "vitest";
import { starter_document, type AppDocument } from "../lib/document";
import { delete_tool, empty_library, upsert_tool, type Library } from "../lib/library";
import { adopt_guest_pages, merge_libraries, same_library, TOMBSTONE_DAYS } from "../lib/sync";

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

it("keeps a newer empty group list instead of resurrecting deleted groups", () => {
	const local: Library = { ...empty_library, groups: [{ id: "social", name: "Social" }], groups_updated_at: "2026-09-12T10:00:00.000Z" };
	const remote: Library = { ...empty_library, groups: [], groups_updated_at: "2026-09-12T11:00:00.000Z" };
	expect(merge_libraries(local, remote, NOW).groups).toEqual([]);
	expect(merge_libraries(remote, local, NOW).groups).toEqual([]);
});
it("deleting in the same millisecond does not resurrect the routine", () => {
	const local = upsert_tool(empty_library, doc("a"), NOW);
	expect(merge_libraries(local, delete_tool(local, "a", NOW), NOW).tools).toEqual([]);
});

describe("syncing each group's app choices", () => {
	const base: Library = { schema_version: 1, tools: [], groups_updated_at: "2026-09-12T10:00:00.000Z", groups: [{ id: "social", name: "Social" }, { id: "games", name: "Games" }] };
	it("keeps the newest app choices per group even when the other device's group list wins", () => {
		const phone: Library = { ...base, groups: [{ id: "social", name: "Social", apps: "cGhvbmU=", apps_updated_at: "2026-09-12T11:00:00.000Z" }, { id: "games", name: "Games" }] };
		const tablet: Library = { ...base, groups_updated_at: "2026-09-12T11:30:00.000Z", groups: [{ id: "social", name: "Social media" }, { id: "games", name: "Games", apps: "dGFibGV0", apps_updated_at: "2026-09-12T11:10:00.000Z" }] };
		const merged = merge_libraries(phone, tablet, NOW);
		expect(merged.groups).toEqual([
			{ id: "social", name: "Social media", apps: "cGhvbmU=", apps_updated_at: "2026-09-12T11:00:00.000Z" },
			{ id: "games", name: "Games", apps: "dGFibGV0", apps_updated_at: "2026-09-12T11:10:00.000Z" },
		]);
		expect(same_library(merge_libraries(merged, phone, NOW), merged)).toBe(true);
	});
	it("takes the later choice when both devices picked apps for the same group", () => {
		const older: Library = { ...base, groups: [{ id: "social", name: "Social", apps: "b2xk", apps_updated_at: "2026-09-12T11:00:00.000Z" }] };
		const newer: Library = { ...base, groups: [{ id: "social", name: "Social", apps: "bmV3", apps_updated_at: "2026-09-12T11:05:00.000Z" }] };
		expect(merge_libraries(older, newer, NOW).groups?.[0].apps).toBe("bmV3");
		expect(merge_libraries(newer, older, NOW).groups?.[0].apps).toBe("bmV3");
	});
});

describe("bug hunt, October 4", () => {
	const v3 = (id: string) => ({ ...doc(id), schema_version: 3, behaviors: { nodes: [], connections: [] } }) as unknown as AppDocument;
	it("does not revert a page whose format went down on another device", () => {
		const web: Library = { schema_version: 1, tools: [{ document: v3("a"), updated_at: "2026-10-04T10:00:00.000Z" }] };
		const phone: Library = { schema_version: 1, tools: [{ document: doc("a"), updated_at: "2026-10-04T10:01:00.000Z" }] };
		expect(merge_libraries(web, phone, NOW).tools[0].document.schema_version).toBe(1);
		expect(merge_libraries(phone, web, NOW).tools[0].document.schema_version).toBe(1);
	});
	it("treats the same library with different key order as unchanged", () => {
		const left: Library = { schema_version: 1, tools: [], removed: { b: "2026-10-04T10:00:00.000Z", a: "2026-10-04T09:00:00.000Z" } };
		const right = JSON.parse('{"removed":{"a":"2026-10-04T09:00:00.000Z","b":"2026-10-04T10:00:00.000Z"},"tools":[],"schema_version":1}') as Library;
		expect(same_library(left, right)).toBe(true);
	});
	it("keeps a group that a merged page still names when the other device's group list wins", () => {
		const games_page = { ...doc("games-page"), blocks: doc("games-page").blocks.map((block) => block.type === "screen_time" ? { ...block, groups: ["Games"] } : block) } as AppDocument;
		const web: Library = { schema_version: 1, tools: [{ document: games_page, updated_at: "2026-10-04T10:00:00.000Z" }], groups_updated_at: "2026-10-04T10:00:00.000Z", groups: [{ id: "games", name: "Games" }] };
		const phone: Library = { schema_version: 1, tools: [], groups_updated_at: "2026-10-04T10:05:00.000Z", groups: [{ id: "social", name: "Social" }] };
		expect(merge_libraries(web, phone, NOW).groups?.map((group) => group.name).sort()).toEqual(["Games", "Social"]);
	});
	it("adopts pages made while signed out, up to the limit, and leaves the rest", () => {
		const account: Library = { schema_version: 1, tools: [{ document: doc("a"), updated_at: "2026-10-04T09:00:00.000Z" }, { document: doc("b"), updated_at: "2026-10-04T09:00:00.000Z" }] };
		const guest: Library = { schema_version: 1, tools: [{ document: doc("c"), updated_at: "2026-10-04T10:00:00.000Z" }, { document: doc("d"), updated_at: "2026-10-04T09:30:00.000Z" }] };
		const { library, leftover } = adopt_guest_pages(account, guest, 3, NOW);
		expect(library.tools.map((entry) => entry.document.id).sort()).toEqual(["a", "b", "c"]);
		expect(leftover.tools.map((entry) => entry.document.id)).toEqual(["d"]);
	});
});
