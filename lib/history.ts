export type History<Value> = { past: Value[]; present: Value; future: Value[] };

export function change<Value>(history: History<Value>, value: Value): History<Value> {
	if (JSON.stringify(value) === JSON.stringify(history.present)) { return history; }
	return { past: [...history.past, history.present].slice(-60), present: value, future: [] };
}

export function undo<Value>(history: History<Value>): History<Value> {
	if (history.past.length === 0) { return history; }
	return { past: history.past.slice(0, -1), present: history.past[history.past.length - 1], future: [history.present, ...history.future] };
}

export function redo<Value>(history: History<Value>): History<Value> {
	if (history.future.length === 0) { return history; }
	return { past: [...history.past, history.present], present: history.future[0], future: history.future.slice(1) };
}
