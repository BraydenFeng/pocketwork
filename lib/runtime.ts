import type { AppDocument } from "./document";

export type RuntimeEvent = { at: number; message: string };
export type RuntimeState = {
	status: "idle" | "running" | "completed";
	ends_at: number | null;
	completed_tasks: string[];
	counters: Record<string, number>;
	events: RuntimeEvent[];
};
export type RuntimeAction =
	| { type: "start" | "stop" | "tick"; now: number }
	| { type: "toggle_task"; task_id: string; now: number }
	| { type: "increment"; block_id: string; now: number };

export function initial_runtime(): RuntimeState {
	return { status: "idle", ends_at: null, completed_tasks: [], counters: {}, events: [] };
}

function log_event(state: RuntimeState, now: number, message: string): RuntimeState {
	return { ...state, events: [...state.events, { at: now, message }].slice(-12) };
}

export function transition(document: AppDocument, state: RuntimeState, action: RuntimeAction): RuntimeState {
	if (!Number.isFinite(action.now)) { return state; }
	switch (action.type) {
		case "start": {
			if (state.status === "running") { return state; }
			const timer = document.blocks.find((block) => block.type === "timer");
			if (!timer) { return state; }
			return log_event({ ...state, status: "running", ends_at: action.now + timer.minutes * 60_000 }, action.now,
				document.rules.block_during_focus ? "Session started · app blocking simulated" : "Session started");
		}
		case "stop":
			if (state.status !== "running") { return state; }
			return log_event({ ...state, status: "idle", ends_at: null }, action.now, "Session stopped · simulated restrictions cleared");
		case "tick":
			if (state.status !== "running" || state.ends_at === null || action.now < state.ends_at) { return state; }
			return log_event({ ...state, status: "completed", ends_at: null }, action.now,
				document.rules.notify_on_complete ? "Session finished · notification simulated · restrictions cleared" : "Session finished · restrictions cleared");
		case "toggle_task": {
			const exists = document.blocks.some((block) => block.type === "checklist" && block.items.some((item) => item.id === action.task_id));
			if (!exists) { return state; }
			return { ...state, completed_tasks: state.completed_tasks.includes(action.task_id)
				? state.completed_tasks.filter((task_id) => task_id !== action.task_id)
				: [...state.completed_tasks, action.task_id] };
		}
		case "increment": {
			const block = document.blocks.find((entry) => entry.id === action.block_id && entry.type === "counter");
			if (!block || block.type !== "counter") { return state; }
			return { ...state, counters: { ...state.counters, [block.id]: Math.min(block.target, (state.counters[block.id] ?? 0) + 1) } };
		}
	}
}

export function remaining_seconds(document: AppDocument, state: RuntimeState, now: number): number {
	if (state.status === "completed") { return 0; }
	if (state.ends_at !== null) { return Math.max(0, Math.ceil((state.ends_at - now) / 1000)); }
	return (document.blocks.find((block) => block.type === "timer")?.minutes ?? 0) * 60;
}

export function format_duration(seconds: number): string {
	return `${Math.floor(seconds / 60).toString().padStart(2, "0")}:${(seconds % 60).toString().padStart(2, "0")}`;
}
