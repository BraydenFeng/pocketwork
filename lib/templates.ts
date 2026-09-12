import { create_block, new_id, type AppDocument } from "./document";

export type Template = { id: string; name: string; tagline: string; build: () => AppDocument };

const focus_rules = { block_during_focus: true, notify_on_complete: true };

// Ready-made routines. Every one is built from the same blocks the editor offers, so "Edit this" never hits a dead end.
export const templates: Template[] = [
	{ id: "deep-work", name: "Deep work", tagline: "90 minutes, apps locked, one task in front of you.", build: () => ({
		schema_version: 1, id: new_id(), name: "Deep work", description: "One long block of real work.",
		blocks: [
			{ id: "heading", type: "heading", title: "One thing, done well.", subtitle: "Everything else can wait ninety minutes." },
			{ id: "timer", type: "timer", title: "Deep work", minutes: 90 },
			{ id: "tasks", type: "checklist", title: "Before you start", items: [{ id: "task-pick", text: "Pick the one task that matters" }, { id: "task-close", text: "Close every other tab" }, { id: "task-phone", text: "Put the phone face down" }] },
			{ id: "shield", type: "screen_time", title: "Distractions stay out" },
		],
		rules: focus_rules,
	}) },
	{ id: "study-sprint", name: "Study sprints", tagline: "45-minute sprints, count them up, phone stays quiet.", build: () => ({
		schema_version: 1, id: new_id(), name: "Study sprints", description: "Short, repeatable rounds of focused study.",
		blocks: [
			{ id: "heading", type: "heading", title: "Sprint, rest, repeat.", subtitle: "Four rounds is a solid session." },
			{ id: "timer", type: "timer", title: "Study sprint", minutes: 45 },
			{ id: "counter", type: "counter", title: "Sprints finished", target: 4 },
			{ id: "shield", type: "screen_time", title: "Nothing but the books" },
		],
		rules: focus_rules,
	}) },
	{ id: "bedtime", name: "Phone-free bedtime", tagline: "An hour of wind-down with the scrolling apps locked.", build: () => ({
		schema_version: 1, id: new_id(), name: "Phone-free bedtime", description: "Wind down without the feed.",
		blocks: [
			{ id: "heading", type: "heading", title: "The day is done.", subtitle: "Nothing on your phone needs you until morning." },
			{ id: "timer", type: "timer", title: "Wind down", minutes: 60 },
			{ id: "tasks", type: "checklist", title: "Before bed", items: [{ id: "task-charge", text: "Phone on the charger, out of reach" }, { id: "task-tomorrow", text: "Write tomorrow's first task" }] },
			{ id: "shield", type: "screen_time", title: "Feeds off for the night" },
		],
		rules: { block_during_focus: true, notify_on_complete: false },
	}) },
	{ id: "morning", name: "Morning start", tagline: "A short checklist and 25 quiet minutes before the phone opens.", build: () => ({
		schema_version: 1, id: new_id(), name: "Morning start", description: "Start the day on your terms, not the feed's.",
		blocks: [
			{ id: "heading", type: "heading", title: "Yours first.", subtitle: "The phone can have you after this." },
			{ id: "tasks", type: "checklist", title: "First things", items: [{ id: "task-water", text: "Drink a glass of water" }, { id: "task-move", text: "Move for five minutes" }, { id: "task-plan", text: "Decide today's one thing" }] },
			{ id: "timer", type: "timer", title: "Quiet start", minutes: 25 },
			{ id: "shield", type: "screen_time", title: "Feeds wait until you're done" },
		],
		rules: focus_rules,
	}) },
	{ id: "reading", name: "Reading time", tagline: "30 minutes with a book and a page counter, apps locked.", build: () => ({
		schema_version: 1, id: new_id(), name: "Reading time", description: "Pages instead of posts.",
		blocks: [
			{ id: "heading", type: "heading", title: "Pages, not posts.", subtitle: "Half an hour is enough to get lost in it." },
			{ id: "timer", type: "timer", title: "Reading", minutes: 30 },
			{ id: "counter", type: "counter", title: "Pages read", target: 20 },
			{ id: "note", type: "note", title: "Worth remembering", text: "Jot one line about what you read." },
			{ id: "shield", type: "screen_time", title: "The feed can wait" },
		],
		rules: focus_rules,
	}) },
];

export function blank_tool(): AppDocument {
	return { schema_version: 1, id: new_id(), name: "My new tool", description: "", blocks: [create_block("heading")], rules: { block_during_focus: false, notify_on_complete: false } };
}
