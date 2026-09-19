import { inflateSync } from "node:zlib";
import { describe, expect, it } from "vitest";
import { age_words, render_history_png, status_schema, summarize_status, type StatusReport } from "../lib/status";

const NOW = Date.parse("2026-09-18T19:30:00.000Z");

function report(overrides: Partial<StatusReport> = {}): StatusReport {
	return status_schema.parse({
		schema_version: 1, reported_at: new Date(NOW - 3 * 60_000).toISOString(), timezone: "America/Los_Angeles",
		routines: [
			{ id: "deep", name: "Deep work", kind: "session", enabled: false, running: true, ends_at: new Date(NOW + 40 * 60_000).toISOString() },
			{ id: "home", name: "Home allowance", kind: "allowance", enabled: true, running: false },
			{ id: "bed", name: "Phone-free bedtime", kind: "standing", enabled: false, running: false },
		],
		allowance: { routine_id: "home", day: "2026-9-18", budget_minutes: 30, used_minutes: 8, remaining_minutes: 22, at_home: true, in_window: true, window_ends: "20:50" },
		history: Array.from({ length: 14 }, (_, index) => ({ day: `2026-09-${(5 + index).toString().padStart(2, "0")}`, allowance_used: index * 2, allowance_budget: 30, session_minutes: index % 3 === 0 ? 50 : 0, sessions: index % 3 === 0 ? 2 : 0 })),
		...overrides,
	});
}

describe("phone status", () => {
	it("rejects anything that is not the agreed shape", () => {
		expect(status_schema.safeParse({ ...report(), extra: true }).success).toBe(false);
		expect(status_schema.safeParse({ ...report(), allowance: { ...report().allowance, window_ends: "8pm" } }).success).toBe(false);
		expect(status_schema.safeParse({ ...report(), schema_version: 2 }).success).toBe(false);
	});
	it("reads as one honest paragraph", () => {
		const words = summarize_status(report(), NOW);
		expect(words).toContain("Deep work is running until");
		expect(words).toContain("22 of 30 minutes left today, at home, window ends 8:50 PM");
		expect(words).toContain("Switched on: Home allowance.");
		expect(words).toContain("focus minutes over the last 7 days");
		expect(words).toContain("Reported by the phone 3 min ago.");
		const closed = summarize_status(report({ allowance: { ...report().allowance!, in_window: false, window_ends: undefined, next_window: "19:00" } }), NOW);
		expect(closed).toContain("next window opens 7 PM");
		expect(age_words(new Date(NOW - 26 * 3_600_000).toISOString(), NOW)).toBe("1 days ago");
	});
	it("draws a valid PNG of the last two weeks", () => {
		const { png, caption } = render_history_png(report());
		expect(png.subarray(0, 8)).toEqual(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
		expect(png.subarray(12, 16).toString("ascii")).toBe("IHDR");
		expect(png.readUInt32BE(16)).toBe(560); expect(png.readUInt32BE(20)).toBe(200);
		const idat_length = png.readUInt32BE(33); expect(png.subarray(37, 41).toString("ascii")).toBe("IDAT");
		const raw = inflateSync(png.subarray(41, 41 + idat_length));
		expect(raw.length).toBe((560 * 3 + 1) * 200);
		expect(caption).toContain("2026-09-05 to 2026-09-18");
		expect(render_history_png(report({ history: [] })).caption).toBe("No history yet.");
	});
});
