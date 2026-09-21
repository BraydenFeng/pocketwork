"use client";


import { ChevronDown, Link2, Plus, Trash2 } from "lucide-react";
import { is_behavior, type BehaviorConfig } from "@/lib/behaviors";
import { connected_summary, input_name, node_name, numeric_fields, set_source, source_options } from "@/lib/creation";
import { node_catalog, node_ports, type LogicGraph, type LogicNode } from "@/lib/logic-graph";
import { ALL_DAYS, DAY_LABELS } from "@/lib/schedule";
import { BlockIcon, InlineText, NumberField } from "./creation-controls";
import { BuilderSettings } from "./builder-settings";
import { Button } from "./ui";
import { optional_input } from "@/lib/primitives";
import { PrimitiveSettings } from "./primitive-settings";
import { page_section, type PageSection } from "@/lib/creation";

export function RoutineConnections({ graph, selected, section, on_select, on_change, on_add, on_page, on_advanced, on_error }: { graph: LogicGraph; section?: PageSection; selected: string | null; on_select: (id: string | null) => void; on_change: (graph: LogicGraph) => void; on_add: () => void; on_page: () => void; on_advanced: () => void; on_error: (message: string) => void }) {
	const visible_nodes = graph.nodes.filter(node => !section || page_section(node.kind) === section);
	function update(node: LogicNode) { on_change({ ...graph, nodes: graph.nodes.map(item => item.id === node.id ? node : item), connections: node.kind === "change_value" && node.config?.change === "reset" ? graph.connections.filter(edge => edge.to !== node.id || edge.input !== "amount") : graph.connections }); }
	function remove(node: LogicNode) {
		if (graph.nodes.some(item => item.kind === "change_value" && item.config?.variable_id === node.id)) { on_error("This variable is used by a change action. Choose another variable in that action or remove the action first."); return; }
		const outgoing = graph.connections.filter(edge => edge.from === node.id);
		if (outgoing.length && !window.confirm(`Remove ${node_name(node)} and its ${outgoing.length} outgoing connection(s)? Reconnect affected blocks before saving.`)) { return; }
		on_change({ ...graph, nodes: graph.nodes.filter(item => item.id !== node.id), connections: graph.connections.filter(edge => edge.from !== node.id && edge.to !== node.id) }); on_select(null);
	}
	function input_field(node: LogicNode, input: string) {
		const options = source_options(graph, node.id, input);
		const edge = graph.connections.find(entry => entry.to === node.id && entry.input === input);
		const optional = optional_input({ kind: node.kind as Parameters<typeof optional_input>[0]["kind"], config: node.config! }, input);
		const label = node.kind === "record" ? `${node.config?.fields?.find(field => field.id === input)?.label ?? "Value"} from` : input_name(node.kind, input);
		return <label key={input} className="connection-field"><span>{label}</span><select aria-label={`${label}: ${node_name(node)}`} value={edge ? `${edge.from}:${edge.output}` : ""} onChange={event => { try { on_change(set_source(graph, node.id, input, event.target.value)); } catch (failure) { on_error(failure instanceof Error ? failure.message : "Could not connect these blocks."); } }}><option value="">{optional ? ["amount", "duration", "threshold", "target"].includes(input) ? "Use the fixed value above" : "Not connected" : "Choose a source…"}</option>{options.map(option => <option key={option.id} value={option.id}>{option.label}</option>)}</select>{!options.length && !optional && <span className="connection-help">No compatible source yet. Add another block below, then connect it here.</span>}</label>;
	}
	return <section className="connection-document" aria-labelledby="connections-title"><div className="connection-intro"><span className="document-eyebrow">ON THIS PAGE</span><h1 id="connections-title">{section === "data" ? "Data" : "Routines"}</h1><p>{section === "data" ? "Values, saved entries, and ways to see them. Connect them to any routine on this page." : "What happens, and when. Choose an event or condition, then the action it runs."}</p></div>
		<div className="execution-note"><Link2 /><p>Connected blocks run <strong>while this page is open</strong>. Native schedules keep working in the background. Preview never changes your phone.</p></div>
		{!graph.nodes.length && <div className="connections-empty"><h2>What should your routine do?</h2><p>Add a control, a source of data, or an action. Then choose how they connect.</p><Button onClick={on_add}><Plus />Add a connected block</Button></div>}
		{graph.nodes.length > 0 && visible_nodes.length === 0 && <p className="document-empty">Nothing in this section yet. Add a block to get started.</p>}
		<div className="connection-list">{visible_nodes.map((node, index) => {
			const editable = is_behavior(node.kind); const open = selected === node.id && editable;
			return <section key={node.id} className={`connection-card ${open ? "is-open" : ""}`}>
				<button type="button" className="connection-card-heading" aria-expanded={open} aria-label={`Configure ${node_name(node)}`} onClick={() => editable ? on_select(open ? null : node.id) : on_page()}><span className="connection-number">{String(index + 1).padStart(2, "0")}</span><BlockIcon kind={node.kind} /><span><strong>{node_name(node)}</strong><small>{connected_summary(graph, node)}</small></span><span className="connection-kind">{editable ? node_catalog[node.kind].title : "On your page"}</span><ChevronDown /></button>
				{open && <div className="connection-card-body"><label className="connection-field"><span>Block name</span><InlineText label={`Name for ${node_name(node)}`} value={node.config?.label ?? ""} placeholder={node_catalog[node.kind].title} on_commit={label => update({ ...node, config: { ...node.config!, label } })} /></label>
					<NodeSettings node={node} graph={graph} patch={patch => update({ ...node, config: { ...node.config!, ...patch } })} />
					{["elapsed_timer", "variable"].includes(node.kind) ? <details className="document-details"><summary>Connect controls (optional)</summary><div className="connection-settings">{node_ports(node).inputs.map(input => input_field(node, input))}</div></details> : node_ports(node).inputs.filter(input => !(node.kind === "change_value" && input === "amount" && node.config?.change === "reset")).map(input => input_field(node, input))}
					<div className="connection-card-footer"><span className="supporting">{node_catalog[node.kind].detail}</span><Button variant="danger" onClick={() => remove(node)}><Trash2 />Remove</Button></div>
				</div>}
			</section>;
		})}</div>
		{graph.nodes.length > 0 && <button type="button" className="document-add" onClick={on_add}><Plus />Add a connected block</button>}
		<button type="button" className="advanced-link" onClick={on_advanced}>Need the full picture? Open advanced wiring <Link2 /></button>
	</section>;
}

function NodeSettings({ node, graph, patch }: { node: LogicNode; graph: LogicGraph; patch: (config: Partial<BehaviorConfig>) => void }) {
	const config = node.config!;
	return <div className="connection-settings">
		<PrimitiveSettings node={node} graph={graph} patch={patch} />
		{node.kind === "number_input" && <NumberField label="Initial value" value={config.value} min={-1000000} max={1000000} on_commit={value => patch({ value })} />}
		{node.kind === "progress" && !graph.connections.some(edge => edge.to === node.id && edge.input === "target") && <NumberField label="Target" value={config.value} min={1} max={1000000} on_commit={value => patch({ value })} />}
		{node.kind === "add_allowance" && <NumberField label="Minutes to award" value={config.minutes} min={1} max={1440} unit="minutes" on_commit={minutes => patch({ minutes })} />}
		{["count", "goal", "compare", "app_usage"].includes(node.kind) && !graph.connections.some(edge => edge.to === node.id && edge.input === "threshold") && <NumberField label={node.kind === "count" ? "Add each time" : node.kind === "goal" ? "Target" : "Value"} value={config.value} min={-1000000} max={1000000} integer={false} on_commit={value => patch({ value })} />}
		{node.kind === "compare" && <label className="connection-field"><span>Condition</span><select value={config.operator} onChange={event => patch({ operator: event.target.value as BehaviorConfig["operator"] })}><option value="gte">At least</option><option value="gt">More than</option><option value="eq">Exactly</option><option value="lt">Less than</option><option value="lte">At most</option></select></label>}
		{node.kind === "delay" && <NumberField label="Wait" value={config.minutes} min={1} max={1440} unit="minutes" on_commit={minutes => patch({ minutes })} />}
		{node.kind === "clock" && <><label className="connection-field"><span>At this time</span><input type="time" value={config.time} onChange={event => { if (event.target.value) { patch({ time: event.target.value }); } }} /></label><div className="day-picker" role="group" aria-label="Event days">{ALL_DAYS.map(day => <button type="button" key={day} aria-pressed={config.days.includes(day)} onClick={() => { const days = config.days.includes(day) ? config.days.filter(value => value !== day) : [...config.days, day].sort(); if (days.length) { patch({ days }); } }}>{DAY_LABELS[day - 1]}</button>)}</div></>}
		{node.kind === "reminder" && <label className="connection-field"><span>Message</span><InlineText label="Message" value={config.message} max_length={240} on_commit={message => patch({ message })} /></label>}
		{["chart", "aggregate"].includes(node.kind) && <label className="connection-field"><span>Which number?</span><select aria-label={`Numeric field: ${node_name(node)}`} value={config.field ?? "value"} onChange={event => patch({ field: event.target.value })}>{!numeric_fields(graph, node).some(field => field.id === (config.field ?? "value")) && <option value={config.field ?? "value"}>{config.field ?? "value"} (not in this source)</option>}{numeric_fields(graph, node).map(field => <option key={field.id} value={field.id}>{field.label}</option>)}</select></label>}
		{node.kind === "app_gate" && <><label className="connection-field"><span>App groups</span><InlineText label="App groups to control" value={(config.groups ?? []).join(", ")} placeholder="Social, Games" max_length={400} on_commit={value => patch({ groups: [...new Set(value.split(",").map(name => name.trim()).filter(Boolean))] })} /></label><p>Separate names with commas. Choose each group's apps privately on your phone. When the condition turns off, this block releases its restrictions; other routines still apply.</p></>}
		{["chart", "number_input", "progress", "add_allowance"].includes(node.kind) ? null : node.kind === "aggregate" ? <label className="connection-field"><span>Calculate</span><select value={config.operation ?? "sum"} onChange={event => patch({ operation: event.target.value as BehaviorConfig["operation"] })}>{["sum", "average", "minimum", "maximum", "count"].map(value => <option value={value} key={value}>{value}</option>)}</select></label> : <BuilderSettings node={node} patch={patch} advanced={false} />}
		{["location", "arrive", "leave"].includes(node.kind) && <p className="connection-help">Uses the single saved location on your iPhone. This connected event currently evaluates while the routine is open, not as an always-on background gym tracker.</p>}
		{node.kind === "add_allowance" && <p className="connection-help">Requires an enabled home-allowance routine on the phone. Its location and time-window restrictions still apply.</p>}
		{node.kind === "app_usage" && <p className="connection-help">Uses Apple Screen Time. Currently reads minutes counted by your home allowance, excluding usage away from home. Separate totals for each app aren't available. This number is read-only.</p>}
	</div>;
}
