"use client";

import { ChevronDown, Plus, Trash2 } from "lucide-react";
import { is_behavior, type BehaviorConfig } from "@/lib/behaviors";
import { connected_summary, generated_storage, input_name, node_name, numeric_fields, page_section, set_source, source_options, type PageSection } from "@/lib/creation";
import { node_catalog, node_ports, type LogicGraph, type LogicNode } from "@/lib/logic-graph";
import { optional_input } from "@/lib/primitives";
import { ALL_DAYS, DAY_LABELS } from "@/lib/schedule";
import { BuilderSettings } from "./builder-settings";
import { BlockIcon, InlineText, NumberField } from "./creation-controls";
import { PrimitiveSettings } from "./primitive-settings";
import { Button } from "./ui";

export function RoutineBlocks({ graph, selected, section, on_select, on_change, on_add, on_error }: {
	graph: LogicGraph;
	selected: string | null;
	section: PageSection;
	on_select: (id: string | null) => void;
	on_change: (graph: LogicGraph) => void;
	on_add: () => void;
	on_error: (message: string) => void;
}) {
	const visible_blocks = graph.nodes.filter(node => is_behavior(node.kind) && page_section(node.kind) === section && !generated_storage(graph, node));
	function update(node: LogicNode) {
		on_change({
			...graph,
			nodes: graph.nodes.map(item => item.id === node.id ? node : item),
			connections: node.kind === "change_value" && node.config?.change === "reset"
				? graph.connections.filter(edge => edge.to !== node.id || edge.input !== "amount")
				: graph.connections,
		});
	}
	function remove(node: LogicNode) {
		if (graph.nodes.some(item => item.kind === "change_value" && item.config?.variable_id === node.id)) {
			on_error("A change block still uses this variable. Choose another variable there first.");
			return;
		}
		const used_by = new Set(graph.connections.filter(edge => edge.from === node.id).map(edge => edge.to)).size;
		if (used_by && !window.confirm(`Remove ${node_name(node)}? ${used_by} other block${used_by === 1 ? " uses" : "s use"} it and will need a new setting.`)) { return; }
		on_change({ ...graph, nodes: graph.nodes.filter(item => item.id !== node.id), connections: graph.connections.filter(edge => edge.from !== node.id && edge.to !== node.id) });
		on_select(null);
	}
	function input_field(node: LogicNode, input: string) {
		const options = source_options(graph, node.id, input);
		const edge = graph.connections.find(entry => entry.to === node.id && entry.input === input);
		const optional = optional_input({ kind: node.kind as Parameters<typeof optional_input>[0]["kind"], config: node.config! }, input);
		const label = node.kind === "record" ? `${node.config?.fields?.find(field => field.id === input)?.label ?? "Value"} from` : input_name(node.kind, input);
		return <label key={input} className="block-property"><span>{label}</span><select aria-label={`${label}: ${node_name(node)}`} value={edge ? `${edge.from}:${edge.output}` : ""} onChange={event => {
			try { on_change(set_source(graph, node.id, input, event.target.value)); }
			catch (failure) { on_error(failure instanceof Error ? failure.message : "That block cannot be used here."); }
		}}><option value="">{optional ? ["amount", "duration", "threshold", "target"].includes(input) ? "Use the fixed value above" : "None" : "Choose a block…"}</option>{options.map(option => <option key={option.id} value={option.id}>{option.label}</option>)}</select>{!options.length && !optional && <span className="block-help">Add a compatible block first.</span>}</label>;
	}
	const title = section === "data" ? "Data" : "Routines";
	const description = section === "data" ? "Values, logs, and things you can display." : "Events, conditions, and actions.";
	return <section className="document-system-section" aria-labelledby={`${section}-section-title`}>
		<div className="document-section-heading"><span className="document-eyebrow">{title.toUpperCase()}</span><h2 id={`${section}-section-title`}>{title}</h2><p>{description}</p></div>
		{section === "routines" && visible_blocks.length > 0 && <p className="document-runtime-note">Custom routines run while this page is open. Native schedules keep running on iPhone.</p>}
		{visible_blocks.length === 0 && <p className="document-section-empty">No {section} yet.</p>}
		<div className="document-logic-blocks">{visible_blocks.map(node => {
			const open = selected === node.id;
			return <section key={node.id} className={`document-logic-block ${open ? "is-open" : ""}`}>
				<button type="button" className="document-logic-heading" aria-expanded={open} aria-label={`Edit ${node_name(node)}`} onClick={() => on_select(open ? null : node.id)}><BlockIcon kind={node.kind} /><span><strong>{node_name(node)}</strong><small>{connected_summary(graph, node)}</small></span><span className="document-logic-kind">{node_catalog[node.kind].title}</span><ChevronDown /></button>
				{open && <div className="document-logic-body"><label className="block-property"><span>Name</span><InlineText label={`Name for ${node_name(node)}`} value={node.config?.label ?? ""} placeholder={node_catalog[node.kind].title} on_commit={label => update({ ...node, config: { ...node.config!, label } })} /></label>
					<NodeSettings node={node} graph={graph} patch={patch => update({ ...node, config: { ...node.config!, ...patch } })} />
					{["elapsed_timer", "variable"].includes(node.kind)
						? <details className="document-details"><summary>Controls (optional)</summary><div className="block-properties">{node_ports(node).inputs.map(input => input_field(node, input))}</div></details>
						: node_ports(node).inputs.filter(input => !(node.kind === "change_value" && input === "amount" && node.config?.change === "reset")).map(input => input_field(node, input))}
					<div className="document-logic-footer"><span className="supporting">{node_catalog[node.kind].detail}</span><Button variant="danger" onClick={() => remove(node)}><Trash2 />Remove block</Button></div>
				</div>}
			</section>;
		})}</div>
		<button type="button" className="document-add document-section-add" onClick={on_add}><Plus /><span>Add {section === "data" ? "data" : "routine"} block</span></button>
	</section>;
}

function NodeSettings({ node, graph, patch }: { node: LogicNode; graph: LogicGraph; patch: (config: Partial<BehaviorConfig>) => void }) {
	const config = node.config!;
	return <div className="block-properties">
		<PrimitiveSettings node={node} graph={graph} patch={patch} />
		{node.kind === "number_input" && <NumberField label="Initial value" value={config.value} min={-1000000} max={1000000} on_commit={value => patch({ value })} />}
		{node.kind === "progress" && !graph.connections.some(edge => edge.to === node.id && edge.input === "target") && <NumberField label="Target" value={config.value} min={1} max={1000000} on_commit={value => patch({ value })} />}
		{node.kind === "add_allowance" && <NumberField label="Minutes to award" value={config.minutes} min={1} max={1440} unit="minutes" on_commit={minutes => patch({ minutes })} />}
		{["count", "goal", "compare", "app_usage"].includes(node.kind) && !graph.connections.some(edge => edge.to === node.id && edge.input === "threshold") && <NumberField label={node.kind === "count" ? "Add each time" : node.kind === "goal" ? "Target" : "Value"} value={config.value} min={-1000000} max={1000000} integer={false} on_commit={value => patch({ value })} />}
		{node.kind === "compare" && <label className="block-property"><span>Condition</span><select value={config.operator} onChange={event => patch({ operator: event.target.value as BehaviorConfig["operator"] })}><option value="gte">At least</option><option value="gt">More than</option><option value="eq">Exactly</option><option value="lt">Less than</option><option value="lte">At most</option></select></label>}
		{node.kind === "delay" && <NumberField label="Wait" value={config.minutes} min={1} max={1440} unit="minutes" on_commit={minutes => patch({ minutes })} />}
		{node.kind === "clock" && <><label className="block-property"><span>At this time</span><input type="time" value={config.time} onChange={event => { if (event.target.value) { patch({ time: event.target.value }); } }} /></label><div className="day-picker" role="group" aria-label="Event days">{ALL_DAYS.map(day => <button type="button" key={day} aria-pressed={config.days.includes(day)} onClick={() => { const days = config.days.includes(day) ? config.days.filter(value => value !== day) : [...config.days, day].sort(); if (days.length) { patch({ days }); } }}>{DAY_LABELS[day - 1]}</button>)}</div></>}
		{node.kind === "reminder" && <label className="block-property"><span>Message</span><InlineText label="Message" value={config.message} max_length={240} on_commit={message => patch({ message })} /></label>}
		{["chart", "aggregate"].includes(node.kind) && <label className="block-property"><span>Number to use</span><select aria-label={`Numeric field: ${node_name(node)}`} value={config.field ?? "value"} onChange={event => patch({ field: event.target.value })}>{!numeric_fields(graph, node).some(field => field.id === (config.field ?? "value")) && <option value={config.field ?? "value"}>{config.field ?? "value"} (missing)</option>}{numeric_fields(graph, node).map(field => <option key={field.id} value={field.id}>{field.label}</option>)}</select></label>}
		{node.kind === "app_gate" && <><label className="block-property"><span>App groups</span><InlineText label="App groups to control" value={(config.groups ?? []).join(", ")} placeholder="Social, Games" max_length={400} on_commit={value => patch({ groups: [...new Set(value.split(",").map(name => name.trim()).filter(Boolean))] })} /></label><p>Separate names with commas. Choose the actual apps privately on your iPhone.</p></>}
		{["chart", "number_input", "progress", "add_allowance"].includes(node.kind) ? null : node.kind === "aggregate" ? <label className="block-property"><span>Calculate</span><select value={config.operation ?? "sum"} onChange={event => patch({ operation: event.target.value as BehaviorConfig["operation"] })}>{["sum", "average", "minimum", "maximum", "count"].map(value => <option value={value} key={value}>{value}</option>)}</select></label> : <BuilderSettings node={node} patch={patch} advanced={false} />}
		{["location", "arrive", "leave"].includes(node.kind) && <p className="block-help">Uses the single saved location on your iPhone. This event currently checks while the page is open.</p>}
		{node.kind === "add_allowance" && <p className="block-help">Requires an enabled home allowance on the phone. Its location and time rules still apply.</p>}
		{node.kind === "app_usage" && <p className="block-help">Uses Apple Screen Time. It currently reads minutes counted by your home allowance. Separate totals for each app are not available.</p>}
	</div>;
}
