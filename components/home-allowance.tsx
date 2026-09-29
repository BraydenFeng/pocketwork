"use client";

import { useEffect, useState } from "react";
import { ChevronDown, MapPin, Plus, Smartphone, Trash2 } from "lucide-react";
import type { AppDocument } from "@/lib/document";
import { home_policy_schema, type HomePolicy } from "@/lib/home-policy";
import { home_allowance_block_id } from "@/lib/page-blocks";
import { BlockIcon, NumberField } from "./creation-controls";
import { Button } from "./ui";

const day_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export function HomeAllowanceBlock({ document, open, disabled = false, on_toggle, on_change, on_draft_error }: {
	document: AppDocument;
	open: boolean;
	disabled?: boolean;
	on_toggle: () => void;
	on_change: (document: AppDocument) => void;
	on_draft_error: (message: string | null) => void;
}) {
	const [policy, set_policy] = useState(document.home_allowance!);
	const [error, set_error] = useState<string | null>(null);
	useEffect(() => { if (!error && document.home_allowance) { set_policy(document.home_allowance); } }, [document.home_allowance, error]);
	useEffect(() => {
		on_draft_error(error);
		return () => on_draft_error(null);
	}, [error, on_draft_error]);
	function update_policy(next: HomePolicy) {
		const normalized = { ...next, outside_windows: "unrestricted" as const };
		set_policy(normalized);
		const parsed = home_policy_schema.safeParse(normalized);
		if (!parsed.success) { set_error(parsed.error.issues[0].message); return; }
		set_error(null);
		on_change({ ...document, home_allowance: parsed.data });
	}
	function update_rule(index: number, next: HomePolicy["rules"][number]) {
		update_policy({ ...policy, rules: policy.rules.map((rule, rule_index) => rule_index === index ? next : rule) });
	}
	const assigned_days = new Set(policy.rules.flatMap(rule => rule.days));
	const unassigned_days = [1, 2, 3, 4, 5, 6, 7].filter(day => !assigned_days.has(day));
	return <section id="allowance-editor" className={`document-logic-block ${open ? "is-open" : ""}`}>
		<button type="button" className="document-logic-heading" aria-expanded={open} aria-label="Edit Home screen-time allowance" onClick={on_toggle}><BlockIcon kind="screen_time" /><span><strong>Home screen-time allowance</strong><small>Home, time windows, and one daily limit</small></span><span className="document-logic-kind">Native iPhone routine</span><ChevronDown /></button>
		{open && <div className="document-logic-body allowance-logic-body">
			<p className="supporting">Usage counts only at your saved home location and inside these windows. Outside either one, this routine does not block anything.</p>
			<div className="allowance-fact"><MapPin /><div><strong>At your saved home location</strong><p>Set or change the location privately on your iPhone.</p></div></div>
			{error && <div className="document-draft-warning" role="alert"><div><strong>Finish the schedule.</strong><p>{error}</p></div></div>}
			<fieldset className="allowance-settings" aria-label="Home allowance settings" disabled={disabled}>
				<div className="allowance-rules">{policy.rules.map((rule, index) => <section className="allowance-rule" key={index}>
					<div className="allowance-rule-heading"><div><span className="document-eyebrow">DAY GROUP {String(index + 1).padStart(2, "0")}</span><h3>{rule.days.length ? rule.days.map(day => day_names[day - 1]).join(", ") : "Choose days"}</h3></div>{policy.rules.length > 1 && <Button variant="danger" aria-label={`Remove day group ${index + 1}`} onClick={() => update_policy({ ...policy, rules: policy.rules.filter((_, rule_index) => rule_index !== index) })}><Trash2 />Remove</Button>}</div>
					<div className="day-picker" role="group" aria-label={`Days for group ${index + 1}`}>{day_names.map((label, day_index) => { const day = day_index + 1; const used_elsewhere = policy.rules.some((other, rule_index) => rule_index !== index && other.days.includes(day)); return <button type="button" key={label} disabled={used_elsewhere} aria-pressed={rule.days.includes(day)} onClick={() => update_rule(index, { ...rule, days: rule.days.includes(day) ? rule.days.filter(value => value !== day) : [...rule.days, day].sort() })}>{label}</button>; })}</div>
					<NumberField label="Daily allowance" value={rule.allowance_minutes} min={1} max={180} unit="minutes" on_commit={allowance_minutes => update_rule(index, { ...rule, allowance_minutes })} />
					<div className="allowance-windows">{rule.windows.map((window, window_index) => <div className="allowance-window" key={window_index}><div className="document-time-fields"><label>From<input type="time" aria-label={`Group ${index + 1} window ${window_index + 1} starts`} value={window.start} onChange={event => update_rule(index, { ...rule, windows: rule.windows.map((part, part_index) => part_index === window_index ? { ...part, start: event.target.value } : part) })} /></label><span>to</span><label>Until<input type="time" aria-label={`Group ${index + 1} window ${window_index + 1} ends`} value={window.end} onChange={event => update_rule(index, { ...rule, windows: rule.windows.map((part, part_index) => part_index === window_index ? { ...part, end: event.target.value } : part) })} /></label></div>{rule.windows.length > 1 && <Button variant="quiet" onClick={() => update_rule(index, { ...rule, windows: rule.windows.filter((_, part_index) => part_index !== window_index) })}>Remove window</Button>}</div>)}</div>
					<Button variant="quiet" disabled={rule.windows.length >= 2 || rule.windows.at(-1)!.end > "23:44"} onClick={() => update_rule(index, { ...rule, windows: [...rule.windows, { start: rule.windows.at(-1)!.end, end: "23:59" }] })}><Plus />Add window</Button>
				</section>)}</div>
				<Button disabled={!unassigned_days.length || policy.rules.length >= 7} onClick={() => update_policy({ ...policy, rules: [...policy.rules, { days: unassigned_days, allowance_minutes: 30, windows: [{ start: "06:30", end: "20:30" }] }] })}><Plus />Add day group</Button>
			</fieldset>
			<div className="allowance-fact"><Smartphone /><div><strong>{document.enabled ? "Enabled on your account" : "Off until you enable it"}</strong><p>Choose apps, set home, and grant Screen Time and location access on your iPhone. Whole-minute Screen Time checkpoints and iOS location callbacks can arrive late.</p></div></div>
		</div>}
	</section>;
}
