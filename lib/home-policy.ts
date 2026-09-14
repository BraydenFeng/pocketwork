import { z } from "zod";

const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
export const home_policy_schema = z.object({
	timezone: z.literal("America/Los_Angeles"),
	away_usage_counts: z.literal(false),
	// "unrestricted": outside the windows nothing is blocked (the default). "block_at_home": the older behavior, kept only for documents that chose it on purpose.
	outside_windows: z.enum(["unrestricted", "block_at_home"]),
	rules: z.array(z.object({
		days: z.array(z.number().int().min(1).max(7)).min(1).max(7),
		allowance_minutes: z.number().int().min(1).max(180),
		windows: z.array(z.object({ start: time, end: time }).strict()).min(1).max(2),
	}).strict()).min(1).max(7),
}).strict().superRefine((policy, context) => {
	const days = new Set<number>();
	for (const rule of policy.rules) {
		for (const day of rule.days) { if (days.has(day)) { context.addIssue({ code: "custom", message: "Each day has one shared allowance." }); } days.add(day); }
		let end = "00:00";
		for (const window of rule.windows) {
			if (window.start < end || window.end <= window.start || minutes(window.end) - minutes(window.start) < 15) { context.addIssue({ code: "custom", message: "Windows must be ordered, non-overlapping, and at least 15 minutes long within one day." }); }
			end = window.end;
		}
	}
	if (days.size !== 7) { context.addIssue({ code: "custom", message: "Choose an allowance for all seven days." }); }
});
export type HomePolicy = z.infer<typeof home_policy_schema>;
function minutes(time: string): number { const [h, m] = time.split(":").map(Number); return h * 60 + m; }
export const requested_home_policy: HomePolicy = {
	timezone: "America/Los_Angeles", away_usage_counts: false, outside_windows: "unrestricted",
	rules: [
		{ days: [2, 3, 4, 5], allowance_minutes: 30, windows: [{ start: "18:00", end: "18:30" }, { start: "19:00", end: "20:50" }] },
		{ days: [6], allowance_minutes: 120, windows: [{ start: "14:30", end: "20:20" }] },
		{ days: [1, 7], allowance_minutes: 180, windows: [{ start: "06:30", end: "20:30" }] },
	],
};
export function home_decision(policy: HomePolicy, day: number, time: string, at_home: boolean, consumed: number) {
	const rule = policy.rules.find((rule) => rule.days.includes(day));
	const allowed = Boolean(rule?.windows.some((window) => window.start <= time && time < window.end));
	const exhausted = consumed >= (rule?.allowance_minutes ?? 0);
	// Blocking happens inside a window once the minutes are spent; outside a window only the legacy setting blocks.
	const blocked = at_home && (allowed ? exhausted : policy.outside_windows === "block_at_home");
	return { count_usage: at_home && allowed && !exhausted, blocked, remaining: Math.max(0, (rule?.allowance_minutes ?? 0) - consumed) };
}
