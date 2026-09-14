import { describe, expect, it } from "vitest";
import { home_decision, home_policy_schema, requested_home_policy } from "../lib/home-policy";
import { personal_routine } from "../lib/personal-routine";
import { document_schema } from "../lib/document";

describe("personal home allowance", () => {
	it("matches every requested day and time", () => {
		expect(home_policy_schema.parse(requested_home_policy).rules).toEqual([
			{ days: [2, 3, 4, 5], allowance_minutes: 30, windows: [{ start: "18:00", end: "18:30" }, { start: "19:00", end: "20:50" }] },
			{ days: [6], allowance_minutes: 120, windows: [{ start: "14:30", end: "20:20" }] },
			{ days: [1, 7], allowance_minutes: 180, windows: [{ start: "06:30", end: "20:30" }] },
		]);
	});
	it("shares thirty minutes across both weekday windows", () => {
		expect(home_decision(requested_home_policy, 2, "18:10", true, 20).remaining).toBe(10);
		expect(home_decision(requested_home_policy, 2, "18:45", true, 20)).toMatchObject({ blocked: false, count_usage: false, remaining: 10 });
		expect(home_decision(requested_home_policy, 2, "19:15", true, 20)).toMatchObject({ blocked: false, count_usage: true, remaining: 10 });
		expect(home_decision(requested_home_policy, 2, "19:15", true, 30).blocked).toBe(true);
	});
	it("away usage is neither blocked nor charged at any hour", () => {
		for (const time of ["10:00", "18:10", "18:45", "19:15", "23:00"]) { expect(home_decision(requested_home_policy, 2, time, false, 20)).toMatchObject({ blocked: false, count_usage: false, remaining: 10 }); }
	});
	it("uses inclusive starts and exclusive ends", () => {
		expect(home_decision(requested_home_policy, 6, "14:29", true, 0).blocked).toBe(false);
		expect(home_decision({ ...requested_home_policy, outside_windows: "block_at_home" }, 6, "14:29", true, 0).blocked).toBe(true);
		expect(home_decision(requested_home_policy, 6, "14:30", true, 0).blocked).toBe(false);
		expect(home_decision(requested_home_policy, 6, "20:20", true, 0)).toMatchObject({ blocked: false, count_usage: false });
		expect(home_decision(requested_home_policy, 6, "20:19", true, 0).count_usage).toBe(true);
		expect(home_decision(requested_home_policy, 1, "06:30", true, 179).remaining).toBe(1);
	});
	it("requires the new phone format and never seeds an active restriction", () => {
		expect(document_schema.parse(personal_routine).enabled).toBe(false);
		expect(document_schema.safeParse({ ...personal_routine, schema_version: 1 }).success).toBe(false);
	});
	it("rejects overlap and away-time counting", () => {
		expect(home_policy_schema.safeParse({ ...requested_home_policy, away_usage_counts: true }).success).toBe(false);
		const bad = structuredClone(requested_home_policy); bad.rules[0].windows[1].start = "18:20";
		expect(home_policy_schema.safeParse(bad).success).toBe(false);
	});
});
