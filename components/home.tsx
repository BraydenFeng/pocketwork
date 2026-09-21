"use client";

import { native_format_four } from "@/lib/release-flags";

import { useRef } from "react";
import { useState } from "react";
import { ArrowRight, Check, CloudOff, Copy, Info, Layers2, LogIn, LogOut, Pencil, Plus, RefreshCw, Shield, Trash2, Upload, X } from "lucide-react";
import type { Account } from "@/lib/cloud";
import type { SyncState } from "./app";
import { is_standing, MAX_DOCUMENT_BYTES, parse_document, type AppDocument } from "@/lib/document";
import { describe_status } from "@/lib/schedule";
import { age_words, type StatusReport } from "@/lib/status";
import { format_edited, routines_using_group, sorted_tools, summarize_tool, type Library } from "@/lib/library";
import { blank_tool } from "@/lib/templates";
import { Button, SectionLabel } from "./ui";

export function Home({ library, now, error, notice, storage_blocked, phone_status, cloud_available, account, sync, on_sign_in, on_sign_out, on_connect_agent, on_open, on_create, on_delete, on_duplicate, on_import, on_toggle, on_add_group, on_rename_group, on_remove_group, on_error, on_dismiss_error, on_dismiss_notice, on_replace_unreadable }: {
	library: Library; now: number; error: string | null; notice: string | null; storage_blocked: boolean; phone_status: StatusReport | null;
	cloud_available: boolean; account: Account | null; sync: SyncState; on_sign_in: (provider: "apple" | "google") => void; on_sign_out: () => void; on_connect_agent: () => void;
	on_open: (id: string) => void; on_create: (document: AppDocument) => void; on_delete: (id: string) => void; on_duplicate: (id: string) => void; on_import: (document: AppDocument) => void; on_toggle: (id: string, enabled: boolean) => void;
	on_add_group: (name: string) => void; on_rename_group: (id: string, name: string) => void; on_remove_group: (id: string) => void;
	on_error: (message: string) => void; on_dismiss_error: () => void; on_dismiss_notice: () => void; on_replace_unreadable: () => void;
}) {
	const file_input = useRef<HTMLInputElement>(null);
	const tools = sorted_tools(library);
	// The phone's own words for a routine, when it has shared them: minutes left, a running countdown, or on/off as the phone sees it.
	function phone_line(document: AppDocument): string | null {
		if (!phone_status) { return null; }
		const age = age_words(phone_status.reported_at, now);
		const allowance = phone_status.allowance;
		if (document.home_allowance && allowance?.routine_id === document.id) {
			const where = allowance.at_home ? "at home" : "away";
			return `${allowance.remaining_minutes} of ${allowance.budget_minutes} min left today · ${where} · phone ${age}`;
		}
		const routine = phone_status.routines.find((entry) => entry.id === document.id);
		if (!routine) { return null; }
		if (routine.running && routine.ends_at) { return `Running on your phone · until ${new Date(routine.ends_at).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`; }
		if (routine.kind !== "session") { return `${routine.enabled ? "On" : "Off"} on your phone · ${age}`; }
		return null;
	}
	const groups = library.groups ?? [];
	const [new_group, set_new_group] = useState("");
	const [renaming, set_renaming] = useState<{ id: string; name: string } | null>(null);
	function submit_group() { if (new_group.trim()) { on_add_group(new_group); set_new_group(""); } }
	function submit_rename() { if (renaming && renaming.name.trim()) { on_rename_group(renaming.id, renaming.name); } set_renaming(null); }
	const saved_where = storage_blocked ? "Saved routines need attention"
		: !account ? `${tools.length} saved on this browser`
		: sync === "syncing" ? "Syncing with your account…"
		: sync === "error" ? "Saved here · could not reach your account"
		: `${tools.length} saved · synced to ${account.email ?? "your account"}`;

	async function import_file(file: File | undefined) {
		if (!file) { return; }
		try {
			if (file.size > MAX_DOCUMENT_BYTES) { throw new Error("This file is too large. Routines must be under 100 KB."); }
			on_import(parse_document(await file.text()));
		} catch (failure) { on_error(failure instanceof Error ? failure.message : "Could not read that file."); }
		finally { if (file_input.current) { file_input.current.value = ""; } }
	}

	return <div className="workbench home"><a className="skip-link" href="#my-tools">Skip to my pages</a>
		<header className="topbar"><div className="brand"><Layers2 /><span>pocketwork<span className="brand-period">.</span></span></div><span className="workspace-label">PAGES / ROUTINES / DATA</span><div className="topbar-actions">{cloud_available && (account
				? <span className="account-chip"><Button onClick={on_connect_agent}>Copy agent connection</Button><span className="account-email">{account.email ?? "Signed in"}</span><Button variant="quiet" onClick={on_sign_out}><LogOut />Sign out</Button></span>
				: <><Button variant="primary" onClick={() => on_sign_in("apple")}><LogIn />Sign in with Apple</Button>{process.env.NEXT_PUBLIC_GOOGLE_ENABLED === "true" && <Button onClick={() => on_sign_in("google")}>Google</Button>}</>)}<Button onClick={() => on_create(blank_tool())}><Plus />New page</Button><Button onClick={() => file_input.current?.click()}><Upload />Add from file</Button></div>
			<input ref={file_input} className="file-input" type="file" accept=".json,application/json" aria-label="Import page file" onChange={(event) => { void import_file(event.target.files?.[0]); }} />
		</header>
		<div className="projectbar home-intro"><div><h1>My pages</h1><p className="supporting">{account ? "Create here. Open Pocketwork on your iPhone with the same sign-in to sync, then choose which apps to block." : cloud_available ? "Sign in and your pages follow you to your iPhone. Until then they live on this browser." : "Your own little tools. Pages hold your routines and data."}</p></div><span className={`save-status ${storage_blocked || sync === "error" ? "has-error" : ""}`}>{sync === "syncing" ? <RefreshCw className="is-spinning" /> : sync === "error" ? <CloudOff /> : <span />}{saved_where}</span></div>
		{error && <div className="alert-banner" role="alert"><Info /><span>{error}</span>{storage_blocked && <Button onClick={on_replace_unreadable}>Replace unreadable data</Button>}<Button variant="quiet" aria-label="Dismiss error" onClick={on_dismiss_error}><X /></Button></div>}
		{notice && <div className="notice-banner" role="status"><Check />{notice}<Button variant="quiet" aria-label="Dismiss message" onClick={on_dismiss_notice}><X /></Button></div>}
		<main className="home-main">
			<section className="home-section" id="my-tools" aria-labelledby="my-tools-heading">
				<div className="home-section-heading"><SectionLabel number="01">MY PAGES</SectionLabel><h2 id="my-tools-heading">{tools.length ? "Pick up where you left off." : "Nothing here yet."}</h2></div>
				{tools.length ? <ul className="tool-grid" aria-label="Your pages">{tools.map((entry) => {
					const schedule = entry.document.blocks.find((block) => block.type === "schedule");
					return <li key={entry.document.id} className="tool-card">
					<button type="button" className="tool-open" onClick={() => on_open(entry.document.id)} aria-label={`Open ${entry.document.name}`}><strong>{entry.document.name}</strong><span className="tool-summary">{summarize_tool(entry.document)}</span>{entry.document.description && <span className="supporting">{entry.document.description}</span>}<span className="tool-meta">{entry.document.schema_version === 4 && !native_format_four ? "Local draft · phone update required" : phone_line(entry.document) ?? (entry.document.home_allowance ? (entry.document.enabled ? "Home allowance enabled" : "Home allowance off") : schedule?.type === "schedule" ? describe_status(schedule, entry.document.enabled === true, now) : format_edited(entry.updated_at, now))}</span></button>
					<div className="tool-actions">{is_standing(entry.document) && !entry.document.home_allowance && <label className="card-switch"><input type="checkbox" role="switch" aria-label={`Switch ${entry.document.name} on or off`} checked={entry.document.enabled === true} onChange={(event) => on_toggle(entry.document.id, event.target.checked)} /><span>{entry.document.enabled ? "On" : "Off"}</span></label>}<button type="button" className="text-button" onClick={() => on_duplicate(entry.document.id)} aria-label={`Duplicate ${entry.document.name}`}><Copy />Duplicate</button><button type="button" className="text-button is-danger" onClick={() => on_delete(entry.document.id)} aria-label={`Delete ${entry.document.name}`}><Trash2 />Delete</button></div>
				</li>; })}</ul> : <p className="empty-hint home-empty">Start with a blank page. Add routines to make things happen, and data to keep track. Your first three pages are free, including MCP and sync.</p>}
			</section>
			<section className="home-section" aria-labelledby="groups-heading">
				<div className="home-section-heading"><SectionLabel number="02">APP GROUPS</SectionLabel><h2 id="groups-heading">Name the apps once. Every routine can use them.</h2><p className="supporting">Groups like Social or Work are named here and filled with real apps on your iPhone, privately. A routine can block a group, allow only a group, or limit it to so many minutes.</p></div>
				<ul className="group-list" aria-label="App groups">{groups.map((group) => {
					const used_by = routines_using_group(library, group.name);
					return <li key={group.id} className="group-chip">{renaming?.id === group.id
						? <form className="group-rename" onSubmit={(event) => { event.preventDefault(); submit_rename(); }}><input className="field" aria-label={`New name for ${group.name}`} value={renaming.name} autoFocus maxLength={40} onChange={(event) => set_renaming({ id: group.id, name: event.target.value })} onBlur={submit_rename} /></form>
						: <><Shield /><strong>{group.name}</strong><span className="supporting">{used_by.length ? `${used_by.length} routine${used_by.length === 1 ? "" : "s"}` : "not used yet"}</span><button type="button" className="text-button" aria-label={`Rename ${group.name}`} onClick={() => set_renaming({ id: group.id, name: group.name })}><Pencil /></button><button type="button" className="text-button is-danger" aria-label={`Delete group ${group.name}`} onClick={() => on_remove_group(group.id)}><Trash2 /></button></>}
					</li>; })}
					<li className="group-chip is-new"><form className="group-rename" onSubmit={(event) => { event.preventDefault(); submit_group(); }}><input className="field" aria-label="New group name" placeholder={groups.length ? "Another group…" : "Social, Games, Work…"} value={new_group} maxLength={40} onChange={(event) => set_new_group(event.target.value)} /><Button onClick={submit_group} disabled={!new_group.trim()}><Plus />Add group</Button></form></li>
				</ul>
			</section>

		</main><footer className="workbench-footer"><span><span className="status-dot" />Your own little tools.</span><span><a href="/account">Account & plan</a> · <a href="/privacy">Privacy</a> · <a href="/support">Support</a></span></footer>
	</div>;
}
