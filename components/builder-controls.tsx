"use client";
import { useState } from "react";
import type { BehaviorNode, BehaviorState, Signal } from "@/lib/behaviors";
import { form_fields, type Entry, type Scalar } from "@/lib/builder-blocks";
import { Button } from "./ui";
import type { TimerCommand } from "@/lib/primitives";
export function BuilderControls({ nodes, state, outputs, input, submit, timer }: { nodes: BehaviorNode[]; state: BehaviorState; outputs: Record<string, Record<string, Signal>>; input: (id: string, value: Scalar) => void; submit: (node: string, values: Record<string, Scalar>) => void; timer: (command: TimerCommand) => void }) {
	return <div className="builder-controls">{nodes.map(node => {
		const signal = outputs[node.id];
		if (node.kind === "elapsed_timer") {
			const remaining = node.config.timer_mode !== "stopwatch";
			const value = Number(signal?.[remaining ? "remaining" : "elapsed"]?.value ?? (remaining ? node.config.value : 0));
			const seconds = Math.max(0, Math.round(value * 60));
			return <section className="primitive-readout" key={node.id}><strong>{node.config.label}</strong><output aria-label={`${node.config.label} time`}>{Math.floor(seconds / 60)}:{String(seconds % 60).padStart(2, "0")}</output><span className="supporting">{signal?.running?.value ? "Running" : signal?.finished?.value ? "Finished" : "Paused"} · {remaining ? "counting down" : "counting up"}</span><div className="document-inline-actions"><Button disabled={signal?.running?.value === true} onClick={() => timer({ node: node.id, action: "start" })}>Start {node.config.label}</Button><Button disabled={signal?.running?.value !== true} onClick={() => timer({ node: node.id, action: "pause" })}>Pause {node.config.label}</Button><Button disabled={signal?.finished?.value === true || !signal?.running?.value && !signal?.elapsed?.value} onClick={() => timer({ node: node.id, action: "stop" })}>Stop {node.config.label}</Button><Button onClick={() => timer({ node: node.id, action: "reset" })}>Reset {node.config.label}</Button></div></section>;
		}
		if (["variable", "calculate", "aggregate", "app_usage", "count", "streak"].includes(node.kind)) {
			const port = node.kind === "app_usage" ? "minutes" : node.kind === "streak" ? "days" : "value";
			const value = signal?.[port];
			return <section className="primitive-readout" key={node.id}><strong>{node.config.label}</strong><output aria-label={`${node.config.label} value`}>{value?.available === false || !value && node.kind !== "variable" ? "Unavailable" : `${Number(value?.value ?? state.values[node.id] ?? node.config.value).toLocaleString(undefined, { maximumFractionDigits: 2 })}${node.config.unit ? ` ${node.config.unit}` : node.kind === "app_usage" ? " minutes" : ""}`}</output></section>;
		}
		if (["number_input", "text_input", "checkbox", "form"].includes(node.kind)) { return <BuilderInput key={node.id} node={node} value={state.data?.inputs[node.id]} saved={state.data?.forms[node.id]} input={input} submit={submit} />; }
		if (node.kind === "progress") { const value = Number(signal?.value?.value ?? 0); const target = Number(signal?.target?.value ?? node.config.value); return <div key={node.id}><strong>{node.config.label}</strong><progress aria-label={node.config.label} max={Math.max(1,target)} value={Math.max(0,Math.min(value,target))} /><span>{signal?.value?.available === false ? "Unavailable" : `${value} / ${target}`}</span></div>; }
		if (["table", "chart"].includes(node.kind)) { return <DataDisplay key={node.id} node={node} rows={Array.isArray(signal?.rows?.value) ? signal.rows.value : []} />; }
		return null;
	})}</div>;
}
function BuilderInput({ node, value, saved, input, submit }: { node: BehaviorNode; value?: Scalar; saved?: Record<string, Scalar>; input: (id: string, value: Scalar) => void; submit: (node: string, values: Record<string, Scalar>) => void }) {
	const [draft, set_draft] = useState(String(value ?? (node.kind === "number_input" ? node.config.value : node.config.text ?? "")));
	const [fields, set_fields] = useState<Record<string, Scalar>>(saved ?? {});
	if (node.kind === "checkbox") { return <label><input type="checkbox" checked={value === true} onChange={e => input(node.id, e.target.checked)} />{node.config.label}</label>; }
	if (node.kind !== "form") { return <form onSubmit={e => { e.preventDefault(); input(node.id, node.kind === "number_input" ? Number(draft) : draft); }}><label>{node.config.label}<input aria-label={node.config.label} type={node.kind === "number_input" ? "number" : "text"} step="any" maxLength={240} value={draft} required={node.kind === "number_input"} onChange={e => set_draft(e.target.value)} /></label><Button type="submit">Set value</Button></form>; }
	return <form onSubmit={e => { e.preventDefault(); const values = { ...fields }; for (const field of form_fields(node)) { if (field.type === "boolean") { values[field.id] ??= false; } if (field.type === "number" && values[field.id] !== undefined && values[field.id] !== "") { values[field.id] = Number(values[field.id]); } } submit(node.id, values); }}><strong>{node.config.label}</strong>{form_fields(node).map(field => <label key={field.id}>{field.label}<input aria-label={field.label} type={field.type === "boolean" ? "checkbox" : field.type === "number" ? "number" : "text"} step="any" required={field.required && field.type !== "boolean"} maxLength={240} {...(field.type === "boolean" ? { checked: fields[field.id] === true } : { value: String(fields[field.id] ?? "") })} onChange={e => set_fields({ ...fields, [field.id]: field.type === "boolean" ? e.target.checked : e.target.value })} /></label>)}<Button type="submit">Submit {node.config.label}</Button></form>;
}
function DataDisplay({ node, rows }: { node: BehaviorNode; rows: Entry[] }) {
	const columns = Array.from(new Set(rows.flatMap(row => Object.keys(row.values)))).slice(0,8);
	const points = rows.slice(-50).flatMap(row => typeof row.values[node.config.field ?? "value"] === "number" ? [Number(row.values[node.config.field ?? "value"])] : []);
	const min = Math.min(0,...points), max = Math.max(1,...points);
	const plotted = points.map((value, index) => ({ x: points.length === 1 ? 150 : 10 + index * 280 / (points.length - 1), y: 110 - (value - min) * 100 / (max - min) }));
	return <figure className="builder-data"><figcaption>{node.config.label} · {rows.length} {rows.length === 1 ? "entry" : "entries"}</figcaption>{node.kind === "chart" && points.length > 0 && <svg viewBox="0 0 300 120" role="img" aria-label={`${node.config.label}, ${points.length} values, from ${Math.min(...points)} to ${Math.max(...points)}`}><polyline points={plotted.map(point => `${point.x},${point.y}`).join(" ")} />{plotted.map((point, index) => <circle key={index} cx={point.x} cy={point.y} r="2.5" />)}</svg>}{rows.length === 0 ? <p>No entries yet.</p> : <div className="builder-table"><table aria-label={node.config.label}><thead><tr><th>Time</th>{columns.map(key => <th key={key}>{key}</th>)}</tr></thead><tbody>{rows.slice(-20).map(row => <tr key={row.id}><td>{new Date(row.at).toLocaleString()}</td>{columns.map(key => <td key={key}>{typeof row.values[key] === "number" ? row.values[key].toLocaleString(undefined, { maximumFractionDigits: 2 }) : String(row.values[key] ?? "")}</td>)}</tr>)}</tbody></table></div>}</figure>;
}
