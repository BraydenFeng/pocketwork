"use client";

import type { ReactNode } from "react";
import { ChevronDown, Plus, Trash2 } from "lucide-react";
import { is_behavior, type BehaviorConfig } from "@/lib/behaviors";
import { branch_has_else, connected_summary, generated_storage, input_name, node_name, numeric_fields, page_section, remove_connected_block, set_source, source_options, type PageSection } from "@/lib/creation";
import { node_catalog, node_ports, type LogicGraph, type LogicNode } from "@/lib/logic-graph";
import { optional_input } from "@/lib/primitives";
import { ALL_DAYS, DAY_LABELS } from "@/lib/schedule";
import { BuilderSettings } from "./builder-settings";
import { BlockIcon, InlineText, NumberField } from "./creation-controls";
import { PrimitiveSettings } from "./primitive-settings";
import { Button } from "./ui";

export function RoutineBlocks({ graph, selected, section, leading_block, native_background = false, on_select, on_change, on_add, on_error }: {
	graph: LogicGraph;
	selected: string | null;
	section: PageSection;
	leading_block?: ReactNode;
	native_background?: boolean;
	on_select: (id: string | null) => void;
	on_change: (graph: LogicGraph) => void;
	on_add: () => void;
	on_error: (message: string) => void;
}) {
	const visible_blocks = graph.nodes.filter(node => is_behavior(node.kind) && page_section(node.kind) === section && !generated_storage(graph, node));
	function update(node: LogicNode) {
		const ports = node_ports(node);
		on_change({
			...graph,
			nodes: graph.nodes.map(item => item.id === node.id ? node : item),
			connections: (node.kind === "change_value" && node.config?.change === "reset"
				? graph.connections.filter(edge => edge.to !== node.id || edge.input !== "amount")
				: graph.connections).filter(edge => edge.to !== node.id || ports.inputs.includes(edge.input)).filter(edge => edge.from !== node.id || ports.outputs.includes(edge.output)),
		});
	}
	function remove(node: LogicNode) {
		const used_by = new Set(graph.connections.filter(edge => edge.from === node.id).map(edge => edge.to)).size;
		if (used_by && !window.confirm(`Remove ${node_name(node)}? ${used_by} other block${used_by === 1 ? " uses" : "s use"} it and will need a new setting.`)) { return; }
		try { on_change(remove_connected_block(graph, node.id)); }
		catch (failure) { on_error(failure instanceof Error ? failure.message : "Could not remove this block."); return; }
		on_select(null);
	}
	function set_else(node: LogicNode, enabled: boolean) {
		const users = new Set(graph.connections.filter(edge => edge.from === node.id && edge.output === "no").map(edge => edge.to)).size;
		if (!enabled && users && !window.confirm(`Remove Else? ${users} other block${users === 1 ? " uses" : "s use"} it and will need a new When setting.`)) { return; }
		on_change({
			...graph,
			nodes: graph.nodes.map(item => item.id === node.id ? { ...item, config: { ...item.config!, else_enabled: enabled ? true : undefined } } : item),
			connections: enabled ? graph.connections : graph.connections.filter(edge => edge.from !== node.id || edge.output !== "no"),
		});
	}
	function input_field(node: LogicNode, input: string) {
		const options = source_options(graph, node.id, input);
		const edge = graph.connections.find(entry => entry.to === node.id && entry.input === input);
		const optional = optional_input({ kind: node.kind as Parameters<typeof optional_input>[0]["kind"], config: node.config! }, input);
		const label = node.kind === "record" ? `${node.config?.fields?.find(field => field.id === input)?.label ?? "Value"} from` : input_name(node.kind, input);
		return <label key={input} className="block-property"><span>{label}</span><select aria-label={`${label}: ${node_name(node)}`} value={edge ? `${edge.from}:${edge.output}` : ""} onChange={event => {
			try { on_change(set_source(graph, node.id, input, event.target.value)); }
			catch (failure) { on_error(failure instanceof Error ? failure.message : "That block cannot be used here."); }
		}}><option value="">{optional ? ["amount", "duration", "threshold", "target", "minutes"].includes(input) ? "Use the fixed value above" : "None" : "Choose a block…"}</option>{options.map(option => <option key={option.id} value={option.id}>{option.label}</option>)}</select>{!options.length && !optional && <span className="block-help">Add a compatible block first.</span>}</label>;
	}
	const title = section === "data" ? "Data" : "Routines";
	const description = section === "data" ? "Values, logs, and things you can display." : "Events, conditions, and actions.";
	return <section className="document-system-section" aria-labelledby={`${section}-section-title`}>
		<div className="document-section-heading"><span className="document-eyebrow">{title.toUpperCase()}</span><h2 id={`${section}-section-title`}>{title}</h2><p>{description}</p></div>
		{section === "routines" && (leading_block || visible_blocks.length > 0) && <p className="document-runtime-note">{native_background ? "This block setup runs as a native background home allowance on your iPhone." : "Custom routines run while this page is open. Native schedules keep running on iPhone."}</p>}
		{!leading_block && visible_blocks.length === 0 && <p className="document-section-empty">No {section} yet.</p>}
		<div className="document-logic-blocks">{leading_block}{visible_blocks.map(node => {
			const open = selected === node.id;
			return <section key={node.id} className={`document-logic-block ${open ? "is-open" : ""}`}>
				<button type="button" className="document-logic-heading" aria-expanded={open} aria-label={`Edit ${node_name(node)}`} onClick={() => on_select(open ? null : node.id)}><BlockIcon kind={node.kind} /><span><strong>{node_name(node)}</strong><small>{connected_summary(graph, node)}</small></span><span className="document-logic-kind">{node_catalog[node.kind].title}</span><ChevronDown /></button>
				{open && <div className="document-logic-body"><label className="block-property"><span>Name</span><InlineText label={`Name for ${node_name(node)}`} value={node.kind === "branch" && node.config?.label === "If / else" ? "If" : node.config?.label ?? ""} placeholder={node_catalog[node.kind].title} on_commit={label => update({ ...node, config: { ...node.config!, label } })} /></label>
					<NodeSettings node={node} graph={graph} native_background={native_background} patch={patch => update({ ...node, config: { ...node.config!, ...patch } })} />
					{["elapsed_timer", "variable"].includes(node.kind)
						? <details className="document-details"><summary>Controls (optional)</summary><div className="block-properties">{node_ports(node).inputs.map(input => input_field(node, input))}</div></details>
						: node_ports(node).inputs.filter(input => !(node.kind === "change_value" && input === "amount" && node.config?.change === "reset")).map(input => input_field(node, input))}
					{node.kind === "branch" && <BranchPaths graph={graph} node={node} on_change={enabled => set_else(node, enabled)} />}
					<div className="document-logic-footer"><span className="supporting">{node_catalog[node.kind].detail}</span><Button variant="danger" onClick={() => remove(node)}><Trash2 />Remove block</Button></div>
				</div>}
			</section>;
		})}</div>
		<button type="button" className="document-add document-section-add" onClick={on_add}><Plus /><span>Add {section === "data" ? "data" : "routine"} block</span></button>
	</section>;
}

function BranchPaths({ graph, node, on_change }: { graph: LogicGraph; node: LogicNode; on_change: (enabled: boolean) => void }) {
	const has_else = branch_has_else(graph, node);
	return <div className="branch-paths" role="group" aria-label={`Paths for ${node_name(node)}`}>
		<div className="branch-path"><span><strong>Then</strong><small>Condition is true</small></span></div>
		{has_else
			? <div className="branch-path"><span><strong>Else</strong><small>Condition is false</small></span><Button variant="quiet" onClick={() => on_change(false)}><Trash2 />Remove else</Button></div>
			: <Button variant="quiet" className="branch-add" onClick={() => on_change(true)}><Plus />Add else</Button>}
	</div>;
}

function NodeSettings({ node, graph, native_background, patch }: { node: LogicNode; graph: LogicGraph; native_background: boolean; patch: (config: Partial<BehaviorConfig>) => void }) {
	const config = node.config!;
	const interval_unit = config.interval_unit ?? "hours";
	const interval_max = interval_unit === "minutes" ? 10080 : interval_unit === "hours" ? 168 : 7;
	return <div className="block-properties">
		<PrimitiveSettings node={node} graph={graph} patch={patch} />
		{node.kind === "number_input" && <NumberField label="Initial value" value={config.value} min={-1000000} max={1000000} on_commit={value => patch({ value })} />}
		{node.kind === "progress" && !graph.connections.some(edge => edge.to === node.id && edge.input === "target") && <NumberField label="Target" value={config.value} min={1} max={1000000} on_commit={value => patch({ value })} />}
		{node.kind === "add_allowance" && !graph.connections.some(edge => edge.to === node.id && edge.input === "minutes") && <NumberField label="Minutes to award" value={config.minutes} min={1} max={1440} unit="minutes" on_commit={minutes => patch({ minutes })} />}
		{["count", "goal", "compare", "app_usage"].includes(node.kind) && !graph.connections.some(edge => edge.to === node.id && edge.input === "threshold") && <NumberField label={node.kind === "count" ? "Add each time" : node.kind === "goal" ? "Target" : "Value"} value={config.value} min={-1000000} max={1000000} integer={false} on_commit={value => patch({ value })} />}
		{node.kind === "compare" && <label className="block-property"><span>Condition</span><select value={config.operator} onChange={event => patch({ operator: event.target.value as BehaviorConfig["operator"] })}><option value="gte">At least</option><option value="gt">More than</option><option value="eq">Exactly</option><option value="lt">Less than</option><option value="lte">At most</option></select></label>}
		{node.kind === "delay" && <NumberField label="Wait" value={config.minutes} min={1} max={1440} unit="minutes" on_commit={minutes => patch({ minutes })} />}
		{node.kind === "clock" && <><label className="block-property"><span>At this time</span><input type="time" value={config.time} onChange={event => { if (event.target.value) { patch({ time: event.target.value }); } }} /></label><div className="day-picker" role="group" aria-label="Event days">{ALL_DAYS.map(day => <button type="button" key={day} aria-pressed={config.days.includes(day)} onClick={() => { const days = config.days.includes(day) ? config.days.filter(value => value !== day) : [...config.days, day].sort(); if (days.length) { patch({ days }); } }}>{DAY_LABELS[day - 1]}</button>)}</div></>}
		{node.kind === "interval" && <><div className="interval-setting"><NumberField label="Every" value={config.value} min={1} max={interval_max} on_commit={value => patch({ value })} /><label className="block-property"><span>Unit</span><select aria-label="Interval unit" value={interval_unit} onChange={event => { const interval_unit = event.target.value as NonNullable<BehaviorConfig["interval_unit"]>; const maximum = interval_unit === "minutes" ? 10080 : interval_unit === "hours" ? 168 : 7; patch({ interval_unit, value: Math.min(config.value, maximum) }); }}><option value="minutes">minutes</option><option value="hours">hours</option><option value="days">days</option></select></label></div><p className="block-help">Runs while this page is open. If an interval passes while it is closed, it runs once when you return.</p></>}
		{node.kind === "reminder" && <label className="block-property"><span>Message</span><InlineText label="Message" value={config.message} max_length={240} on_commit={message => patch({ message })} /></label>}
		{["chart", "aggregate"].includes(node.kind) && <label className="block-property"><span>Number to use</span><select aria-label={`Numeric field: ${node_name(node)}`} value={config.field ?? "value"} onChange={event => patch({ field: event.target.value })}>{!numeric_fields(graph, node).some(field => field.id === (config.field ?? "value")) && <option value={config.field ?? "value"}>{config.field ?? "value"} (missing)</option>}{numeric_fields(graph, node).map(field => <option key={field.id} value={field.id}>{field.label}</option>)}</select></label>}
		{node.kind === "app_gate" && <><label className="block-property"><span>App groups</span><InlineText label="App groups to control" value={(config.groups ?? []).join(", ")} placeholder="Social, Games" max_length={400} on_commit={value => patch({ groups: [...new Set(value.split(",").map(name => name.trim()).filter(Boolean))] })} /></label><p>Separate names with commas. Choose the actual apps privately on your iPhone.</p></>}
		{["chart", "number_input", "progress", "add_allowance"].includes(node.kind) ? null : node.kind === "aggregate" ? <label className="block-property"><span>Calculate</span><select value={config.operation ?? "sum"} onChange={event => patch({ operation: event.target.value as BehaviorConfig["operation"] })}>{["sum", "average", "minimum", "maximum", "count"].map(value => <option value={value} key={value}>{value}</option>)}</select></label> : <BuilderSettings node={node} patch={patch} advanced={false} />}
		{["location", "arrive", "leave"].includes(node.kind) && <p className="block-help">{native_background && node.kind === "location" ? "Uses the saved location on your iPhone as part of this background allowance." : "Uses the single saved location on your iPhone. This event currently checks while the page is open."}</p>}
		{node.kind === "add_allowance" && <p className="block-help">Requires an enabled home allowance on the phone. Connect a number to update the reward as that number changes.</p>}
		{node.kind === "app_usage" && <p className="block-help">Uses Apple Screen Time. Minutes are counted by your home allowance; History contains up to 30 days for charts and tables.</p>}
	</div>;
}
