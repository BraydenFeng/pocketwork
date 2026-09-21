import { deflateSync } from "node:zlib";
import { z } from "zod";
import type { Account, Cloud } from "./cloud";

// What the phone shares when the person opts in. Mirrors StatusReport in ios/Shared/StatusReport.swift.
const clock = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
export const status_schema = z.object({
	schema_version: z.literal(1),
	reported_at: z.string().datetime(),
	timezone: z.string().min(1).max(64),
	routines: z.array(z.object({
		id: z.string(), name: z.string(), kind: z.enum(["session", "standing", "allowance"]), enabled: z.boolean(), running: z.boolean(), ends_at: z.string().datetime().optional(),
	}).strict()).max(50),
	allowance: z.object({
		routine_id: z.string(), day: z.string(), budget_minutes: z.number().int().min(0), used_minutes: z.number().int().min(0), remaining_minutes: z.number().int().min(0),
		at_home: z.boolean(), in_window: z.boolean(), window_ends: clock.optional(), next_window: clock.optional(),
	}).strict().optional(),
	history: z.array(z.object({
		day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), allowance_used: z.number().int().min(0).optional(), allowance_budget: z.number().int().min(0).optional(), session_minutes: z.number().int().min(0), sessions: z.number().int().min(0),
	}).strict()).max(60),
}).strict();
export type StatusReport = z.infer<typeof status_schema>;

export async function fetch_status(cloud: Cloud, account: Account): Promise<{ status: StatusReport; updated_at: string } | null> {
	const { data, error } = await cloud.client.from("routine_status").select("status,updated_at").eq("user_id", account.id).maybeSingle();
	if (error) {
		// The table is created by supabase/schema.sql; a project without it simply has no status yet.
		if (/routine_status/.test(error.message) && /not exist|schema cache/i.test(error.message)) { return null; }
		throw new Error(`Could not read your phone's status. ${error.message}`);
	}
	if (!data) { return null; }
	const parsed = status_schema.safeParse(data.status);
	if (!parsed.success) { throw new Error(`Your phone's status could not be read. ${parsed.error.issues[0].message}`); }
	return { status: parsed.data, updated_at: data.updated_at };
}

function clock_words(value: string): string {
	const [hours, minutes] = value.split(":").map(Number);
	const suffix = hours >= 12 ? "PM" : "AM";
	const twelve = hours % 12 === 0 ? 12 : hours % 12;
	return minutes === 0 ? `${twelve} ${suffix}` : `${twelve}:${minutes.toString().padStart(2, "0")} ${suffix}`;
}

export function age_words(reported_at: string, now: number): string {
	const minutes = Math.max(0, Math.round((now - Date.parse(reported_at)) / 60_000));
	if (minutes < 1) { return "just now"; }
	if (minutes < 60) { return `${minutes} min ago`; }
	const hours = Math.floor(minutes / 60);
	if (hours < 24) { return `${hours} hr ago`; }
	return `${Math.floor(hours / 24)} days ago`;
}

// One paragraph a person or an agent can read without the numbers.
export function summarize_status(report: StatusReport, now: number): string {
	const lines: string[] = [];
	const running = report.routines.find((routine) => routine.running);
	if (running?.ends_at) { lines.push(`${running.name} is running until ${new Date(running.ends_at).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}.`); }
	if (report.allowance) {
		const a = report.allowance;
		const where = a.at_home ? "at home" : "away from home";
		if (a.in_window) { lines.push(`Home allowance: ${a.remaining_minutes} of ${a.budget_minutes} minutes left today, ${where}, window ends ${clock_words(a.window_ends!)}.`); }
		else if (a.next_window) { lines.push(`Home allowance: ${a.remaining_minutes} of ${a.budget_minutes} minutes left today, ${where}; next window opens ${clock_words(a.next_window)}.`); }
		else { lines.push(`Home allowance: ${a.remaining_minutes} of ${a.budget_minutes} minutes left today, ${where}; no more windows today.`); }
	}
	const standing = report.routines.filter((routine) => routine.kind !== "session");
	const on = standing.filter((routine) => routine.enabled).map((routine) => routine.name);
	if (standing.length) { lines.push(on.length ? `Switched on: ${on.join(", ")}.` : "No standing routines are switched on."); }
	const week = report.history.slice(-7);
	const focus = week.reduce((total, day) => total + day.session_minutes, 0);
	if (focus) { lines.push(`${focus} focus minutes over the last ${week.length} days.`); }
	lines.push(`Reported by the phone ${age_words(report.reported_at, now)}.`);
	return lines.join(" ");
}

// A small PNG bar chart of the last 14 days: allowance used against budget (or focus minutes when there is no allowance).
// Drawn pixel by pixel so it needs no native image library; labels travel in the text next to it.
export function render_history_png(report: StatusReport): { png: Buffer; caption: string } {
	const days = report.history.slice(-14);
	const has_allowance = days.some((day) => day.allowance_budget !== undefined);
	const values = days.map((day) => has_allowance ? (day.allowance_used ?? 0) : day.session_minutes);
	const budgets = days.map((day) => has_allowance ? (day.allowance_budget ?? 0) : 0);
	const peak = Math.max(1, ...values, ...budgets);
	const width = 560, height = 200, left = 16, bottom = 16, top = 16;
	const plot_h = height - top - bottom;
	const slot = (width - left * 2) / Math.max(1, days.length);
	const canvas = new Uint8Array(width * height * 3).fill(0xfc);
	const fill = (x0: number, y0: number, x1: number, y1: number, rgb: [number, number, number]) => {
		for (let y = Math.max(0, y0 | 0); y < Math.min(height, y1 | 0); y++) {
			for (let x = Math.max(0, x0 | 0); x < Math.min(width, x1 | 0); x++) { const at = (y * width + x) * 3; canvas[at] = rgb[0]; canvas[at + 1] = rgb[1]; canvas[at + 2] = rgb[2]; }
		}
	};
	fill(left, height - bottom, width - left, height - bottom + 1, [0xd9, 0xdb, 0xe2]);
	days.forEach((_, index) => {
		const x = left + index * slot + slot * 0.2, w = slot * 0.6;
		if (budgets[index]) { fill(x, height - bottom - (budgets[index] / peak) * plot_h, x + w, height - bottom, [0xe6, 0xe8, 0xef]); }
		if (values[index]) {
			const over = budgets[index] && values[index] >= budgets[index];
			fill(x, height - bottom - (values[index] / peak) * plot_h, x + w, height - bottom, over ? [0xa7, 0x32, 0x28] : [0x25, 0x5f, 0xb3]);
		}
	});
	const caption = days.length
		? `${has_allowance ? "Home allowance minutes used (dark) against budget (light)" : "Focus minutes"} per day, ${days[0].day} to ${days[days.length - 1].day}, peak ${peak} min.`
		: "No history yet.";
	return { png: encode_png(width, height, canvas), caption };
}

function crc32(bytes: Uint8Array): number {
	let crc = ~0;
	for (const byte of bytes) { crc ^= byte; for (let bit = 0; bit < 8; bit++) { crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1)); } }
	return ~crc >>> 0;
}

function chunk(type: string, data: Uint8Array): Buffer {
	const length = Buffer.alloc(4); length.writeUInt32BE(data.length);
	const body = Buffer.concat([Buffer.from(type, "ascii"), Buffer.from(data)]);
	const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body));
	return Buffer.concat([length, body, crc]);
}

function encode_png(width: number, height: number, rgb: Uint8Array): Buffer {
	const raw = Buffer.alloc((width * 3 + 1) * height);
	for (let y = 0; y < height; y++) { raw[y * (width * 3 + 1)] = 0; rgb.subarray(y * width * 3, (y + 1) * width * 3).forEach((value, index) => { raw[y * (width * 3 + 1) + 1 + index] = value; }); }
	const header = Buffer.alloc(13); header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4); header[8] = 8; header[9] = 2; header[10] = 0; header[11] = 0; header[12] = 0;
	return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk("IHDR", header), chunk("IDAT", deflateSync(raw)), chunk("IEND", new Uint8Array())]);
}
