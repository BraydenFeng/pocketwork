import type { Block } from "./document";

export type ScheduleBlock = Extract<Block, { type: "schedule" }>;
export type ScheduleStatus = { active: boolean; change_at: number };

// 1 = Sunday … 7 = Saturday, matching Calendar.weekday on iOS.
export const DAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
export const WEEKDAYS = [2, 3, 4, 5, 6];
export const ALL_DAYS = [1, 2, 3, 4, 5, 6, 7];

function minutes_of(clock: string): number {
	const [hours, minutes] = clock.split(":").map(Number);
	return hours * 60 + minutes;
}

function at_minutes(day_start: Date, minutes: number): number {
	const stamp = new Date(day_start);
	stamp.setHours(Math.floor(minutes / 60), minutes % 60, 0, 0);
	return stamp.getTime();
}

function start_of_day(now: number, offset_days: number): Date {
	const day = new Date(now);
	day.setHours(0, 0, 0, 0);
	day.setDate(day.getDate() + offset_days);
	return day;
}

// A window belongs to the day it starts on. Ending earlier than it starts means it runs past midnight into the next day.
export function schedule_status(schedule: ScheduleBlock, now: number): ScheduleStatus {
	const start = minutes_of(schedule.start);
	const end = minutes_of(schedule.end);
	const length = end > start ? end - start : 24 * 60 - start + end;
	let next_start = Number.POSITIVE_INFINITY;
	for (let offset = -1; offset <= 7; offset++) {
		const day = start_of_day(now, offset);
		if (!schedule.days.includes(day.getDay() + 1)) { continue; }
		const window_start = at_minutes(day, start);
		const window_end = window_start + length * 60_000;
		if (now >= window_start && now < window_end) { return { active: true, change_at: window_end }; }
		if (window_start > now) { next_start = Math.min(next_start, window_start); }
	}
	return { active: false, change_at: next_start };
}

export function format_clock(clock: string): string {
	const [hours, minutes] = clock.split(":").map(Number);
	const suffix = hours >= 12 ? "PM" : "AM";
	const twelve = hours % 12 === 0 ? 12 : hours % 12;
	return minutes === 0 ? `${twelve} ${suffix}` : `${twelve}:${minutes.toString().padStart(2, "0")} ${suffix}`;
}

export function format_days(days: number[]): string {
	const sorted = [...new Set(days)].sort((left, right) => left - right);
	if (sorted.length === 7) { return "Every day"; }
	if (sorted.length === 5 && WEEKDAYS.every((day) => sorted.includes(day))) { return "Weekdays"; }
	if (sorted.length === 2 && sorted.includes(1) && sorted.includes(7)) { return "Weekends"; }
	return sorted.map((day) => DAY_LABELS[day - 1]).join(", ");
}

export function describe_schedule(schedule: ScheduleBlock): string {
	return `${format_days(schedule.days)} · ${format_clock(schedule.start)} to ${format_clock(schedule.end)}`;
}

// What the person sees on the routine card and in the preview.
export function describe_status(schedule: ScheduleBlock, enabled: boolean, now: number): string {
	if (!enabled) { return "Off · switch it on to start enforcing"; }
	const status = schedule_status(schedule, now);
	if (status.active) { return `Active now · until ${format_time_of(status.change_at, now)}`; }
	if (!Number.isFinite(status.change_at)) { return "On · waiting for a scheduled day"; }
	return `On · next ${format_time_of(status.change_at, now)}`;
}

function format_time_of(stamp: number, now: number): string {
	const date = new Date(stamp);
	const clock = format_clock(`${date.getHours().toString().padStart(2, "0")}:${date.getMinutes().toString().padStart(2, "0")}`);
	const today = start_of_day(now, 0).getTime();
	const tomorrow = start_of_day(now, 1).getTime();
	if (stamp >= today && stamp < tomorrow) { return clock; }
	if (stamp >= tomorrow && stamp < start_of_day(now, 2).getTime()) { return `tomorrow ${clock}`; }
	return `${DAY_LABELS[date.getDay()]} ${clock}`;
}
