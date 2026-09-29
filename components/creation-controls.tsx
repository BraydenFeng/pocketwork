"use client";

import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { Activity, ArrowUpRight, Calculator, CalendarClock, ChartNoAxesCombined, CheckCircle2, CheckSquare, CirclePlus, Clock3, Database, FileInput, FileText, Flame, Hash, ListChecks, ListPlus, LogOut, MapPin, MessageSquare, MousePointerClick, RefreshCw, Repeat2, RotateCcw, Save, Search, Shield, Sigma, SlidersHorizontal, Smartphone, Split, Square, Table2, Target, Timer, ToggleLeft, Type, Variable, X } from "lucide-react";
import { creation_catalog, is_page_kind, page_section, type CreationKind } from "@/lib/creation";
import { Button } from "./ui";

export type PickerScope = "all" | "page" | "routines" | "data";

export function InlineText({ label, value, on_commit, placeholder, multiline = false, wrap = false, max_length = 80, required = false, className = "", on_slash }: {
	label: string; value: string; on_commit: (value: string) => void; placeholder?: string; multiline?: boolean; wrap?: boolean; max_length?: number; required?: boolean; className?: string; on_slash?: () => void;
}) {
	const [draft, set_draft] = useState(value);
	const [invalid, set_invalid] = useState(false);
	useEffect(() => { set_draft(value); set_invalid(false); }, [value]);
	function commit() { if (required && !draft.trim()) { set_invalid(true); return; } set_invalid(false); if (draft !== value) { on_commit(required ? draft.trim() : draft); } }
	function key(event: KeyboardEvent<HTMLInputElement | HTMLTextAreaElement>) {
		if (event.key === "/" && !draft && on_slash) { event.preventDefault(); on_slash(); }
		if (event.key === "Escape") { set_draft(value); set_invalid(false); }
		if (event.key === "Enter" && (!multiline || wrap)) { event.preventDefault(); event.currentTarget.blur(); }
	}
	const props = { className: `document-input ${className}`, "aria-label": label, "aria-invalid": invalid, value: draft, placeholder, maxLength: max_length, onChange: (event: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => { set_draft(wrap ? event.target.value.replace(/[\r\n]+/g, " ") : event.target.value); set_invalid(false); }, onBlur: commit, onKeyDown: key };
	return <>{multiline || wrap ? <textarea rows={wrap ? 1 : 2} {...props} /> : <input {...props} />}{invalid && <span className="field-error" role="alert">Give this a name before leaving the field.</span>}</>;
}

export function NumberField({ label, value, min, max, on_commit, unit, integer = true }: { label: string; value: number; min: number; max: number; on_commit: (value: number) => void; unit?: string; integer?: boolean }) {
	const [draft, set_draft] = useState(String(value));
	const [invalid, set_invalid] = useState(false);
	useEffect(() => { set_draft(String(value)); set_invalid(false); }, [value]);
	function commit() {
		const number = Number(draft);
		if (!draft.trim() || !Number.isFinite(number) || integer && !Number.isInteger(number) || number < min || number > max) { set_invalid(true); return; }
		set_invalid(false); if (number !== value) { on_commit(number); }
	}
	return <label className="document-number"><span>{label}</span><span className="number-with-unit"><input type="number" inputMode={integer ? "numeric" : "decimal"} step={integer ? 1 : "any"} aria-label={label} aria-invalid={invalid} min={min} max={max} value={draft} onChange={event => { set_draft(event.target.value); set_invalid(false); }} onBlur={commit} onKeyDown={event => { if (event.key === "Enter") { event.currentTarget.blur(); } if (event.key === "Escape") { set_draft(String(value)); set_invalid(false); } }} />{unit && <span>{unit}</span>}</span>{invalid && <span className="field-error" role="alert">Use {integer ? "a whole number" : "a number"} from {min} to {max}.</span>}</label>;
}

export function BlockIcon({ kind }: { kind: string }) {
	const icons = {
		heading: Type,
		note: FileText,
		checklist: CheckSquare,
		counter: Hash,
		timer: Timer,
		schedule: CalendarClock,
		screen_time: Shield,
		elapsed_timer: Timer,
		variable: Variable,
		change_value: RefreshCw,
		time_window: Clock3,
		log: ListPlus,
		form: ListPlus,
		chart: ChartNoAxesCombined,
		table: Table2,
		progress: Target,
		health: Activity,
		app_usage: Smartphone,
		record: Database,
		save_entry: Save,
		button: MousePointerClick,
		checkbox: ToggleLeft,
		number_input: Hash,
		text_input: FileInput,
		check_in: CheckCircle2,
		location: MapPin,
		arrive: MapPin,
		leave: LogOut,
		clock: CalendarClock,
		interval: Repeat2,
		app_gate: Shield,
		reminder: MessageSquare,
		count: Hash,
		streak: Flame,
		goal: Target,
		compare: SlidersHorizontal,
		and: ListChecks,
		or: CirclePlus,
		not: RotateCcw,
		branch: Split,
		delay: Timer,
		aggregate: Sigma,
		calculate: Calculator,
	} as const;
	const Icon = icons[kind as keyof typeof icons] ?? Square;
	return <Icon />;
}

export function BlockPicker({ on_close, on_pick, scope = "all" }: { on_close: () => void; on_pick: (kind: CreationKind) => void; scope?: PickerScope }) {
	const dialog = useRef<HTMLDialogElement>(null);
	const input = useRef<HTMLInputElement>(null);
	const [query, set_query] = useState("");
	const [active, set_active] = useState(0);
	const entries = creation_catalog.filter(item => {
		const in_scope = scope === "all" || scope === "page" && is_page_kind(item.kind) || !is_page_kind(item.kind) && page_section(item.kind) === scope;
		return in_scope && `${item.title} ${item.detail} ${item.section}`.toLowerCase().includes(query.toLowerCase());
	});
	useEffect(() => {
		const element = dialog.current;
		const previous = document.activeElement as HTMLElement | null;
		element?.showModal(); input.current?.focus();
		return () => { element?.close(); requestAnimationFrame(() => { if (previous?.isConnected) { previous.focus({ preventScroll: true }); } }); };
	}, []);
	useEffect(() => { dialog.current?.querySelector(`[data-option-index="${active}"]`)?.scrollIntoView({ block: "nearest" }); }, [active]);
	function key(event: KeyboardEvent) {
		if (event.key === "ArrowDown" || event.key === "ArrowUp") { event.preventDefault(); set_active(current => entries.length ? (current + (event.key === "ArrowDown" ? 1 : -1) + entries.length) % entries.length : 0); }
		if (event.key === "Enter" && event.target === input.current && entries[active]) { event.preventDefault(); on_pick(entries[active].kind); }
	}
	return <dialog ref={dialog} className="creation-dialog" aria-labelledby="block-picker-title" onCancel={on_close} onClick={event => { if (event.target === dialog.current) { on_close(); } }} onKeyDown={key}>
		<div className="picker-heading"><h2 id="block-picker-title">{scope === "page" ? "Add to page" : scope === "routines" ? "Add a routine block" : scope === "data" ? "Add a data block" : "Add a block"}</h2><Button variant="quiet" aria-label="Close block picker" onClick={on_close}><X /></Button></div>
		<label className="picker-search"><Search /><input ref={input} aria-label="Find a block" placeholder="Search blocks…" value={query} onChange={event => { set_query(event.target.value); set_active(0); }} /><kbd>Esc</kbd></label>
		<div className="picker-options">{entries.map((item, index) => <div key={item.kind}>{entries[index - 1]?.section !== item.section && <p className="picker-section">{item.section}</p>}<button type="button" className="picker-option" data-option-index={index} data-active={index === active} onMouseEnter={() => set_active(index)} onClick={() => on_pick(item.kind)} aria-label={`Add ${item.title}`}><span className="picker-glyph"><BlockIcon kind={item.kind} /></span><span><strong>{item.title}</strong><small>{item.detail}</small></span><ArrowUpRight /></button></div>)}{!entries.length && <p className="document-empty">No blocks match “{query}”. Try “chart”, “timer”, or “log”.</p>}</div>
		<div className="picker-footer"><CirclePlus /><span>Add it now. Change its properties right on the page.</span></div>
	</dialog>;
}
