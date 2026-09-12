import { describe, expect, it } from "vitest";
import { create_block, document_schema, is_standing, remove_block, starter_document, type AppDocument } from "../lib/document";
import { describe_schedule, describe_status, format_clock, format_days, schedule_status, type ScheduleBlock } from "../lib/schedule";
import { summarize_tool } from "../lib/library";

// Wednesday 2026-09-16, 20:30 local time. Tests use local-time constructors so they hold in any zone.
const wednesday_evening = new Date(2026, 8, 16, 20, 30).getTime();
const nightly: ScheduleBlock = { id: "window", type: "schedule", title: "Every night", days: [1, 2, 3, 4, 5, 6, 7], start: "22:00", end: "07:00" };
const weekdays: ScheduleBlock = { id: "window", type: "schedule", title: "Weekdays", days: [2, 3, 4, 5, 6], start: "09:00", end: "17:00" };

function standing(overrides: Partial<AppDocument> = {}): AppDocument {
	return { schema_version: 1, id: "bedtime", name: "Bedtime", description: "", enabled: false,
		blocks: [{ id: "heading", type: "heading", title: "Night", subtitle: "" }, nightly, { id: "shield", type: "screen_time", title: "Feeds off" }],
		rules: { block_during_focus: true, notify_on_complete: false }, ...overrides };
}

describe("standing routine validation", () => {
	it("accepts a scheduled routine that locks apps", () => { expect(document_schema.safeParse(standing()).success).toBe(true); expect(is_standing(standing())).toBe(true); });
	it("refuses a schedule next to a timer", () => {
		const document = standing({ blocks: [...standing().blocks, { id: "timer", type: "timer", title: "Focus", minutes: 25 }] });
		expect(document_schema.safeParse(document).error?.issues[0].message).toContain("not both");
	});
	it("refuses a schedule with nothing to enforce", () => {
		expect(document_schema.safeParse(standing({ rules: { block_during_focus: false, notify_on_complete: false } })).success).toBe(false);
		expect(document_schema.safeParse(standing({ blocks: standing().blocks.filter((block) => block.type !== "screen_time") })).success).toBe(false);
	});
	it("refuses bad windows and stray switches", () => {
		expect(document_schema.safeParse(standing({ blocks: [{ ...nightly, start: "22:00", end: "22:00" }, standing().blocks[2]] })).success).toBe(false);
		expect(document_schema.safeParse(standing({ blocks: [{ ...nightly, days: [2, 2] }, standing().blocks[2]] })).success).toBe(false);
		expect(document_schema.safeParse(standing({ blocks: [{ ...nightly, start: "25:00" }, standing().blocks[2]] })).success).toBe(false);
		expect(document_schema.safeParse(standing({ blocks: [{ ...nightly, start: "22:00", end: "22:10" }, standing().blocks[2]] })).error?.issues[0].message).toContain("15 minutes");
		expect(document_schema.safeParse(standing({ blocks: [{ ...nightly, start: "23:50", end: "00:05" }, standing().blocks[2]] })).success).toBe(true);
		expect(document_schema.safeParse({ ...starter_document, enabled: true }).success).toBe(false);
	});
	it("removing the schedule drops the switch and the blocking rule", () => {
		const document = remove_block(standing({ enabled: true }), "window");
		expect(document.enabled).toBeUndefined();
		expect(document.rules.block_during_focus).toBe(false);
		expect(document_schema.safeParse(document).success).toBe(true);
	});
	it("creates a sensible default schedule block", () => {
		const block = create_block("schedule");
		expect(block.type).toBe("schedule");
		if (block.type === "schedule") { expect(block.days).toHaveLength(7); expect(block.start).toBe("22:00"); }
	});
});

describe("schedule windows", () => {
	it("knows when a nightly window is open, including past midnight", () => {
		expect(schedule_status(nightly, wednesday_evening).active).toBe(false);
		const late = new Date(2026, 8, 16, 23, 0).getTime();
		expect(schedule_status(nightly, late)).toEqual({ active: true, change_at: new Date(2026, 8, 17, 7, 0).getTime() });
		const early = new Date(2026, 8, 17, 6, 59).getTime();
		expect(schedule_status(nightly, early).active).toBe(true);
		expect(schedule_status(nightly, new Date(2026, 8, 17, 7, 0).getTime()).active).toBe(false);
	});
	it("reports the next start when closed", () => {
		expect(schedule_status(nightly, wednesday_evening).change_at).toBe(new Date(2026, 8, 16, 22, 0).getTime());
		const friday_night = new Date(2026, 8, 18, 18, 0).getTime();
		expect(schedule_status(weekdays, friday_night).change_at).toBe(new Date(2026, 8, 21, 9, 0).getTime());
	});
	it("respects the chosen days", () => {
		const saturday_noon = new Date(2026, 8, 19, 12, 0).getTime();
		expect(schedule_status(weekdays, saturday_noon).active).toBe(false);
		const wednesday_noon = new Date(2026, 8, 16, 12, 0).getTime();
		expect(schedule_status(weekdays, wednesday_noon).active).toBe(true);
	});
	it("describes windows and status in plain words", () => {
		expect(format_days([1, 2, 3, 4, 5, 6, 7])).toBe("Every day");
		expect(format_days([2, 3, 4, 5, 6])).toBe("Weekdays");
		expect(format_days([7, 1])).toBe("Weekends");
		expect(format_days([2, 4])).toBe("Mon, Wed");
		expect(format_clock("22:00")).toBe("10 PM");
		expect(format_clock("09:30")).toBe("9:30 AM");
		expect(describe_schedule(nightly)).toBe("Every day · 10 PM to 7 AM");
		expect(describe_status(nightly, false, wednesday_evening)).toBe("Off · switch it on to start enforcing");
		expect(describe_status(nightly, true, wednesday_evening)).toBe("On · next 10 PM");
		expect(describe_status(nightly, true, new Date(2026, 8, 16, 23, 0).getTime())).toBe("Active now · until tomorrow 7 AM");
		expect(describe_status(weekdays, true, new Date(2026, 8, 18, 18, 0).getTime())).toBe("On · next Mon 9 AM");
		expect(summarize_tool(standing())).toBe("Every day · 10 PM to 7 AM · blocks apps");
	});
});
