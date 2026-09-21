import { z } from "zod";
import type { BehaviorContext, BehaviorNode, BehaviorState, Behaviors, Signal } from "./behaviors";

export const primitive_kinds = ["elapsed_timer", "change_value", "time_window", "record"] as const;
export const primitive_config_fields = {
	variable_id: z.string().regex(/^[a-zA-Z0-9_-]{1,64}$/).optional(),
	change: z.enum(["set", "add", "subtract", "reset"]).optional(),
	timer_mode: z.enum(["countdown", "stopwatch"]).optional(),
	end_time: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).optional(),
	unit: z.string().trim().max(24).optional(),
};
export type TimerCommand = { node: string; action: "start" | "pause" | "stop" | "reset" };
export type TimerValue = { elapsed: number; started_at?: number; duration: number; cycle: number; finished: boolean };

export function once_signal(signal: Signal, state: BehaviorState, key: string): boolean {
	if (signal.available === false) { return false; }
	if (!signal.value) { delete state.fired[key]; return false; }
	const rising = state.fired[key] === undefined;
	state.fired[key] = "true";
	const fresh_event = signal.event_token !== undefined && state.fired[`${key}.event`] !== signal.event_token;
	if (signal.event_token !== undefined) { state.fired[`${key}.event`] = signal.event_token; }
	return rising || fresh_event;
}

export function mark_events(node: BehaviorNode, outputs: Record<string, Signal>, input: (port: string) => Signal): void {
	const event_ports: Partial<Record<BehaviorNode["kind"], string>> = {
		button: "pressed", check_in: "done", arrive: "arrived", leave: "left", clock: "due", elapsed_timer: "finished", change_value: "changed",
		delay: "done", reminder: "sent", number_input: "changed", text_input: "changed", checkbox: "changed", form: "submitted", save_entry: "saved", add_allowance: "granted",
	};
	const event_port = event_ports[node.kind];
	if (event_port && outputs[event_port]?.value && outputs[event_port].available !== false) { outputs[event_port].event_token = `${node.id}:${outputs[event_port].token}`; }
	if (["and", "or", "branch"].includes(node.kind)) {
		const output = outputs[node.kind === "branch" ? "yes" : "result"];
		const inputs = node.kind === "branch" ? [input("condition")] : [input("a"), input("b")];
		const events = inputs.filter(signal => signal.value && signal.available !== false && signal.event_token !== undefined).map(signal => signal.event_token);
		if (output?.value && events.length) { output.event_token = JSON.stringify(events); }
	}
}

export function requires_format_four(graph: Behaviors): boolean {
	return graph.nodes.some(node => (primitive_kinds as readonly string[]).includes(node.kind) || node.config.unit !== undefined)
		|| graph.connections.some(edge => edge.input === "threshold" || edge.input === "target");
}

export function optional_input(node: Pick<BehaviorNode, "kind" | "config">, port: string): boolean {
	return node.kind === "elapsed_timer" || node.kind === "change_value" && port === "amount"
		|| node.kind === "compare" && port === "threshold" || node.kind === "progress" && port === "target"
		|| node.kind === "variable" && port === "set" || node.kind === "count" && port === "reset"
		|| node.kind === "save_entry" && port === "clear"
		|| node.kind === "record" && node.config.fields?.find(field => field.id === port)?.required === false;
}

export function variable_dependencies(graph: Behaviors, strict: boolean): { from: string; to: string }[] {
	const dependencies: { from: string; to: string }[] = [];
	for (const node of graph.nodes.filter(item => item.kind === "change_value")) {
		const target = graph.nodes.find(item => item.id === node.config.variable_id);
		if (!target || target.kind !== "variable") { if (strict || node.config.variable_id) { throw new Error(`Choose an existing variable for ${node.config.label || "Change variable"}.`); } continue; }
		if (graph.connections.some(edge => edge.to === target.id && edge.input === "set")) { throw new Error("A variable cannot use both a continuous source and change actions. Disconnect its value source first."); }
		dependencies.push({ from: node.id, to: target.id });
	}
	return dependencies;
}

export function run_timer(node: BehaviorNode, state: BehaviorState, context: BehaviorContext, input: (port: string) => Signal, once: (port: string) => boolean, linked: (port: string) => boolean): Record<string, Signal> {
	const timers = state.timers ??= {};
	const timer = timers[node.id] ?? { elapsed: 0, duration: node.config.value, cycle: 0, finished: false };
	const countdown = node.config.timer_mode !== "stopwatch";
	const command = context.timer_command?.node === node.id ? context.timer_command.action : undefined;
	const start = once("start"); const pause = once("pause"); const stop = once("stop"); const reset = once("reset");
	let elapsed = timer.elapsed + (timer.started_at === undefined ? 0 : Math.max(0, context.now - timer.started_at) / 60000);
	if (countdown && timer.started_at !== undefined && elapsed >= timer.duration) { elapsed = timer.duration; timer.finished = true; delete timer.started_at; }
	timer.elapsed = elapsed;
	if (timer.started_at !== undefined) { timer.started_at = context.now; }
	if (reset || command === "reset") { timer.elapsed = 0; timer.finished = false; delete timer.started_at; timer.cycle += 1; }
	else if (stop || command === "stop") { if (timer.started_at !== undefined || timer.elapsed > 0) { timer.finished = true; } delete timer.started_at; }
	else if (pause || command === "pause") { delete timer.started_at; }
	else if ((start || command === "start") && timer.started_at === undefined) {
		if (timer.finished) { timer.elapsed = 0; timer.finished = false; }
		if (timer.elapsed === 0) {
			const duration = linked("duration") ? input("duration") : { value: node.config.value, token: "" };
			if (countdown && (duration.available === false || typeof duration.value !== "number" || !Number.isFinite(duration.value) || duration.value < 1 / 60 || duration.value > 10080)) { throw new Error("A countdown needs an available duration between one second and seven days, in minutes."); }
			timer.duration = Number(duration.value); timer.cycle += 1;
		}
		timer.started_at = context.now;
	}
	timers[node.id] = timer;
	const token = `${node.id}:${timer.cycle}`;
	return {
		elapsed: { value: timer.elapsed, token: String(timer.elapsed) },
		remaining: { value: countdown ? Math.max(0, timer.duration - timer.elapsed) : 0, token, available: countdown },
		running: { value: timer.started_at !== undefined, token },
		finished: { value: timer.finished, token },
	};
}

export function window_active(node: BehaviorNode, now: number): boolean {
	const date = new Date(now); const minute = date.getHours() * 60 + date.getMinutes();
	const parse = (value: string) => { const [hours, minutes] = value.split(":").map(Number); return hours * 60 + minutes; };
	const start = parse(node.config.time), end = parse(node.config.end_time ?? "20:00");
	const day = date.getDay() + 1, previous_day = day === 1 ? 7 : day - 1;
	return end > start ? node.config.days.includes(day) && minute >= start && minute < end
		: node.config.days.includes(day) && minute >= start || node.config.days.includes(previous_day) && minute < end;
}
