"use client";
import { useEffect, useRef, useState } from "react";
import { initial_behaviors, run_behaviors, type BehaviorState, type BehaviorContext, type Signal, is_behavior } from "@/lib/behaviors";
import { behavior_part, legacy_ports, type LogicGraph } from "@/lib/logic-graph";
import { BuilderControls } from "./builder-controls";
import { Button, SectionLabel } from "./ui";
export function BehaviorRunner({ graph }: { graph: LogicGraph }) {
	const [state, set_state] = useState<BehaviorState>(initial_behaviors);
	const current = useRef(state);
	const [health, set_health] = useState<Record<string, number>>({});
	const [offset, set_offset] = useState(0);
	const [location, set_location] = useState(false);
	const [usage, set_usage] = useState(0);
	const [messages, set_messages] = useState<string[]>([]);
	const [error, set_error] = useState<string | null>(null);
	const [outputs, set_outputs] = useState<Record<string, Record<string, Signal>>>({});
	function run(tap?: string, next_location = location, now = Date.now()+offset, event: Partial<BehaviorContext> = {}) {
		try {
			const external = Object.fromEntries(graph.nodes.filter(n => !is_behavior(n.kind)).map(n => [n.id, Object.fromEntries(Object.entries(legacy_ports(n)).map(([port, type]) => [port, { value: type === "number" ? usage : n.kind === "home" ? next_location : false, token: String(next_location) }]))]));
			const result = run_behaviors(behavior_part(graph), current.current, { ...event, health, now, at_location: next_location, usage_minutes: usage, tap, external });
			current.current = result.state; set_state(result.state); set_outputs(result.signals); set_messages(previous => [...previous, ...result.effects.map(e => e.message), ...result.actions.map(a => a.kind === "add_allowance" ? `Simulated: +${a.minutes} minutes` : `Simulated: app gate ${a.active ? "closed" : "open"}`)].slice(-8)); set_error(null);
		} catch (failure) { set_error(failure instanceof Error ? failure.message : "Could not run these connections."); }
	}
	useEffect(() => { const timer = window.setInterval(() => run(), 1000); return () => window.clearInterval(timer); });
	return <section className="behavior-test"><SectionLabel>TEST BEHAVIORS</SectionLabel><p className="supporting">Simulated location and app usage. Test progress stays here; no phone restrictions or notifications are changed.</p>
		<div className="behavior-controls"><label><input type="checkbox" checked={location} onChange={event => { set_location(event.target.checked); run(undefined, event.target.checked); }} />At saved location</label><label>Usage minutes<input type="number" min="0" value={usage} onChange={event => set_usage(Number(event.target.value))} /></label><Button onClick={() => run()}>Evaluate</Button><Button onClick={() => { set_offset(offset+300000); run(undefined, location, Date.now()+offset+300000); }}>Advance 5 minutes</Button><Button onClick={() => { set_offset(offset+86400000); run(undefined, location, Date.now()+offset+86400000); }}>Advance one day</Button><Button onClick={() => { current.current = initial_behaviors(); set_state(current.current); set_offset(0); set_outputs({}); set_messages([]); }}>Reset test</Button></div>
		<div className="behavior-controls">{graph.nodes.filter(n => n.kind === "button" || n.kind === "check_in").map(n => <Button key={n.id} onClick={() => run(n.id)}>{n.config?.label || n.kind}</Button>)}</div>
		{graph.nodes.filter(n => n.kind === "health").map(n => <label key={n.id}>Simulate {n.config?.metric ?? "steps"}<input type="number" aria-label={`Simulate ${n.config?.metric ?? "steps"}`} value={health[n.config?.metric ?? "steps"] ?? ""} onChange={e => { const next = { ...health }; if (e.target.value === "") { delete next[n.config?.metric ?? "steps"]; } else { next[n.config?.metric ?? "steps"] = Number(e.target.value); } set_health(next); }} /></label>)}
		<BuilderControls nodes={behavior_part(graph).nodes} state={state} outputs={outputs} input={(id,value) => run(undefined, location, Date.now()+offset, { inputs: { [id]: value } })} submit={(node,values) => run(undefined, location, Date.now()+offset, { submission: { node, values } })} />
		<dl>{graph.nodes.filter(n => is_behavior(n.kind)).map(n => <div key={n.id}><dt>{n.config?.label || n.kind}</dt><dd>{Object.entries(outputs[n.id] ?? {}).map(([port,s]) => `${port}: ${s.available === false ? "Unavailable" : typeof s.value === "object" ? Array.isArray(s.value) ? `${s.value.length} entries` : "Record" : String(s.value)}`).join(" · ") || "Ready"}</dd></div>)}</dl>
		{messages.map((message, index) => <p key={index} role="status">{message}</p>)}{error && <p role="alert">{error}</p>}
	</section>;
}
