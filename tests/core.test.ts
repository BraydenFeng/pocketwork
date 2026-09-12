import { describe, expect, it } from "vitest";
import { document_schema, move_block, parse_document, remove_block, serialize_document, starter_document, type AppDocument } from "../lib/document";
import { change, redo, undo } from "../lib/history";
import { format_duration, initial_runtime, remaining_seconds, transition } from "../lib/runtime";
import { load_draft, save_draft } from "../lib/storage";
import fixture from "../public/starter.pocketwork.json";

function copy(): AppDocument { return structuredClone(starter_document); }

describe("versioned configuration boundary", () => {
	it("keeps the native bundled fixture identical to the editor starter", () => { expect(parse_document(JSON.stringify(fixture))).toEqual(starter_document); });
	it("round trips the sample without executable code", () => { expect(parse_document(serialize_document(copy()))).toEqual(starter_document); });
	it.each(["javascript:alert(1)", "{", "null", "[]"])("rejects non-documents: %s", (text) => { expect(() => parse_document(text)).toThrow(); });
	it("rejects oversized files before parsing", () => { expect(() => parse_document(" ".repeat(100_001))).toThrow("too large"); });
	it("rejects unsupported schema versions", () => { expect(document_schema.safeParse({ ...copy(), schema_version: 2 }).success).toBe(false); });
	it("rejects unknown fields instead of accepting scripts", () => { expect(document_schema.safeParse({ ...copy(), script: "alert(1)" }).success).toBe(false); });
	it("rejects duplicate identifiers, including task IDs", () => {
		const doc = copy(); if (doc.blocks[2].type === "checklist") { doc.blocks[2].items[0].id = "focus"; }
		expect(document_schema.safeParse(doc).success).toBe(false);
	});
	it("rejects intervals shorter than DeviceActivity supports", () => {
		const doc = copy(); if (doc.blocks[1].type === "timer") { doc.blocks[1].minutes = 5; }
		expect(document_schema.safeParse(doc).success).toBe(false);
	});
	it("rejects rules missing required blocks", () => { expect(document_schema.safeParse({ ...copy(), blocks: [copy().blocks[0]] }).success).toBe(false); });
	it("rejects two session timers", () => {
		const doc = copy(); doc.blocks.push({ id: "second", type: "timer", title: "Second timer", minutes: 25 });
		expect(document_schema.safeParse(doc).success).toBe(false);
	});
	it("deleting a timer disables its dependent rules", () => {
		const doc = remove_block(copy(), "focus");
		expect(doc.rules).toEqual({ block_during_focus: false, notify_on_complete: false });
		expect(document_schema.safeParse(doc).success).toBe(true);
	});
	it("keeps the final block and ignores out-of-bounds moves", () => {
		const doc = { ...copy(), blocks: [copy().blocks[0]], rules: { block_during_focus: false, notify_on_complete: false } };
		expect(remove_block(doc, "welcome")).toBe(doc); expect(move_block(doc, "missing", 1)).toBe(doc); expect(move_block(doc, "welcome", -1)).toBe(doc);
	});
	it("reorders without changing the original", () => {
		const doc = copy(); const moved = move_block(doc, "focus", -1);
		expect(moved.blocks[0].id).toBe("focus"); expect(doc.blocks[0].id).toBe("welcome");
	});
});

describe("session runner", () => {
	it("uses an absolute deadline, surviving a suspended browser", () => {
		const state = transition(copy(), initial_runtime(), { type: "start", now: 1000 });
		expect(remaining_seconds(copy(), state, 11_000)).toBe(1490);
		const finished = transition(copy(), state, { type: "tick", now: 9_000_000 });
		expect(finished.status).toBe("completed"); expect(finished.events.at(-1)?.message).toContain("notification simulated");
		expect(transition(copy(), finished, { type: "tick", now: 9_000_001 })).toBe(finished);
	});
	it("ignores repeated starts and early ticks", () => {
		const state = transition(copy(), initial_runtime(), { type: "start", now: 1000 });
		expect(transition(copy(), state, { type: "start", now: 5000 })).toBe(state); expect(transition(copy(), state, { type: "tick", now: 5000 })).toBe(state);
	});
	it("stops without emitting a completion notification", () => {
		const state = transition(copy(), initial_runtime(), { type: "start", now: 1000 });
		const stopped = transition(copy(), state, { type: "stop", now: 2000 });
		expect(stopped.status).toBe("idle"); expect(stopped.ends_at).toBeNull(); expect(stopped.events.at(-1)?.message).not.toContain("notification");
	});
	it("handles task toggles and rejects unknown tasks", () => {
		const state = transition(copy(), initial_runtime(), { type: "toggle_task", task_id: "task-one", now: 0 });
		expect(state.completed_tasks).toEqual(["task-one"]); expect(transition(copy(), state, { type: "toggle_task", task_id: "missing", now: 0 })).toBe(state);
		expect(transition(copy(), state, { type: "toggle_task", task_id: "task-one", now: 0 }).completed_tasks).toEqual([]);
	});
	it("caps counters at their configured target", () => {
		const doc = copy(); doc.blocks.push({ id: "count", type: "counter", title: "Count", target: 1 });
		const state = transition(doc, initial_runtime(), { type: "increment", block_id: "count", now: 0 });
		expect(transition(doc, state, { type: "increment", block_id: "count", now: 0 }).counters.count).toBe(1);
	});
	it("formats timer values", () => { expect(format_duration(1500)).toBe("25:00"); expect(format_duration(9)).toBe("00:09"); });
});

describe("editing and persistence", () => {
	it("undoes, redoes, and drops redo after a new change", () => {
		const first = { past: [] as number[], present: 1, future: [] as number[] }; const second = change(first, 2);
		expect(undo(second).present).toBe(1); expect(redo(undo(second)).present).toBe(2); expect(change(undo(second), 3).future).toEqual([]);
	});
	it("bounds undo memory", () => {
		let history = { past: [] as number[], present: 0, future: [] as number[] };
		for (let value = 1; value < 100; value++) { history = change(history, value); } expect(history.past).toHaveLength(60);
	});
	it("loads an empty browser and a stored draft", () => {
		expect(load_draft({ getItem: () => null, setItem: () => {} })).toBeNull();
		expect(load_draft({ getItem: () => serialize_document(copy()), setItem: () => {} })).toEqual(copy());
	});
	it("does not overwrite a corrupt draft", () => {
		let writes = 0; expect(() => load_draft({ getItem: () => "broken", setItem: () => { writes++; } })).toThrow("not been overwritten"); expect(writes).toBe(0);
	});
	it("surfaces storage quota failures", () => { expect(() => save_draft({ getItem: () => null, setItem: () => { throw new Error("Quota exceeded"); } }, copy())).toThrow("Export a backup"); });
});
