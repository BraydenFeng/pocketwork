"use client";

import { useEffect, useRef, useState, type PointerEvent } from "react";
import { ArrowRight, Check, CircleHelp, GripVertical, Plus, RotateCcw, Trash2, Workflow, ZoomIn, ZoomOut } from "lucide-react";
import { behavior_catalog, is_behavior } from "@/lib/behaviors";
import { BuilderSettings } from "./builder-settings";
import { BehaviorRunner } from "./behavior-runner";
import type { HomePolicy } from "@/lib/home-policy";
import type { AppDocument, Block } from "@/lib/document";
import { compile_graph, connect, connection_key, graph_from_document, make_node, node_catalog, node_ports, node_height, NODE_WIDTH, PORT_GAP, PORT_TOP, type Connection, type LogicGraph, type LogicNode, type NodeKind } from "@/lib/logic-graph";
import { Button, SectionLabel, TextField } from "./ui";

const library_sections: { title: string; kinds: NodeKind[] }[] = [
	{ title: "Inputs", kinds: ["number_input", "text_input", "checkbox", "form", "health"] },
	{ title: "Time & location", kinds: ["timer", "schedule", "clock", "location", "arrive", "leave", "delay"] },
	{ title: "Data", kinds: ["variable", "count", "streak", "usage", "app_usage", "allowance", "save_entry", "aggregate"] },
	{ title: "Logic", kinds: ["compare", "and", "or", "not", "branch", "goal", "calculate", "text_compare"] },
	{ title: "Actions", kinds: ["button", "check_in", "apps", "notification", "reminder", "app_gate", "add_allowance"] },
	{ title: "Display", kinds: ["table", "chart", "progress"] },
];
const day_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
function message(error: unknown): string { return error instanceof Error ? error.message : "Could not update this graph."; }
function port_point(node: LogicNode, port: string, output: boolean) { return { x: node.x + (output ? NODE_WIDTH : 0), y: node.y + PORT_TOP + (output ? node_ports(node).outputs : node_ports(node).inputs).indexOf(port) * PORT_GAP }; }
function curve(a: { x: number; y: number }, b: { x: number; y: number }) { const bend = Math.max(60, Math.abs(b.x - a.x) / 2); return `M ${a.x} ${a.y} C ${a.x + bend} ${a.y}, ${b.x - bend} ${b.y}, ${b.x} ${b.y}`; }

export function LogicCanvas({ document, on_change, disabled = false, on_dirty_change }: { document: AppDocument; on_change: (document: AppDocument) => void; disabled?: boolean; on_dirty_change?: (dirty: boolean) => void }) {
	const [search, set_search] = useState("");
	const [testing, set_testing] = useState(false);
	const [graph, set_graph] = useState<LogicGraph>(() => graph_from_document(document));
	const [source, set_source] = useState(document);
	const [selected, set_selected] = useState<string | null>(null);
	const [pending, set_pending] = useState<{ id: string; port: string } | null>(null);
	const [dirty, set_dirty] = useState(false);
	const [error, set_error] = useState<string | null>(null);
	const [status, set_status] = useState("Connections match this routine.");
	const [viewport, set_viewport] = useState({ x: 0, y: 0, width: 1240, height: 680 });
	const [cursor, set_cursor] = useState({ x: 0, y: 0 });
	const svg = useRef<SVGSVGElement>(null);
	const drag = useRef<{ id: string | null; client_x: number; client_y: number; x: number; y: number } | null>(null);
	const node = graph.nodes.find((item) => item.id === selected);
	const stale = JSON.stringify(source) !== JSON.stringify(document);
	useEffect(() => { on_dirty_change?.(dirty); }, [dirty, on_dirty_change]);
	useEffect(() => {
		if (!svg.current) { return; }
		const observer = new ResizeObserver(([entry]) => { if (entry.contentRect.width > 0) { set_viewport((previous) => ({ ...previous, width: entry.contentRect.width, height: entry.contentRect.height })); } });
		observer.observe(svg.current); return () => observer.disconnect();
	}, []);
	useEffect(() => {
		if (dirty || !stale) { return; }
		set_graph(graph_from_document(document)); set_source(document);
	}, [document, dirty, stale]);
	useEffect(() => {
		const warn = (event: BeforeUnloadEvent) => { if (dirty) { event.preventDefault(); } };
		window.addEventListener("beforeunload", warn); return () => window.removeEventListener("beforeunload", warn);
	}, [dirty]);
	function edit(next: LogicGraph) { set_graph(next); set_dirty(true); set_error(null); set_status("Draft connections · apply when ready"); }
	function update(next: LogicNode) { edit({ ...graph, nodes: graph.nodes.map((item) => item.id === next.id ? next : item) }); }
	function input(id: string, port: string) {
		if (!pending) { set_status("Choose an output on the right of a node first."); return; }
		try { edit(connect(graph, { from: pending.id, output: pending.port, to: id, input: port })); set_pending(null); }
		catch (failure) { set_error(message(failure)); set_pending(null); }
	}
	function apply() {
		try {
			if (stale) { throw new Error("This routine changed elsewhere. Reload the graph before applying your draft."); }
			const result = compile_graph(document, graph); on_change(result); set_source(result); set_dirty(false); set_error(null); set_status("Applied · saved with your routine");
		} catch (failure) { set_error(message(failure)); }
	}
	function reload() { if (dirty && !window.confirm("Discard unapplied graph changes?")) { return; } set_graph(graph_from_document(document)); set_source(document); set_dirty(false); set_pending(null); set_error(null); set_status("Connections match this routine."); }
	function point(event: PointerEvent) { const rect = svg.current!.getBoundingClientRect(); const scale = Math.min(rect.width / viewport.width, rect.height / viewport.height); return { x: viewport.x + (event.clientX - rect.left) / scale, y: viewport.y + (event.clientY - rect.top) / scale }; }
	function start_drag(event: PointerEvent, item?: LogicNode) {
		if (event.button !== 0) { return; }
		event.preventDefault(); event.stopPropagation(); svg.current?.setPointerCapture(event.pointerId);
		drag.current = { id: item?.id ?? null, client_x: event.clientX, client_y: event.clientY, x: item?.x ?? viewport.x, y: item?.y ?? viewport.y };
		if (item) { set_selected(item.id); }
	}
	function pointer_move(event: PointerEvent) {
		const current = point(event); if (pending) { set_cursor(current); }
		if (!drag.current) { return; }
		const rect = svg.current!.getBoundingClientRect(); const scale = Math.min(rect.width / viewport.width, rect.height / viewport.height); const dx = (event.clientX - drag.current.client_x) / scale; const dy = (event.clientY - drag.current.client_y) / scale;
		const moving = drag.current;
		if (moving.id) { set_graph((previous) => ({ ...previous, nodes: previous.nodes.map((item) => item.id === moving.id ? { ...item, x: moving.x + dx, y: moving.y + dy } : item) })); }
		else { set_viewport((previous) => ({ ...previous, x: moving.x - dx, y: moving.y - dy })); }
	}
	function add(kind: NodeKind) { let x = viewport.x + 40; let y = viewport.y + 40; while (graph.nodes.some(item => Math.abs(item.x - x) < NODE_WIDTH + 24 && Math.abs(item.y - y) < Math.max(node_height(item), 220))) { x += NODE_WIDTH + 64; if (x > viewport.x + Math.max(viewport.width, 800) - NODE_WIDTH) { x = viewport.x + 40; y += 240; } } const next = make_node(kind, x, y); edit({ ...graph, nodes: [...graph.nodes, next] }); set_selected(next.id); }
	const pending_node = graph.nodes.find((item) => item.id === pending?.id);
	return <div className="logic-workspace">
		<aside className="logic-library" aria-label="Logic node library"><SectionLabel>BEHAVIORS</SectionLabel><input className="logic-search" aria-label="Search behaviors" placeholder="Find a behavior…" value={search} onChange={(event) => set_search(event.target.value)} /><div className="logic-node-list">{library_sections.map(section => {
			const kinds = section.kinds.filter(kind => `${node_catalog[kind].title} ${node_catalog[kind].detail} ${section.title}`.toLowerCase().includes(search.toLowerCase()));
			return kinds.length > 0 && <details className="logic-category" key={`${section.title}-${Boolean(search)}`} open={search ? true : undefined}><summary>{section.title}<span>{kinds.length}</span></summary>{kinds.map(kind => <button className="logic-add" type="button" key={kind} title={node_catalog[kind].detail} disabled={disabled || graph.nodes.length >= 55 || (!is_behavior(kind) && graph.nodes.some(item => item.kind === kind))} onClick={() => add(kind)} aria-label={`Add ${node_catalog[kind].title} node`}><Plus /><strong>{node_catalog[kind].title}</strong></button>)}</details>;
		})}</div><div className="logic-help"><p>Drag nodes. Connect matching ports.</p></div></aside>
		<div className="logic-main"><div className="logic-toolbar"><span><Workflow />{graph.nodes.length} nodes <span className="supporting">/ {graph.connections.length} connections</span></span><div><Button variant="quiet" aria-label="Zoom out" onClick={() => set_viewport({ ...viewport, width: viewport.width * 1.2, height: viewport.height * 1.2 })}><ZoomOut /></Button><Button variant="quiet" aria-label="Zoom in" onClick={() => set_viewport({ ...viewport, width: Math.max(180, viewport.width / 1.2), height: Math.max(180, viewport.height / 1.2) })}><ZoomIn /></Button><Button variant="quiet" aria-label="Actual size" onClick={() => { const rect = svg.current?.getBoundingClientRect(); if (rect) { set_viewport({ x: 0, y: 0, width: rect.width, height: rect.height }); } }}>100%</Button><Button variant="quiet" aria-label="Fit graph" onClick={() => { const min_x = Math.min(0, ...graph.nodes.map((item) => item.x - 40)); const min_y = Math.min(0, ...graph.nodes.map((item) => item.y - 40)); set_viewport({ x: min_x, y: min_y, width: Math.max(800, ...graph.nodes.map((item) => item.x + NODE_WIDTH + 40 - min_x)), height: Math.max(440, ...graph.nodes.map((item) => item.y + node_height(item) + 40 - min_y)) }); }}><RotateCcw /></Button></div></div>
			<div className="logic-stage"><svg ref={svg} className="logic-svg" viewBox={`${viewport.x} ${viewport.y} ${viewport.width} ${viewport.height}`} preserveAspectRatio="xMinYMin meet" aria-label="Connected logic canvas" onPointerDown={(event) => { if (event.target === event.currentTarget) { start_drag(event); } }} onPointerMove={pointer_move} onPointerUp={(event) => { drag.current = null; if (svg.current?.hasPointerCapture(event.pointerId)) { svg.current.releasePointerCapture(event.pointerId); } }} onPointerCancel={() => { drag.current = null; set_pending(null); }} onKeyDown={(event) => { if (event.key === "Escape") { set_pending(null); } }}>
				<defs><pattern id={`grid-${document.id}`} width="24" height="24" patternUnits="userSpaceOnUse"><circle cx="1" cy="1" r="1" className="logic-dot" /></pattern></defs>
				<rect x={viewport.x} y={viewport.y} width={viewport.width} height={viewport.height} fill={`url(#grid-${document.id})`} onPointerDown={(event) => start_drag(event)} />
				{graph.connections.map((edge) => { const from = graph.nodes.find((item) => item.id === edge.from)!; const to = graph.nodes.find((item) => item.id === edge.to)!; return <path key={connection_key(edge)} className={`logic-wire ${selected === from.id || selected === to.id ? "is-selected" : ""}`} d={curve(port_point(from, edge.output, true), port_point(to, edge.input, false))} />; })}
				{pending && pending_node && <path className="logic-wire is-pending" d={curve(port_point(pending_node, pending.port, true), cursor)} />}
				{graph.nodes.map((item) => <g key={item.id} className={`logic-node ${selected === item.id ? "is-selected" : ""}`} transform={`translate(${item.x},${item.y})`} data-node-id={item.id}>
					<rect className="logic-node-shell" width={NODE_WIDTH} height={node_height(item)} rx="10" />
					<foreignObject x="12" y="8" width={NODE_WIDTH - 24} height="80"><button type="button" className="logic-node-heading" onPointerDown={(event) => start_drag(event, item)} onClick={() => set_selected(item.id)} aria-label={`Configure ${node_catalog[item.kind].title}`}><span><GripVertical /><strong>{item.config?.label || node_catalog[item.kind].title}</strong></span><small>{item.kind === "timer" && item.block?.type === "timer" ? `${item.block.minutes} minutes` : item.kind === "apps" && item.block?.type === "screen_time" ? item.block.groups?.join(", ") || "Choose apps on iPhone" : node_catalog[item.kind].detail}</small></button></foreignObject>
					{([false, true] as const).flatMap((output) => (output ? node_ports(item).outputs : node_ports(item).inputs).map((port, index) => <g key={`${output}-${port}`} className={`logic-port ${pending?.id === item.id && pending.port === port && output ? "is-active" : ""}`} role="button" tabIndex={0} aria-label={`${node_catalog[item.kind].title} ${output ? "output" : "input"} ${port}`} onPointerDown={(event) => { event.stopPropagation(); if (output) { set_pending({ id: item.id, port }); set_cursor(port_point(item, port, true)); } }} onPointerUp={() => { if (!output) { input(item.id, port); } }} onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); if (output) { set_pending({ id: item.id, port }); set_cursor(port_point(item, port, true)); } else { input(item.id, port); } } }}>
						<circle className="logic-port-hit" cx={output ? NODE_WIDTH : 0} cy={PORT_TOP + index * PORT_GAP} r="14" /><circle cx={output ? NODE_WIDTH : 0} cy={PORT_TOP + index * PORT_GAP} r="5" /><text x={output ? NODE_WIDTH - 14 : 14} y={PORT_TOP + index * PORT_GAP + 4} textAnchor={output ? "end" : "start"}>{port}</text>
					</g>))}
				</g>)}
			</svg>{!graph.nodes.length && <div className="logic-empty"><Workflow /><h2>Give your page a little logic.</h2><p>Add a timer or time window, then connect it to an action.</p></div>}</div>
			<div className="logic-footer"><span role="status">{pending ? "Choose an input to connect. Escape cancels." : status}</span><Button onClick={() => set_testing(!testing)} variant="quiet">{testing ? "Close test" : "Test logic"}</Button><Button onClick={reload} variant="quiet">Reload</Button><Button onClick={apply} disabled={disabled || !dirty} variant="primary"><Check />Apply to routine</Button></div>{graph.nodes.some(item => is_behavior(item.kind)) && <p className="logic-runtime-note">New behaviors require the updated iPhone app and run while the routine is open.</p>}{error && <p className="logic-error" role="alert">{error}</p>}{testing && <BehaviorRunner graph={graph} />}
		</div>
		<aside className="logic-inspector" aria-label="Node settings"><SectionLabel>NODE SETTINGS</SectionLabel>{node ? <><h2>{node_catalog[node.kind].title}</h2><NodeSettings node={node} graph={graph} update={update} select={set_selected} /><SectionLabel>CONNECTIONS</SectionLabel><ul className="logic-connections">{graph.connections.filter((edge) => edge.from === node.id || edge.to === node.id).map((edge) => <li key={connection_key(edge)}><span>{node_catalog[graph.nodes.find((item) => item.id === edge.from)!.kind].title} · {edge.output}<ArrowRight />{node_catalog[graph.nodes.find((item) => item.id === edge.to)!.kind].title} · {edge.input}</span><Button variant="quiet" aria-label={`Disconnect ${edge.output} from ${edge.input}`} onClick={() => edit({ ...graph, connections: graph.connections.filter((item) => item !== edge) })}><XIcon /></Button></li>)}</ul><Button variant="quiet" onClick={() => { edit({ nodes: graph.nodes.filter((item) => item.id !== node.id), connections: graph.connections.filter((edge) => edge.from !== node.id && edge.to !== node.id) }); set_selected(null); }}><Trash2 />Remove node</Button></> : <div className="logic-inspector-empty"><Workflow /><h2>Connect the pieces.</h2><p>Select a node to change its settings or remove a connection.</p></div>}</aside>
	</div>;
}
function XIcon() { return <span aria-hidden="true">×</span>; }
function NodeSettings({ node, graph, update, select }: { node: LogicNode; graph: LogicGraph; update: (node: LogicNode) => void; select: (id: string) => void }) {
	const block = node.block;
	const patch = (next: Block) => update({ ...node, block: next });
	const allowance = graph.nodes.find((item) => item.kind === "allowance");
	return <div className="logic-settings">
		{block && <label>Title<input value={block.title} onChange={(event) => patch({ ...block, title: event.target.value })} /></label>}
		{block?.type === "timer" && <label>Duration (minutes)<input type="number" min="15" max="120" value={block.minutes} onChange={(event) => patch({ ...block, minutes: Number(event.target.value) })} /></label>}
		{block?.type === "schedule" && (allowance ? <><p>In a home allowance, daily windows are configured with each budget.</p><Button onClick={() => select(allowance.id)}>Edit daily windows</Button></> : <><div className="logic-days">{day_names.map((label, index) => <label key={label}><input type="checkbox" checked={block.days.includes(index + 1)} onChange={(event) => patch({ ...block, days: event.target.checked ? [...block.days, index + 1].sort() : block.days.filter((day) => day !== index + 1) })} />{label}</label>)}</div><label>From<input type="time" value={block.start} onChange={(event) => patch({ ...block, start: event.target.value })} /></label><label>Until<input type="time" value={block.end} onChange={(event) => patch({ ...block, end: event.target.value })} /></label></>)}
		{block?.type === "screen_time" && <><label>Action<select value={block.mode ?? "block"} onChange={(event) => { const mode = event.target.value as "block" | "allow_only" | "limit"; const next = { ...block, mode }; if (mode === "limit") { next.limit_minutes = block.limit_minutes ?? 30; } else { delete next.limit_minutes; } patch(next); }}><option value="block">Block these apps</option><option value="allow_only">Allow only these apps</option><option value="limit">Limit usage</option></select></label><TextField label="App groups (comma separated)" value={(block.groups ?? []).join(", ")} on_commit={(value) => patch({ ...block, groups: value.split(",").map((name) => name.trim()).filter(Boolean) })} />{block.mode === "limit" && <label>Usage limit (minutes)<input type="number" min="15" max="1440" value={block.limit_minutes ?? 30} onChange={(event) => patch({ ...block, limit_minutes: Number(event.target.value) })} /></label>}<p>App selections stay private on the phone. With home logic, connect both Home and Outside: apps also block outside your windows while at home.</p></>}
		{node.kind === "home" && <p>Uses the location saved on your iPhone. The current phone app calls its setup button Set home here. One saved location is supported.</p>}
		{node.kind === "usage" && <p>Counts distraction usage only when both Home and Window are true. Away usage never counts. iOS reports whole-minute checkpoints.</p>}
		{node.kind === "notification" && <p>Connect a timer's finished output. The iPhone schedules a local completion notification; permission is required.</p>}
		{is_behavior(node.kind) && node.config && <BehaviorSettings node={node} update={update} />}
		{node.policy && <PolicySettings node={node} update={update} />}
	</div>;
}

function PolicySettings({ node, update }: { node: LogicNode; update: (node: LogicNode) => void }) {
	const policy = node.policy!;
	type Rule = HomePolicy["rules"][number];
	function rules(next: Rule[]) { update({ ...node, policy: { ...policy, rules: next } }); }
	function rule_at(index: number, next: Rule) { rules(policy.rules.map((item, i) => i === index ? next : item)); }
	const unassigned = [1, 2, 3, 4, 5, 6, 7].filter((day) => !policy.rules.some((rule) => rule.days.includes(day)));
	return <>
		<p>Each day has one shared budget. Uncheck days to put them in a separate group. Times use Los Angeles.</p>
		{policy.rules.map((rule, index) => <fieldset key={index}><legend>{rule.days.map((day) => day_names[day - 1]).join(", ") || "Choose days"}</legend>
			<div className="logic-days">{day_names.map((label, day_index) => <label key={label}><input type="checkbox" checked={rule.days.includes(day_index + 1)} onChange={(event) => rule_at(index, { ...rule, days: event.target.checked ? [...rule.days, day_index + 1].sort() : rule.days.filter((day) => day !== day_index + 1) })} />{label}</label>)}</div>
			<label>Shared allowance (minutes)<input type="number" min="1" max="180" value={rule.allowance_minutes} onChange={(event) => rule_at(index, { ...rule, allowance_minutes: Number(event.target.value) })} /></label>
			{rule.windows.map((window, window_index) => <div key={window_index}><div className="logic-window">{(["start", "end"] as const).map((key) => <label key={key}>{key === "start" ? "From" : "Until"}<input type="time" value={window[key]} onChange={(event) => rule_at(index, { ...rule, windows: rule.windows.map((part, j) => j === window_index ? { ...part, [key]: event.target.value } : part) })} /></label>)}</div>{rule.windows.length > 1 && <Button variant="quiet" onClick={() => rule_at(index, { ...rule, windows: rule.windows.filter((_, i) => i !== window_index) })}>Remove window</Button>}</div>)}
			<Button variant="quiet" disabled={rule.windows.length >= 2 || rule.windows.at(-1)!.end > "23:44"} onClick={() => rule_at(index, { ...rule, windows: [...rule.windows, { start: rule.windows.at(-1)!.end, end: "23:59" }] })}><Plus />Add window</Button>
			{policy.rules.length > 1 && <Button variant="quiet" onClick={() => rules(policy.rules.filter((_, i) => i !== index))}>Remove day group</Button>}
		</fieldset>)}
		<Button disabled={!unassigned.length || policy.rules.length >= 7} onClick={() => rules([...policy.rules, { days: unassigned, allowance_minutes: 30, windows: [{ start: "06:30", end: "20:30" }] }])}><Plus />Add day group</Button>
	</>;
}

function BehaviorSettings({ node, update }: { node: LogicNode; update: (node: LogicNode) => void }) {
	const config = node.config!;
	const patch = (next: Partial<typeof config>) => update({ ...node, config: { ...config, ...next } });
	return <>
		<BuilderSettings node={node} patch={patch} />
		<label>Name<input value={config.label} onChange={event => patch({ label: event.target.value })} maxLength={80} /></label>
		{["variable", "count", "goal", "compare", "app_usage"].includes(node.kind) && <label>{node.kind === "count" ? "Increase by" : node.kind === "variable" ? "Initial value" : "Target value"}<input type="number" value={config.value} onChange={event => patch({ value: Number(event.target.value) })} /></label>}
		{node.kind === "delay" && <label>Wait (minutes)<input type="number" min="1" max="1440" value={config.minutes} onChange={event => patch({ minutes: Number(event.target.value) })} /></label>}
		{node.kind === "delay" && <p>Starting again restarts the wait. Pending waits resume when you reopen this routine.</p>}
		{node.kind === "compare" && <label>Comparison<select value={config.operator} onChange={event => patch({ operator: event.target.value as typeof config.operator })}><option value="gte">At least</option><option value="gt">Greater than</option><option value="eq">Equal to</option><option value="lt">Less than</option><option value="lte">At most</option></select></label>}
		{node.kind === "clock" && <><label>Time<input type="time" value={config.time} onChange={event => patch({ time: event.target.value })} /></label><div className="logic-days">{day_names.map((label, index) => <label key={label}><input type="checkbox" checked={config.days.includes(index+1)} onChange={event => patch({ days: event.target.checked ? [...config.days,index+1] : config.days.filter(day => day !== index+1) })} />{label}</label>)}</div><p>Uses the device's local time.</p></>}
		{node.kind === "reminder" && <label>Message<textarea aria-label="Reminder message" value={config.message} maxLength={240} onChange={event => patch({ message: event.target.value })} /></label>}
		{["location", "arrive", "leave"].includes(node.kind) && <p>One saved location is shared by all routines, including the home allowance. Location changes are observed while this routine is open. Initial unknown location does not count as an arrival.</p>}
		{node.kind === "app_usage" && <p>Reads today's home allowance meter on the phone. Away usage stays excluded; this does not read unrestricted usage of arbitrary apps.</p>}
		{node.kind === "streak" && <p>One check-in per local calendar day. A missed day restarts the streak.</p>}
		<p>{behavior_catalog[node.kind as keyof typeof behavior_catalog].detail}. Open Test logic to try the connections before saving.</p>
	</>;
}
