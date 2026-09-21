import { expect, it } from "vitest";
import { assert_page_limit, plan_active } from "../lib/page-plan";
import { blank_tool } from "../lib/templates";
import type { Library } from "../lib/library";
function library(ids: string[]): Library { return { schema_version: 1, tools: ids.map(id => ({ document: { ...blank_tool(), id }, updated_at: new Date().toISOString() })) }; }
it("allows three free pages and blocks a fourth", () => {
	expect(() => assert_page_limit(library(["a", "b"]), library(["a", "b", "c"]), false)).not.toThrow();
	expect(() => assert_page_limit(library(["a", "b", "c"]), library(["a", "b", "c", "d"]), false)).toThrow("3 pages");
});
it("keeps existing over-limit pages editable after cancellation", () => {
	const old = library(["a", "b", "c", "d"]);
	expect(() => assert_page_limit(old, { ...old, tools: old.tools.map(entry => ({ ...entry, document: { ...entry.document, name: "Edited" } })) }, false)).not.toThrow();
	expect(() => assert_page_limit(old, library(["a", "b", "c"]), false)).not.toThrow();
	expect(() => assert_page_limit(old, library(["a", "b", "c", "e"]), false)).toThrow();
});
it("reuses a free slot after deletion and permits verified Pro", () => {
	expect(() => assert_page_limit(library(["a", "b", "c"]), library(["a", "b", "d"]), false)).not.toThrow();
	expect(() => assert_page_limit(library(["a", "b", "c"]), library(["a", "b", "c", "d"]), true)).not.toThrow();
	expect(plan_active({ pro: true, expires_at: new Date(1000).toISOString(), configured: true }, 1000)).toBe(false);
});
