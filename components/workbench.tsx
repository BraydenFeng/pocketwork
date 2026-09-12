"use client";

import { useEffect, useRef, useState } from "react";
import { ArrowDown, ArrowLeft, ArrowUp, ArrowUpRight, Bell, BookOpen, Braces, CalendarClock, Check, ChevronRight, Download, FileText, GripVertical, Hash, Info, Layers2, LayoutTemplate, ListChecks, MonitorSmartphone, MousePointer2, Play, Plus, Redo2, RotateCcw, Search, Shield, SlidersHorizontal, Smartphone, Timer, Trash2, Type, Undo2, Workflow, X } from "lucide-react";
import { create_block, document_schema, move_block, new_id, remove_block, serialize_document, type AppDocument, type Block, type BlockType } from "@/lib/document";
import { ALL_DAYS, DAY_LABELS, WEEKDAYS } from "@/lib/schedule";
import { change, redo, undo, type History } from "@/lib/history";
import { initial_runtime, transition, type RuntimeAction } from "@/lib/runtime";
import { load_guide_dismissed, save_guide_dismissed } from "@/lib/onboarding";
import { Button, SectionLabel, TextField, Toggle } from "./ui";
import { PhonePreview } from "./preview";
import { QuickStart, type GuideStep } from "./quick-start";

const block_catalog = [
	{ type: "heading", label: "Heading", description: "A title and supporting text", icon: Type },
	{ type: "timer", label: "Focus timer", description: "A 15–120 minute countdown", icon: Timer },
	{ type: "checklist", label: "Checklist", description: "Tasks you can check off", icon: ListChecks },
	{ type: "counter", label: "Counter", description: "Track a count toward a goal", icon: Hash },
	{ type: "note", label: "Note", description: "Text to read in your tool", icon: FileText },
	{ type: "screen_time", label: "Screen Time", description: "Block chosen apps during focus", icon: Shield },
	{ type: "schedule", label: "Schedule", description: "Runs by itself on set days and times", icon: CalendarClock },
] satisfies { type: BlockType; label: string; description: string; icon: typeof Type }[];

function error_message(error: unknown): string { return error instanceof Error ? error.message : "Something went wrong. Please try again."; }

export function Workbench({ tool, on_save, on_back, storage_blocked, storage_error, on_replace_unreadable, on_dismiss_error }: {
	tool: AppDocument; on_save: (document: AppDocument) => void; on_back: () => void; storage_blocked: boolean; storage_error: string | null; on_replace_unreadable: () => void; on_dismiss_error: () => void;
}) {
	const [history, set_history] = useState<History<AppDocument>>({ past: [], present: tool, future: [] });
	const document = history.present;
	const [ready, set_ready] = useState(false);
	const [save_state, set_save_state] = useState("Saved on this browser");
	const [error, set_error] = useState<string | null>(null);
	const [notice, set_notice] = useState<string | null>(null);
	const [selected_id, set_selected_id] = useState<string | null>((tool.blocks.find((block) => block.type === "timer") ?? tool.blocks[0]).id);
	const [view, set_view] = useState<"canvas" | "behavior" | "configuration">("canvas");
	const [inspector, set_inspector] = useState<"block" | "app" | "device">("block");
	const [interactive, set_interactive] = useState(false);
	const [query, set_query] = useState("");
	const [dragged_id, set_dragged_id] = useState<string | null>(null);
	const [runtime, set_runtime] = useState(initial_runtime);
	const [now, set_now] = useState(0);
	const [guide_open, set_guide_open] = useState(false);
	const [guide_step, set_guide_step] = useState<GuideStep>("customize");
	const [focus_target, set_focus_target] = useState<"inspector" | "preview" | "guide" | "help" | null>(null);
	const inspector_ref = useRef<HTMLElement>(null);
	const preview_ref = useRef<HTMLElement>(null);
	const help_ref = useRef<HTMLButtonElement>(null);
	const search_input = useRef<HTMLInputElement>(null);
	const selected_block = document.blocks.find((block) => block.id === selected_id);
	const has_timer = document.blocks.some((block) => block.type === "timer");
	const has_shield = document.blocks.some((block) => block.type === "screen_time");
	const has_schedule = document.blocks.some((block) => block.type === "schedule");
	const has_engine = has_timer || has_schedule;
	const valid = document_schema.safeParse(document).success;

	useEffect(() => {
		try { set_guide_open(!load_guide_dismissed(window.localStorage)); }
		catch (failure) { console.warn(error_message(failure)); set_guide_open(true); }
		set_now(Date.now()); set_ready(true);
	}, []);

	useEffect(() => {
		if (!focus_target) { return; }
		const target = focus_target === "inspector" ? inspector_ref.current : focus_target === "preview" ? preview_ref.current : help_ref.current;
		target?.focus({ preventScroll: true });
		const region = focus_target === "guide" ? window.document.getElementById("quick-start") : target;
		region?.scrollIntoView({ block: "start" });
		set_focus_target(null);
	}, [focus_target]);

	useEffect(() => {
		if (!ready || storage_blocked || document === tool) { return; }
		set_save_state("Saving…");
		const timeout = window.setTimeout(() => {
			try { on_save(document); set_save_state("Saved on this browser"); }
			catch (failure) { set_error(error_message(failure)); set_save_state("Not saved · export a backup"); }
		}, 350);
		return () => window.clearTimeout(timeout);
	}, [document, ready, storage_blocked, on_save, tool]);

	// Leaving the editor inside the debounce window must not drop the last edit.
	const pending = useRef({ document, tool, on_save, storage_blocked });
	pending.current = { document, tool, on_save, storage_blocked };
	useEffect(() => () => {
		const { document: latest, tool: saved, on_save: save, storage_blocked: blocked } = pending.current;
		if (blocked || latest === saved) { return; }
		try { save(latest); } catch (failure) { console.warn(error_message(failure)); }
	}, []);

	useEffect(() => {
		const tick = () => { const timestamp = Date.now(); set_now(timestamp); set_runtime((state) => transition(document, state, { type: "tick", now: timestamp })); };
		const interval = window.setInterval(tick, 500);
		window.addEventListener("focus", tick);
		return () => { window.clearInterval(interval); window.removeEventListener("focus", tick); };
	}, [document]);

	useEffect(() => { set_runtime(initial_runtime()); }, [document]);
	useEffect(() => {
		function on_key(event: KeyboardEvent) {
			const target = event.target as HTMLElement;
			if (event.key === "/" && !["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName) && !target.isContentEditable) {
				event.preventDefault(); search_input.current?.focus();
			}
		}
		window.addEventListener("keydown", on_key);
		return () => window.removeEventListener("keydown", on_key);
	}, []);
	useEffect(() => {
		if (!notice) { return; }
		const timeout = window.setTimeout(() => set_notice(null), 4500);
		return () => window.clearTimeout(timeout);
	}, [notice]);

	function commit(next: AppDocument) { set_history((current) => change(current, next)); }
	function update_block(next: Block) { commit({ ...document, blocks: document.blocks.map((block) => block.id === next.id ? next : block) }); }
	function open_inspector(section: "block" | "app" | "device") { set_inspector(section); set_focus_target("inspector"); }
	function select_block(id: string) { set_selected_id(id); set_interactive(false); set_view("canvas"); open_inspector("block"); }
	function open_preview(test_mode: boolean) { set_view("canvas"); set_interactive(test_mode); set_focus_target("preview"); }
	function toggle_guide(open: boolean) {
		set_guide_open(open); set_focus_target(open ? "guide" : "help");
		try { save_guide_dismissed(window.localStorage, !open); }
		catch (failure) { console.warn(error_message(failure)); set_notice(error_message(failure)); }
	}
	function guide_action() {
		if (guide_step === "customize") { select_block((document.blocks.find((block) => block.type === "timer") ?? document.blocks[0]).id); }
		else if (guide_step === "test") { open_preview(true); }
		else { open_inspector("device"); }
	}
	function dispatch(action: RuntimeAction) { set_runtime((state) => transition(document, state, action)); }
	function add_block(type: BlockType) {
		if (document.blocks.length >= 20 || ((type === "timer" || type === "screen_time" || type === "schedule") && document.blocks.some((block) => block.type === type))) { return; }
		if ((type === "schedule" && has_timer) || (type === "timer" && has_schedule)) { set_notice("A routine runs on a timer or on a schedule, not both. Remove the other one first."); return; }
		const block = create_block(type);
		// A schedule only means something if it locks apps, so switch that rule on when the pieces are there.
		const rules = type === "schedule" && has_shield ? { ...document.rules, block_during_focus: true } : document.rules;
		commit({ ...document, blocks: [...document.blocks, block], rules, ...(type === "schedule" ? { enabled: false } : {}) }); select_block(block.id); set_view("canvas");
	}
	function export_tool() {
		try {
			const blob = new Blob([serialize_document(document)], { type: "application/json" });
			const url = URL.createObjectURL(blob);
			const link = window.document.createElement("a"); link.href = url; link.download = `${document.name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "personal-tool"}.pocketwork.json`;
			link.click(); window.setTimeout(() => URL.revokeObjectURL(url), 1000); set_notice("Configuration exported. Import it from Files in the iPhone host.");
		} catch (failure) { set_error(error_message(failure)); }
	}
	function drop_block(target_id: string) {
		if (!dragged_id || dragged_id === target_id) { return; }
		const blocks = [...document.blocks]; const source = blocks.findIndex((block) => block.id === dragged_id); const target = blocks.findIndex((block) => block.id === target_id);
		if (source >= 0 && target >= 0) { const [moved] = blocks.splice(source, 1); blocks.splice(target, 0, moved); commit({ ...document, blocks }); }
		set_dragged_id(null);
	}
	function update_rule(key: keyof AppDocument["rules"], value: boolean) { commit({ ...document, rules: { ...document.rules, [key]: value } }); }
	function set_enabled(enabled: boolean) { commit({ ...document, enabled }); }
	function rules_panel() {
		return <><div className="behavior-intro"><Workflow /><div><h2>{has_schedule ? "What happens on schedule?" : "What happens when you focus?"}</h2><p>Turn these rules on or off, then use Try it to test them. Rules control behavior; blocks control what appears on your screen.</p><Button variant="quiet" onClick={() => open_preview(true)}><Play />Test these rules</Button></div></div>
			<div className="recipe"><SectionLabel number="WHEN">{has_schedule ? "The scheduled window opens" : "A focus session starts"}</SectionLabel><div className="recipe-action"><Shield /><div><strong>Keep selected apps out of the way</strong><p>{has_schedule ? "Choose apps privately on your iPhone. They lock when the window opens and release when it closes or you switch the routine off." : "Choose apps privately on your iPhone. They are released when the session ends or you stop it."}</p></div></div><Toggle label={has_schedule ? "Block while active" : "Block during focus"} description={has_engine && has_shield ? (has_schedule ? "Uses your schedule + Screen Time block" : "Uses your timer + Screen Time block") : "Add a timer or schedule, plus a Screen Time block first"} checked={document.rules.block_during_focus} disabled={!has_engine || !has_shield} on_change={(value) => update_rule("block_during_focus", value)} /></div>
			<div className="recipe"><SectionLabel number="WHEN">The focus timer finishes</SectionLabel><div className="recipe-action"><Bell /><div><strong>A gentle heads-up</strong><p>The iPhone host can schedule a local notification. Ending a session early cancels it.</p></div></div><Toggle label="Notify on completion" description={has_timer ? "Requires notification permission on iPhone" : has_schedule ? "Only for timer routines" : "Add a timer first"} checked={document.rules.notify_on_complete} disabled={!has_timer} on_change={(value) => update_rule("notify_on_complete", value)} /></div>
			<div className="plain-note"><Info /><p>Editing your tool resets the browser test session. Native blocks are simulated here; they do not control this computer or your phone.</p></div></>;
	}

	return <div className="workbench"><a className="skip-link" href="#canvas">Skip to workbench</a>
		<header className="topbar"><div className="brand"><Layers2 /><span>pocketwork<span className="brand-period">.</span></span></div><span className="workspace-label">PERSONAL APP WORKBENCH</span><div className="topbar-actions"><button ref={help_ref} type="button" className="button button-quiet quick-start-toggle" aria-expanded={guide_open} aria-controls="quick-start" disabled={!ready} onClick={() => toggle_guide(!guide_open)}><BookOpen />Quick start</button><Button variant="quiet" onClick={() => open_inspector("device")}><Smartphone />iPhone setup</Button><span className="header-divider" /><Button variant="primary" onClick={export_tool} disabled={!ready || !valid}><Download />Export routine</Button></div>
		</header>
		<div className="projectbar"><div><div className="breadcrumb"><button type="button" className="breadcrumb-back" onClick={on_back}><ArrowLeft />My routines</button><ChevronRight /><span>Editing</span></div><button className="project-title" type="button" title="Edit routine name and description" onClick={() => open_inspector("app")}><h1>{document.name}</h1><SlidersHorizontal /></button></div><div className="project-meta"><span className={`save-status ${storage_blocked ? "has-error" : ""}`}><span />{storage_blocked ? "Draft recovery needed" : save_state}</span><span className="local-tag">LOCAL FIRST</span></div></div>
		{guide_open && <QuickStart step={guide_step} on_step={set_guide_step} on_action={guide_action} on_dismiss={() => toggle_guide(false)} />}
		{(error ?? storage_error) && <div className="alert-banner" role="alert"><Info /><span>{error ?? storage_error}</span>{storage_blocked && <Button onClick={on_replace_unreadable}>Replace unreadable data</Button>}<Button variant="quiet" aria-label="Dismiss error" onClick={() => { set_error(null); on_dismiss_error(); }}><X /></Button></div>}
		{notice && <div className="notice-banner" role="status"><Check />{notice}</div>}
		<main className="workbench-grid">
			<aside className="library" aria-label="Component library"><div className="panel-heading"><SectionLabel number="01">ADD BLOCKS</SectionLabel><Layers2 /></div>
				<p className="panel-hint">Add blocks below. Included controls open their settings.</p>
				<label className="search-field"><Search /><input ref={search_input} placeholder="Find a block…" value={query} onChange={(event) => set_query(event.target.value)} aria-label="Search blocks" /><kbd>/</kbd></label>
				<div className="library-list">{block_catalog.filter((entry) => `${entry.label} ${entry.description}`.toLowerCase().includes(query.toLowerCase())).map((entry) => {
					const included = (entry.type === "timer" || entry.type === "screen_time" || entry.type === "schedule") ? document.blocks.find((block) => block.type === entry.type) : undefined;
					return <button type="button" className="library-item" key={entry.type} disabled={!ready || (!included && document.blocks.length >= 20)} onClick={() => included ? select_block(included.id) : add_block(entry.type)} aria-label={`${included ? "Edit" : "Add"} ${entry.label}`}><span className="block-glyph"><entry.icon /></span><span><strong>{entry.label}</strong><small>{included ? "Added · click to edit" : entry.description}</small></span>{included ? <Check /> : <Plus />}</button>;
				})}{block_catalog.filter((entry) => `${entry.label} ${entry.description}`.toLowerCase().includes(query.toLowerCase())).length === 0 && <p className="empty-hint">No matching blocks. Try “timer”, “schedule” or “note”.</p>}</div>
				<div className="outline-heading"><SectionLabel>ON YOUR SCREEN</SectionLabel><span>{document.blocks.length}/20</span></div>
				<ol className="block-outline">{document.blocks.map((block, index) => {
					const Icon = block_catalog.find((entry) => entry.type === block.type)!.icon;
					return <li key={block.id} className={selected_id === block.id ? "is-selected" : ""} draggable onDragStart={() => set_dragged_id(block.id)} onDragEnd={() => set_dragged_id(null)} onDragOver={(event) => event.preventDefault()} onDrop={() => drop_block(block.id)}><button type="button" className="outline-select" onClick={() => { select_block(block.id); set_view("canvas"); }} aria-pressed={selected_id === block.id}><GripVertical /><Icon /><span>{block.title}</span></button><div className="reorder-controls"><button type="button" aria-label={`Move ${block.title} up`} disabled={index === 0} onClick={() => commit(move_block(document, block.id, -1))}><ArrowUp /></button><button type="button" aria-label={`Move ${block.title} down`} disabled={index === document.blocks.length - 1} onClick={() => commit(move_block(document, block.id, 1))}><ArrowDown /></button></div></li>;
				})}</ol>
				<div className="library-footer"><MonitorSmartphone /><strong>Build here. Test here. Run on iPhone.</strong><p>This browser previews your routine. Running it on iPhone requires the native app, currently in development.</p><button className="text-button" type="button" onClick={() => open_inspector("device")}>What works on iPhone <ArrowUpRight /></button></div>
			</aside>
			<section ref={preview_ref} tabIndex={-1} className="canvas-region" id="canvas" aria-label="Workbench canvas"><div className="canvas-toolbar"><div className="view-tabs" role="tablist" aria-label="Editor view">{([{ id: "canvas", label: "Layout", icon: LayoutTemplate }, { id: "behavior", label: "Rules", icon: Workflow }, { id: "configuration", label: "Advanced", icon: Braces }] as const).map((tab) => <button key={tab.id} type="button" role="tab" aria-selected={view === tab.id} onClick={() => set_view(tab.id)}><tab.icon />{tab.label}</button>)}</div><div className="history-controls"><Button variant="quiet" aria-label="Undo edit" disabled={!history.past.length} onClick={() => set_history(undo)}><Undo2 /></Button><Button variant="quiet" aria-label="Redo edit" disabled={!history.future.length} onClick={() => set_history(redo)}><Redo2 /></Button></div></div>
				{view === "canvas" && <><div className="canvas-caption"><span><Smartphone />iPhone · live preview</span><div className="mode-switch"><button type="button" aria-pressed={!interactive} onClick={() => set_interactive(false)}><MousePointer2 />Edit</button><button type="button" aria-pressed={interactive} onClick={() => set_interactive(true)}><Play />Try it</button></div></div><div className="mode-hint" role="status">{interactive ? <><Play /><span><strong>Test mode.</strong> Use the buttons below. App blocking is only simulated.</span></> : <><MousePointer2 /><span><strong>Edit mode.</strong> Click a block below to change its settings. Use Try it to test buttons.</span></>}</div><div className="device-stage"><PhonePreview document={document} runtime={runtime} now={now} selected_id={selected_id} interactive={interactive} on_select={select_block} dispatch={dispatch} on_toggle_enabled={set_enabled} /></div><div className="preview-footnote"><span className="preview-badge">BROWSER SIMULATION</span><span>{interactive ? "Timer, tasks and counters are temporary here. The On/Off switch is saved with the routine." : "Add blocks from the library. Reorder them in On your screen."}</span></div></>}
				{view === "behavior" && <div className="behavior-panel">{rules_panel()}</div>}
				{view === "configuration" && <div className="configuration-panel"><SectionLabel number="V1">YOUR PORTABLE TOOL</SectionLabel><h2>Configuration, not code.</h2><p>This is the document both the visual editor and native host understand. No API keys, app-selection tokens, or executable scripts are exported.</p><pre tabIndex={0} aria-label="Routine JSON configuration">{JSON.stringify(document, null, 2)}</pre><Button onClick={export_tool}><Download />Download configuration</Button></div>}
			</section>
			<aside ref={inspector_ref} tabIndex={-1} className="inspector" aria-label="Inspector"><div className="panel-heading"><SectionLabel number="02">SETTINGS</SectionLabel><SlidersHorizontal /></div><Button className="return-to-preview" variant="quiet" onClick={() => open_preview(interactive)}><MonitorSmartphone />Back to preview</Button><div className="inspector-tabs" role="tablist" aria-label="Inspector section">{(["block", "app", "device"] as const).map((tab) => <button type="button" role="tab" aria-selected={inspector === tab} key={tab} onClick={() => set_inspector(tab)}>{tab === "block" ? "Block" : tab === "app" ? "Routine" : "iPhone"}</button>)}</div>
				{inspector === "block" && (selected_block ? <div className="inspector-content" key={selected_block.id}><div className="inspector-title"><span className="block-glyph">{(() => { const Icon = block_catalog.find((entry) => entry.type === selected_block.type)!.icon; return <Icon />; })()}</span><div><h2>{block_catalog.find((entry) => entry.type === selected_block.type)!.label}</h2><span className="supporting">Changes appear in the preview. Text saves when you leave a field.</span></div></div>
					<TextField label="Title" value={selected_block.title} required on_commit={(title) => update_block({ ...selected_block, title })} />
					{selected_block.type === "heading" && <TextField label="Supporting text" value={selected_block.subtitle} multiline max_length={200} on_commit={(subtitle) => update_block({ ...selected_block, subtitle })} />}
					{selected_block.type === "timer" && <><label className="field-label"><span>Session length</span><select className="field" value={selected_block.minutes} onChange={(event) => update_block({ ...selected_block, minutes: Number(event.target.value) })}>{Array.from(new Set([15, 20, 25, 30, 45, 60, 90, 120, selected_block.minutes])).sort((left, right) => left - right).map((minutes) => <option key={minutes} value={minutes}>{minutes} minutes</option>)}</select></label><p className="supporting">15–120 minutes. The native Screen Time monitor requires intervals of at least 15 minutes.</p><SectionLabel>CONNECTED BEHAVIOR</SectionLabel><Toggle label="Block during focus" description={has_shield ? "Screen Time apps selected on iPhone" : "Add a Screen Time block to enable"} checked={document.rules.block_during_focus} disabled={!has_shield} on_change={(value) => update_rule("block_during_focus", value)} /><Toggle label="Notify on completion" description="A local notification on iPhone" checked={document.rules.notify_on_complete} on_change={(value) => update_rule("notify_on_complete", value)} /></>}
					{selected_block.type === "checklist" && <><SectionLabel>TASKS · {selected_block.items.length}/20</SectionLabel>{selected_block.items.map((item, index) => <div className="task-editor" key={item.id}><TextField label={`Task ${index + 1}`} value={item.text} required on_commit={(text) => update_block({ ...selected_block, items: selected_block.items.map((entry) => entry.id === item.id ? { ...entry, text } : entry) })} /><Button variant="quiet" aria-label={`Remove task ${index + 1}`} disabled={selected_block.items.length === 1} onClick={() => update_block({ ...selected_block, items: selected_block.items.filter((entry) => entry.id !== item.id) })}><X /></Button></div>)}<Button disabled={selected_block.items.length >= 20} onClick={() => update_block({ ...selected_block, items: [...selected_block.items, { id: new_id(), text: "Another small step" }] })}><Plus />Add task</Button></>}
					{selected_block.type === "note" && <TextField label="Your note" value={selected_block.text} multiline max_length={1000} on_commit={(text) => update_block({ ...selected_block, text })} />}
					{selected_block.type === "counter" && <label className="field-label"><span>Target</span><input className="field" type="number" min={1} max={1000} value={selected_block.target} onChange={(event) => { const target = Number(event.target.value); if (Number.isInteger(target) && target >= 1 && target <= 1000) { update_block({ ...selected_block, target }); } }} /></label>}
					{selected_block.type === "schedule" && <><SectionLabel>DAYS</SectionLabel><div className="day-picker" role="group" aria-label="Days of the week">{ALL_DAYS.map((day) => <button type="button" key={day} aria-pressed={selected_block.days.includes(day)} onClick={() => { const days = selected_block.days.includes(day) ? selected_block.days.filter((entry) => entry !== day) : [...selected_block.days, day].sort((left, right) => left - right); if (days.length) { update_block({ ...selected_block, days }); } }}>{DAY_LABELS[day - 1]}</button>)}</div><div className="day-presets"><button type="button" className="text-button" onClick={() => update_block({ ...selected_block, days: ALL_DAYS })}>Every day</button><button type="button" className="text-button" onClick={() => update_block({ ...selected_block, days: WEEKDAYS })}>Weekdays</button></div>
						<div className="time-fields"><label className="field-label"><span>Starts</span><input className="field" type="time" value={selected_block.start} onChange={(event) => { if (event.target.value) { update_block({ ...selected_block, start: event.target.value }); } }} /></label><label className="field-label"><span>Ends</span><input className="field" type="time" value={selected_block.end} onChange={(event) => { if (event.target.value) { update_block({ ...selected_block, end: event.target.value }); } }} /></label></div><p className="supporting">An end time earlier than the start runs past midnight. Switch the routine on from the preview or My routines.</p>
						<SectionLabel>CONNECTED BEHAVIOR</SectionLabel><Toggle label="Block while active" description={has_shield ? "Screen Time apps selected on iPhone" : "Add a Screen Time block to enable"} checked={document.rules.block_during_focus} disabled={!has_shield} on_change={(value) => update_rule("block_during_focus", value)} /></>}
					{selected_block.type === "screen_time" && <><div className="capability-note"><Shield /><strong>Your selection stays on your phone.</strong><p>Choose apps using Apple’s private picker in the native host. Website and category selections are supported there too.</p></div><Toggle label={has_schedule ? "Block while active" : "Block during focus"} description={has_engine ? (has_schedule ? "Locked while the schedule window is open" : "Release when the session ends or is stopped") : "Add a focus timer or schedule first"} checked={document.rules.block_during_focus} disabled={!has_engine} on_change={(value) => update_rule("block_during_focus", value)} /><Button onClick={() => set_inspector("device")}><Smartphone />View device requirements</Button></>}
					<div className="inspector-bottom"><Button variant="danger" disabled={document.blocks.length === 1} onClick={() => { const next = remove_block(document, selected_block.id); commit(next); set_selected_id(next.blocks[0].id); }}><Trash2 />Remove block</Button></div>
				</div> : <div className="empty-hint">Select a block in your screen to edit it.</div>)}
				{inspector === "app" && <div className="inspector-content"><div className="inspector-title"><LayoutTemplate /><h2>Name your routine</h2></div><TextField label="Routine name" value={document.name} required on_commit={(name) => commit({ ...document, name })} /><TextField label="Description" value={document.description} multiline max_length={200} on_commit={(description) => commit({ ...document, description })} /><div className="capability-note"><strong>Saved with your other routines.</strong><p>Every routine is kept on this browser. Export a file to move one to your iPhone or another computer. There is no cloud sync or account yet.</p></div><Button onClick={on_back}><ArrowLeft />Back to my routines</Button></div>}
				{inspector === "device" && <div className="inspector-content"><div className="inspector-title"><Smartphone /><h2>From canvas to iPhone</h2></div><span className="preview-badge">NATIVE HOST · DEVELOPMENT</span><p className="supporting">The browser is ready to use. The iPhone host source is included, but it is not an App Store app yet.</p><ol className="device-steps"><li><strong>Build the native host</strong><p>Use a Mac with Xcode. Follow ios/README.md to configure signing, App Groups, and Family Controls.</p></li><li><strong>Export this routine</strong><p>Save the JSON file to iCloud Drive or send it to your iPhone.</p></li><li><strong>Import and grant access</strong><p>Open the host, import from Files, then select the apps to block and allow notifications if desired.</p></li></ol><div className="capability-note"><Info /><strong>Honest permission boundaries</strong><p>Nothing here has Apple approval yet. Real blocking needs signing and device verification. The user can always end a session.</p></div><p className="supporting">Location triggers, widgets, and subscription billing are not part of this build.</p></div>}
				<div className="runtime-panel"><SectionLabel number="03">TEST ACTIVITY</SectionLabel><div className="runtime-status"><span className={runtime.status === "running" ? "status-dot is-running" : "status-dot"} /><span>{runtime.status === "running" ? "Session running · simulated" : runtime.status === "completed" ? "Session completed" : "Ready when you are"}</span><button type="button" aria-label="Reset preview session" onClick={() => set_runtime(initial_runtime())}><RotateCcw /></button></div>{runtime.events.length ? <ol className="event-log" aria-live="polite">{runtime.events.slice(-3).map((event, index) => <li key={`${event.at}-${index}`}>{event.message}</li>)}</ol> : <p className="supporting">Switch to Try it and start a session to see what your rules do.</p>}{runtime.status === "running" && <Button variant="quiet" onClick={() => dispatch({ type: "tick", now: runtime.ends_at! })}>Simulate timer finishing <ChevronRight /></Button>}</div>
			</aside>
		</main><footer className="workbench-footer"><span><span className="status-dot" />Your own little routines.</span><span>LOCAL PROTOTYPE <span className="footer-separator">/</span> SCHEMA V1</span></footer>
	</div>;
}
