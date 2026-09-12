"use client";

import { BatteryFull, Check, ChevronRight, Pause, Play, Plus, Shield, ShieldCheck, Signal, Wifi } from "lucide-react";
import type { AppDocument, Block } from "@/lib/document";
import { format_duration, remaining_seconds, type RuntimeAction, type RuntimeState } from "@/lib/runtime";

export function PhonePreview({ document, runtime, now, selected_id, interactive, on_select, dispatch }: {
	document: AppDocument; runtime: RuntimeState; now: number; selected_id: string | null; interactive: boolean;
	on_select: (id: string) => void; dispatch: (action: RuntimeAction) => void;
}) {
	const blocking = runtime.status === "running" && document.rules.block_during_focus;
	function content(block: Block) {
		switch (block.type) {
			case "heading": return <div className="preview-heading"><span className="eyebrow">YOUR SPACE, YOUR PACE</span><h2>{block.title}</h2><p>{block.subtitle}</p></div>;
			case "timer": return <div className="preview-timer"><span className="preview-label">{block.title}</span><div className="timer-digits" aria-label="Time remaining">{format_duration(remaining_seconds(document, runtime, now))}</div><span className="timer-caption">{runtime.status === "running" ? "One thing at a time." : runtime.status === "completed" ? "A little progress feels good." : "A fresh start is one tap away."}</span>
				<button type="button" className="session-button" disabled={!interactive} onClick={() => dispatch({ type: runtime.status === "running" ? "stop" : "start", now: Date.now() })}>
					{runtime.status === "running" ? <Pause /> : <Play />} {runtime.status === "running" ? "End session" : runtime.status === "completed" ? "Start again" : "Start focusing"}
				</button></div>;
			case "checklist": return <div className="preview-checklist"><div className="preview-label-row"><h3>{block.title}</h3><span>{block.items.filter((item) => runtime.completed_tasks.includes(item.id)).length}/{block.items.length}</span></div>
				{block.items.map((item) => <label className="task-row" key={item.id}><input type="checkbox" disabled={!interactive} checked={runtime.completed_tasks.includes(item.id)} onChange={() => dispatch({ type: "toggle_task", task_id: item.id, now: Date.now() })} /><span>{item.text}</span></label>)}</div>;
			case "screen_time": return <div className="preview-shield"><span className="shield-glyph">{blocking ? <ShieldCheck /> : <Shield />}</span><div><h3>{block.title}</h3><p>{blocking ? "Blocking simulated in preview" : "Choose your apps on iPhone"}</p></div><ChevronRight /></div>;
			case "counter": return <div className="preview-counter"><h3>{block.title}</h3><div className="counter-value"><span>{runtime.counters[block.id] ?? 0}<small> / {block.target}</small></span><button className="button" type="button" aria-label={`Increment ${block.title}`} disabled={!interactive || (runtime.counters[block.id] ?? 0) >= block.target} onClick={() => dispatch({ type: "increment", block_id: block.id, now: Date.now() })}>{(runtime.counters[block.id] ?? 0) >= block.target ? <Check /> : <Plus />}</button></div></div>;
			case "note": return <div className="preview-note"><h3>{block.title}</h3><p>{block.text}</p></div>;
		}
	}
	return <div className="phone" aria-label="Live iPhone preview"><div className="phone-top"><span>9:41</span><span className="phone-island" aria-hidden="true" /><span className="phone-signals" aria-hidden="true"><Signal /><Wifi /><BatteryFull /></span></div>
		<div className="phone-content"><div className="phone-app-name"><span className="app-sigil" aria-hidden="true" /><span>{document.name}</span></div>
			{document.blocks.map((block) => <div className={`preview-block ${selected_id === block.id && !interactive ? "is-selected" : ""}`} key={block.id}>
				{!interactive && <button className="block-hit-area" type="button" aria-label={`Select ${block.title}`} onClick={() => on_select(block.id)} />}{content(block)}
			</div>)}
			<div className="phone-footer">Made for you. By you.</div>
		</div><div className="home-indicator" aria-hidden="true" /></div>;
}
