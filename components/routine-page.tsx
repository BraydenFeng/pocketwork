"use client";

import { useState } from "react";
import { ArrowDown, ArrowUp, GripVertical, Plus, Smartphone, Trash2 } from "lucide-react";
import { is_behavior } from "@/lib/behaviors";
import { is_block_authored_home_allowance } from "@/lib/background-allowance";
import { describe_shield, new_id, shield_mode, type AppDocument, type Block } from "@/lib/document";
import { generated_storage, remove_page_block } from "@/lib/creation";
import type { LogicGraph } from "@/lib/logic-graph";
import { home_allowance_block_id } from "@/lib/page-blocks";
import { ALL_DAYS, DAY_LABELS, WEEKDAYS } from "@/lib/schedule";
import type { AppGroup } from "@/lib/library";
import { BlockIcon, InlineText, NumberField } from "./creation-controls";
import { HomeAllowanceBlock } from "./home-allowance";
import { RoutineBlocks } from "./routine-blocks";
import { Button, Toggle } from "./ui";

type PickerScope = "all" | "page" | "routines" | "data";

export function RoutinePage({ document, groups, graph, selected, graph_dirty, graph_error, disabled, on_change, on_graph_change, on_select, on_discard_graph, on_add, on_error, on_draft_error }: {
	document: AppDocument;
	groups: AppGroup[];
	graph: LogicGraph;
	selected: string | null;
	graph_dirty: boolean;
	graph_error: string | null;
	disabled: boolean;
	on_change: (document: AppDocument) => void;
	on_graph_change: (graph: LogicGraph) => void;
	on_select: (id: string | null) => void;
	on_discard_graph: () => void;
	on_add: (scope: PickerScope, before?: string) => void;
	on_error: (message: string) => void;
	on_draft_error: (message: string | null) => void;
}) {
	const [menu, set_menu] = useState<string | null>(null);
	const [dragged, set_dragged] = useState<string | null>(null);
	const block_authored_allowance = is_block_authored_home_allowance(document);
	const custom_blocks = graph.nodes.filter(node => is_behavior(node.kind) && !generated_storage(graph, node));
	const page_blocks = document.home_allowance ? document.blocks.filter(block => !["schedule", "screen_time"].includes(block.type)) : document.blocks;
	function update(block: Block) { on_change({ ...document, blocks: document.blocks.map(item => item.id === block.id ? block : item) }); }
	function remove(id: string) { try { on_change(remove_page_block(document, id)); set_menu(null); } catch (error) { on_error(error instanceof Error ? error.message : "Could not remove this block."); } }
	function drop(id: string) {
		if (!dragged || dragged === id) { return; }
		const ids = page_blocks.map(block => block.id); const from = ids.indexOf(dragged); const to = ids.indexOf(id);
		if (from >= 0 && to >= 0) { const [moved] = ids.splice(from, 1); ids.splice(to, 0, moved); const by_id = new Map(document.blocks.map(block => [block.id, block])); let index = 0; const blocks = document.blocks.map(block => page_blocks.some(page_block => page_block.id === block.id) ? by_id.get(ids[index++])! : block); on_change({ ...document, blocks }); }
		set_dragged(null);
	}
	function move(id: string, direction: -1 | 1) {
		const index = page_blocks.findIndex(block => block.id === id);
		const destination = index + direction;
		if (index < 0 || destination < 0 || destination >= page_blocks.length) { return; }
		const ids = page_blocks.map(block => block.id);
		[ids[index], ids[destination]] = [ids[destination], ids[index]];
		const by_id = new Map(document.blocks.map(block => [block.id, block])); let visible_index = 0;
		on_change({ ...document, blocks: document.blocks.map(block => page_blocks.some(page_block => page_block.id === block.id) ? by_id.get(ids[visible_index++])! : block) });
	}
	return <div className="routine-document">
		<div className="document-sigil" aria-hidden="true"><BlockIcon kind={document.home_allowance ? "screen_time" : "note"} /></div>
		<h1 className="document-title" aria-label={document.name}><InlineText label="Page name" value={document.name} required wrap placeholder="Untitled page" on_commit={name => on_change({ ...document, name })} /></h1>
		<InlineText label="Description" value={document.description} placeholder="Add a description…" multiline max_length={200} on_commit={description => on_change({ ...document, description })} className="document-description" />
		<div className="document-properties"><span><Smartphone />{document.home_allowance ? "Runs on your iPhone" : document.blocks.some(block => block.type === "schedule") ? "Scheduled on iPhone" : document.blocks.some(block => block.type === "timer") ? "Start when you need it" : "Your own little tool"}</span><span>{document.home_allowance ? "Los Angeles time" : custom_blocks.length ? `${custom_blocks.length} custom block${custom_blocks.length === 1 ? "" : "s"}` : "Changes save automatically"}</span></div>
		<section className="document-system-section document-page-section" aria-labelledby="page-section-title">
			<div className="document-section-heading"><span className="document-eyebrow">PAGE</span><h2 id="page-section-title">Page</h2><p>Text, controls, and anything you want to see.</p></div>
			{page_blocks.length === 0 && <p className="document-section-empty">Nothing on this page yet.</p>}
			<ol className="document-blocks" aria-label="Page blocks">{page_blocks.map((block, index) => <li key={block.id} className="document-row" data-block-id={block.id} onDragOver={event => { if (dragged) { event.preventDefault(); } }} onDrop={() => drop(block.id)}>
				<div className="block-gutter"><button type="button" aria-label={`Insert before ${block.title}`} onClick={() => on_add("page", block.id)}><Plus /></button><button type="button" draggable aria-label={`Actions for ${block.title}`} aria-expanded={menu === block.id} onDragStart={event => { set_dragged(block.id); event.dataTransfer.setData("text/plain", block.id); }} onDragEnd={() => set_dragged(null)} onClick={() => set_menu(menu === block.id ? null : block.id)}><GripVertical /></button></div>
				{menu === block.id && <div className="block-action-menu" onKeyDown={event => { if (event.key === "Escape") { set_menu(null); } }}><Button variant="quiet" disabled={index === 0} onClick={() => { move(block.id, -1); set_menu(null); }}><ArrowUp />Move up</Button><Button variant="quiet" disabled={index === page_blocks.length - 1} onClick={() => { move(block.id, 1); set_menu(null); }}><ArrowDown />Move down</Button><Button variant="danger" onClick={() => remove(block.id)}><Trash2 />Remove block</Button></div>}
				<NativeBlock block={block} document={document} groups={groups} on_change={update} on_document={on_change} on_add={() => on_add("all", block.id)} />
			</li>)}</ol>
			<button type="button" className="document-add" onClick={() => on_add("all")}><Plus /><span>Add a block</span><kbd aria-hidden="true">/</kbd></button>
		</section>
		{graph_dirty && graph_error && <div className="document-draft-warning" role="alert"><div><strong>This block needs one more setting.</strong><p>{graph_error}</p></div><Button variant="quiet" onClick={on_discard_graph}>Discard unfinished block</Button></div>}
		<RoutineBlocks graph={graph} selected={selected} section="routines" native_background={block_authored_allowance} leading_block={document.home_allowance && !block_authored_allowance ? <HomeAllowanceBlock document={document} open={selected === home_allowance_block_id} disabled={disabled} on_toggle={() => on_select(selected === home_allowance_block_id ? null : home_allowance_block_id)} on_change={on_change} on_draft_error={on_draft_error} /> : undefined} on_select={on_select} on_change={on_graph_change} on_add={() => on_add("routines")} on_error={on_error} />
		<RoutineBlocks graph={graph} selected={selected} section="data" on_select={on_select} on_change={on_graph_change} on_add={() => on_add("data")} on_error={on_error} />
		<div className="document-bottom-note">Type / in an empty text block to add anything.</div>
	</div>;
}

function NativeBlock({ block, document, groups, on_change, on_document, on_add }: { block: Block; document: AppDocument; groups: AppGroup[]; on_change: (block: Block) => void; on_document: (document: AppDocument) => void; on_add: () => void }) {
	const [new_group, set_new_group] = useState("");
	const title = <InlineText label={`Block title: ${block.title}`} value={block.title} required on_commit={title => on_change({ ...block, title })} className="block-title-input" />;
	if (block.type === "note") { return <div className="document-text-block">{block.title !== "Text" && title}<InlineText label={`Text: ${block.title}`} value={block.text} multiline max_length={1000} placeholder="Write something, or press / to add a block…" on_commit={text => on_change({ ...block, text })} on_slash={on_add} /></div>; }
	if (block.type === "heading") { return <div className="document-heading-block">{title}<InlineText label={`Supporting text: ${block.title}`} value={block.subtitle} placeholder="Add supporting text…" multiline max_length={200} on_commit={subtitle => on_change({ ...block, subtitle })} /></div>; }
	if (block.type === "checklist") { return <div className="document-checklist">{title}{block.items.map((item, index) => <div className="document-task" key={item.id}><span className="empty-checkbox" aria-hidden="true" /><InlineText label={`Task ${index + 1}: ${block.title}`} value={item.text} required placeholder="To-do" on_commit={text => on_change({ ...block, items: block.items.map(entry => entry.id === item.id ? { ...entry, text } : entry) })} /><Button variant="quiet" aria-label={`Remove task ${index + 1}: ${block.title}`} disabled={block.items.length === 1} onClick={() => on_change({ ...block, items: block.items.filter(entry => entry.id !== item.id) })}><Trash2 /></Button></div>)}<Button variant="quiet" disabled={block.items.length >= 20} onClick={() => on_change({ ...block, items: [...block.items, { id: new_id(), text: "New task" }] })}><Plus />Add task</Button></div>; }
	return <section className="document-capability"><div className="capability-title"><BlockIcon kind={block.type} />{title}</div>
		{block.type === "timer" && <><NumberField label="Session length" value={block.minutes} min={15} max={120} unit="minutes" on_commit={minutes => on_change({ ...block, minutes })} /><p className="supporting">Starts when you press Start. Ends when the timer finishes or you stop it.</p><details className="document-details"><summary>Session options</summary><Toggle label="Notify on completion" description="A notification on your iPhone" checked={document.rules.notify_on_complete} on_change={notify_on_complete => on_document({ ...document, rules: { ...document.rules, notify_on_complete } })} /></details></>}
		{block.type === "counter" && <NumberField label="Target" value={block.target} min={1} max={1000} on_commit={target => on_change({ ...block, target })} />}
		{block.type === "schedule" && <><div className="day-picker" role="group" aria-label="Days of the week">{ALL_DAYS.map(day => <button type="button" key={day} aria-pressed={block.days.includes(day)} onClick={() => { const days = block.days.includes(day) ? block.days.filter(value => value !== day) : [...block.days, day].sort(); if (days.length) { on_change({ ...block, days }); } }}>{DAY_LABELS[day - 1]}</button>)}</div><div className="document-inline-actions"><Button variant="quiet" onClick={() => on_change({ ...block, days: WEEKDAYS })}>Weekdays</Button><Button variant="quiet" onClick={() => on_change({ ...block, days: ALL_DAYS })}>Every day</Button></div><div className="document-time-fields"><label>From<input type="time" aria-label="Starts" value={block.start} onChange={event => { if (event.target.value) { on_change({ ...block, start: event.target.value }); } }} /></label><span>to</span><label>Until<input type="time" aria-label="Ends" value={block.end} onChange={event => { if (event.target.value) { on_change({ ...block, end: event.target.value }); } }} /></label></div><p className="supporting">Repeats while enabled on your iPhone. Outside this window, this routine releases its restrictions. An earlier end time means the next day.</p><span className="capability-state">{document.enabled ? "Enabled on your account" : "Off until you enable it on your iPhone"}</span></>}
		{block.type === "screen_time" && <><label className="document-select"><span>What happens</span><select aria-label="App blocking mode" value={shield_mode(block)} onChange={event => { const mode = event.target.value as "block" | "allow_only" | "limit"; on_change({ ...block, mode, groups: mode !== "block" && !block.groups?.length ? [groups[0]?.name ?? "Distractions"] : block.groups, limit_minutes: mode === "limit" ? block.limit_minutes ?? 30 : undefined }); }}><option value="block">Block these apps</option><option value="allow_only">Allow only these apps</option><option value="limit">Give these apps a time limit</option></select></label>{shield_mode(block) === "limit" && <NumberField label="Minutes before blocking" value={block.limit_minutes ?? 30} min={15} max={1440} unit="minutes" on_commit={limit_minutes => on_change({ ...block, limit_minutes })} />}
			<div className="document-group-picks" role="group" aria-label="App groups">{[...new Set([...groups.map(group => group.name), ...(block.groups ?? [])])].map(name => <label key={name}><input type="checkbox" checked={(block.groups ?? []).some(value => value.toLowerCase() === name.toLowerCase())} onChange={event => on_change({ ...block, groups: event.target.checked ? [...(block.groups ?? []), name] : (block.groups ?? []).filter(value => value.toLowerCase() !== name.toLowerCase()) })} />{name}</label>)}</div>
			<details className="document-details"><summary>Add an app group</summary><form className="document-inline-actions" onSubmit={event => { event.preventDefault(); const name = new_group.trim(); if (name && !(block.groups ?? []).some(value => value.toLowerCase() === name.toLowerCase())) { on_change({ ...block, groups: [...(block.groups ?? []), name] }); set_new_group(""); } }}><input aria-label="New group name" placeholder="Social, games, work…" maxLength={40} value={new_group} onChange={event => set_new_group(event.target.value)} /><Button type="submit" disabled={!new_group.trim()}>Add group</Button></form></details>
			<p className="supporting">{describe_shield(block)}. Choose the actual apps privately on your iPhone.</p><p className="capability-state">{document.rules.block_during_focus ? `Applies only while your ${document.blocks.some(item => item.type === "schedule") ? "schedule is active" : "focus timer is running"}.` : "Blocking is off for this routine."}</p>{!document.rules.block_during_focus && document.blocks.some(item => item.type === "timer" || item.type === "schedule") && <Button onClick={() => on_document({ ...document, rules: { ...document.rules, block_during_focus: true } })}>Enable blocking during this routine</Button>}
		</>}
	</section>;
}
