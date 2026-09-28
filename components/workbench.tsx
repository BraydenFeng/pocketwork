"use client";

import { native_format_four } from "@/lib/release-flags";

import { useEffect, useRef, useState } from "react";
import { ArrowLeft, Check, ChevronRight, Download, Info, MoreHorizontal, Play, Redo2, RotateCcw, Smartphone, Undo2, X } from "lucide-react";
import { is_behavior } from "@/lib/behaviors";
import { serialize_document, type AppDocument } from "@/lib/document";
import { add_connected_block, checked_document, fill_single_sources, insert_page_block, is_page_kind, validate_connections, type CreationKind } from "@/lib/creation";
import { compile_graph, graph_from_document, type LogicGraph } from "@/lib/logic-graph";
import type { AppGroup } from "@/lib/library";
import { change, redo, undo, type History } from "@/lib/history";
import { initial_runtime, transition, type RuntimeAction } from "@/lib/runtime";
import { BehaviorRunner } from "./behavior-runner";
import { BlockPicker, type PickerScope } from "./creation-controls";
import { PhonePreview } from "./preview";
import { RoutinePage } from "./routine-page";
import { Button } from "./ui";
import type { SyncState } from "./app";

type EditorView = "page" | "preview";
type PickerState = { before?: string; scope: PickerScope };

function message(error: unknown): string { return error instanceof Error ? error.message : "Something went wrong. Please try again."; }

function merge_draft(document: AppDocument, draft: LogicGraph): LogicGraph {
	const fresh = graph_from_document(document);
	const custom_nodes = draft.nodes.filter(node => is_behavior(node.kind));
	const custom_ids = new Set(custom_nodes.map(node => node.id));
	const nodes = [...fresh.nodes.filter(node => !is_behavior(node.kind)), ...custom_nodes];
	const node_ids = new Set(nodes.map(node => node.id));
	const connections = [
		...fresh.connections.filter(edge => !custom_ids.has(edge.to)),
		...draft.connections.filter(edge => custom_ids.has(edge.to)),
	].filter(edge => node_ids.has(edge.from) && node_ids.has(edge.to));
	return { nodes, connections };
}

export function Workbench({ tool, groups, on_save, on_back, storage_blocked, storage_error, on_replace_unreadable, on_dismiss_error, sync }: {
	tool: AppDocument;
	groups: AppGroup[];
	on_save: (document: AppDocument) => void;
	on_back: () => void;
	storage_blocked: boolean;
	storage_error: string | null;
	on_replace_unreadable: () => void;
	on_dismiss_error: () => void;
	sync: SyncState;
}) {
	const [history, set_history] = useState<History<AppDocument>>({ past: [], present: tool, future: [] });
	const document = history.present;
	const [previous_tool, set_previous_tool] = useState(tool);
	if (tool !== previous_tool) {
		set_previous_tool(tool);
		if (history.present === previous_tool || JSON.stringify(history.present) === JSON.stringify(previous_tool)) { set_history({ past: [], present: tool, future: [] }); }
	}
	const [view, set_view] = useState<EditorView>("page");
	const [picker, set_picker] = useState<PickerState | null>(null);
	const [more, set_more] = useState(false);
	const [help, set_help] = useState(false);
	const [error, set_error] = useState<string | null>(null);
	const [notice, set_notice] = useState<string | null>(null);
	const [saving, set_saving] = useState(false);
	const [save_failed, set_save_failed] = useState(false);
	const [graph, set_graph] = useState<LogicGraph>(() => graph_from_document(tool));
	const [graph_dirty, set_graph_dirty] = useState(false);
	const [selected_block, set_selected_block] = useState<string | null>(null);
	const [runtime, set_runtime] = useState(initial_runtime);
	const [preview_enabled, set_preview_enabled] = useState(false);
	const [now, set_now] = useState(0);
	const graph_error = graph_dirty ? validate_connections(document, graph) : null;
	const pending = useRef({ document, tool, on_save, storage_blocked });
	pending.current = { document, tool, on_save, storage_blocked };

	useEffect(() => { set_now(Date.now()); }, []);
	useEffect(() => {
		if (storage_blocked || document === tool || JSON.stringify(document) === JSON.stringify(tool)) { return; }
		set_saving(true);
		const timer = window.setTimeout(() => {
			try { on_save(checked_document(document)); set_saving(false); set_save_failed(false); }
			catch (failure) { set_error(message(failure)); set_saving(false); set_save_failed(true); }
		}, 350);
		return () => window.clearTimeout(timer);
	}, [document, tool, storage_blocked, on_save]);
	useEffect(() => () => {
		const latest = pending.current;
		if (latest.storage_blocked || latest.document === latest.tool || JSON.stringify(latest.document) === JSON.stringify(latest.tool)) { return; }
		try { latest.on_save(checked_document(latest.document)); }
		catch (failure) { console.warn("Could not save the last page edit:", failure); }
	}, []);
	useEffect(() => { set_graph(current => graph_dirty ? merge_draft(document, current) : graph_from_document(document)); }, [document, graph_dirty]);
	useEffect(() => { set_runtime(initial_runtime()); set_preview_enabled(document.enabled ?? false); }, [document, view]);
	useEffect(() => {
		if (view !== "preview") { return; }
		const timer = window.setInterval(() => {
			const timestamp = Date.now();
			set_now(timestamp);
			set_runtime(state => transition(document, state, { type: "tick", now: timestamp }));
		}, 500);
		return () => window.clearInterval(timer);
	}, [document, view]);
	useEffect(() => {
		const key = (event: KeyboardEvent) => {
			const target = event.target as HTMLElement;
			if (event.key === "Escape") { set_more(false); set_help(false); set_selected_block(null); }
			if (event.key === "/" && view === "page" && !picker && !["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName) && !target.isContentEditable) {
				event.preventDefault();
				set_picker({ scope: "all" });
			}
		};
		window.addEventListener("keydown", key);
		return () => window.removeEventListener("keydown", key);
	}, [view, picker]);
	useEffect(() => {
		const warn = (event: BeforeUnloadEvent) => { if (graph_dirty || save_failed) { event.preventDefault(); } };
		window.addEventListener("beforeunload", warn);
		return () => window.removeEventListener("beforeunload", warn);
	}, [graph_dirty, save_failed]);

	function commit(next: AppDocument) {
		try { set_history(current => change(current, checked_document(next))); set_error(null); }
		catch (failure) { set_error(message(failure)); }
	}
	function edit_graph(next: LogicGraph) {
		const prepared = fill_single_sources(merge_draft(document, next));
		set_graph(prepared);
		set_graph_dirty(true);
		set_error(null);
		const issue = validate_connections(document, prepared);
		if (issue) { return; }
		try {
			const next_document = compile_graph(document, prepared);
			set_history(current => change(current, next_document));
			set_graph(graph_from_document(next_document));
			set_graph_dirty(false);
		} catch (failure) { set_error(message(failure)); }
	}
	function discard_graph() {
		set_graph(graph_from_document(document));
		set_graph_dirty(false);
		set_selected_block(null);
		set_error(null);
	}
	function can_leave() {
		if (graph_dirty && !window.confirm("Discard the unfinished block changes? Your saved page will stay unchanged.")) { return false; }
		if (graph_dirty) { discard_graph(); }
		return true;
	}
	function show(next: EditorView) {
		if (next !== view && !can_leave()) { return; }
		set_view(next);
		set_more(false);
		set_notice(null);
	}
	function back() { if (can_leave()) { on_back(); } }
	function pick(kind: CreationKind) {
		try {
			set_error(null);
			if (is_page_kind(kind)) {
				const next = insert_page_block(document, kind, picker?.before);
				commit(next);
				if (kind === "schedule") { set_notice("Added the schedule and app blocker. It stays off until you enable it on your iPhone."); }
				if (kind === "screen_time" && !document.blocks.some(block => block.type === "timer" || block.type === "schedule")) { set_notice("Added a 25-minute focus timer for this blocker. Change its duration right on the page."); }
			} else {
				const base = graph_dirty ? graph : graph_from_document(document);
				const next = add_connected_block(base, kind);
				set_selected_block(next.selected);
				edit_graph(next.graph);
			}
			set_picker(null);
		} catch (failure) { set_error(message(failure)); set_picker(null); }
	}
	function export_page() {
		try {
			const url = URL.createObjectURL(new Blob([serialize_document(document)], { type: "application/json" }));
			const link = window.document.createElement("a");
			link.href = url;
			link.download = `${document.name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "page"}.pocketwork.json`;
			link.click();
			window.setTimeout(() => URL.revokeObjectURL(url), 1000);
			set_more(false);
		} catch (failure) { set_error(message(failure)); }
	}
	function dispatch(action: RuntimeAction) { set_runtime(state => transition(document, state, action)); }

	const has_native_preview = document.blocks.some(block => block.type !== "note" || Boolean(block.text));
	const save_label = storage_blocked ? "Storage needs attention" : save_failed ? "Not saved" : graph_dirty ? "Block needs a setting" : saving ? "Saving…" : document.schema_version === 4 && !native_format_four ? "Saved here · local-only blocks" : sync === "syncing" ? "Syncing…" : sync === "error" ? "Saved here · sync paused" : sync === "synced" ? "Saved & synced" : "Saved on this browser";
	return <div className="creation-workspace"><a className="skip-link" href="#page-editor">Skip to page</a>
		<header className="creation-topbar"><nav className="creation-breadcrumb" aria-label="Breadcrumb"><Button variant="quiet" onClick={back}><ArrowLeft /><span>My pages</span></Button><ChevronRight /><span>{document.name}</span></nav><div className="creation-topbar-actions"><span className={`creation-save ${save_failed || storage_blocked || graph_dirty ? "is-error" : ""}`} role="status"><Check />{save_label}</span><Button variant={view === "preview" ? "primary" : "quiet"} aria-pressed={view === "preview"} onClick={() => show(view === "preview" ? "page" : "preview")}><Play />{view === "preview" ? "Back to editing" : "Preview"}</Button><div className="creation-more"><Button variant="quiet" aria-label="More page options" aria-expanded={more} onClick={() => set_more(!more)}><MoreHorizontal /></Button>{more && <div className="creation-more-menu"><Button variant="quiet" onClick={export_page}><Download />Export page</Button><Button variant="quiet" onClick={() => { set_help(true); set_more(false); }}><Smartphone />Use on iPhone</Button></div>}</div></div></header>
		<div className="creation-toolbar creation-toolbar-quiet"><span>Page editor</span><div className="history-controls"><Button variant="quiet" aria-label="Undo edit" disabled={!history.past.length || graph_dirty || storage_blocked} onClick={() => set_history(undo)}><Undo2 /></Button><Button variant="quiet" aria-label="Redo edit" disabled={!history.future.length || graph_dirty || storage_blocked} onClick={() => set_history(redo)}><Redo2 /></Button></div></div>
		{(error ?? storage_error) && <div className="alert-banner" role="alert"><Info /><span>{error ?? storage_error}</span>{storage_blocked && <Button onClick={on_replace_unreadable}>Replace unreadable data</Button>}<Button variant="quiet" aria-label="Dismiss error" onClick={() => { set_error(null); on_dismiss_error(); }}><X /></Button></div>}
		{notice && <div className="notice-banner" role="status"><Check /><span>{notice}</span><Button variant="quiet" aria-label="Dismiss message" onClick={() => set_notice(null)}><X /></Button></div>}
		{help && <div className="creation-help"><div>{document.schema_version === 4 && !native_format_four ? <><strong>This draft needs a compatible phone update.</strong><p>These new blocks currently run only in the browser. Sign-in and export do not make them compatible with the installed iPhone app. Any earlier phone version of this page stays unchanged.</p></> : <><strong>Your page follows your account.</strong><p>Open Pocketwork on your iPhone with the same sign-in to sync. Choose apps, grant permissions, and enable schedules there. Browser previews never change phone restrictions. Without sign-in, export the page and import it on the phone.</p></>}</div><Button variant="quiet" aria-label="Close iPhone help" onClick={() => set_help(false)}><X /></Button></div>}
		<main id="page-editor">
			{document.schema_version === 4 && !native_format_four && <div className="creation-help"><Info /><p>Saved only here until the compatible iPhone update is available. Existing phone pages stay unchanged.</p></div>}
			{view === "page" && <RoutinePage document={document} groups={groups} graph={graph} selected={selected_block} graph_dirty={graph_dirty} graph_error={graph_error} on_change={commit} on_graph_change={edit_graph} on_select={set_selected_block} on_discard_graph={discard_graph} on_add={(scope, before) => set_picker({ scope, before })} on_error={set_error} />}
			{view === "preview" && <div className={`creation-preview ${has_native_preview ? "has-native-preview" : ""}`}><div className="preview-explanation"><span className="document-eyebrow">TRY YOUR PAGE</span><h1>A test run. Nothing on your phone changes.</h1><p>Buttons, entries, and switches here are simulated. Test data resets when you leave this preview.</p>{has_native_preview && <><Button variant="quiet" onClick={() => { set_runtime(initial_runtime()); set_preview_enabled(document.enabled ?? false); }}><RotateCcw />Reset timer</Button>{runtime.status === "running" && <Button variant="quiet" onClick={() => dispatch({ type: "tick", now: runtime.ends_at! })}>Simulate timer finishing</Button>}<p role="status">{runtime.status === "running" ? "Session running · simulated" : runtime.status === "completed" ? "Session completed" : "Ready when you are"}</p>{runtime.events.length > 0 && <ol className="event-log">{runtime.events.slice(-3).map((event, index) => <li key={index}>{event.message}</li>)}</ol>}</>}</div>{has_native_preview && <PhonePreview document={{ ...document, ...(document.enabled !== undefined ? { enabled: preview_enabled } : {}) }} runtime={runtime} now={now} selected_id={null} interactive on_select={() => undefined} dispatch={dispatch} on_toggle_enabled={set_preview_enabled} />}{document.behaviors && <div className="creation-behavior-preview"><BehaviorRunner graph={graph_from_document(document)} simple /></div>}</div>}
		</main>
		{picker && <BlockPicker scope={picker.scope} on_close={() => set_picker(null)} on_pick={pick} />}
	</div>;
}
