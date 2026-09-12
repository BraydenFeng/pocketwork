"use client";

import { useRef } from "react";
import { ArrowRight, Check, Copy, Info, Layers2, Plus, Trash2, Upload, X } from "lucide-react";
import { is_standing, MAX_DOCUMENT_BYTES, parse_document, type AppDocument } from "@/lib/document";
import { describe_status } from "@/lib/schedule";
import { format_edited, sorted_tools, summarize_tool, type Library } from "@/lib/library";
import { blank_tool, templates } from "@/lib/templates";
import { Button, SectionLabel } from "./ui";

export function Home({ library, now, error, notice, storage_blocked, on_open, on_create, on_delete, on_duplicate, on_import, on_toggle, on_error, on_dismiss_error, on_dismiss_notice, on_replace_unreadable }: {
	library: Library; now: number; error: string | null; notice: string | null; storage_blocked: boolean;
	on_open: (id: string) => void; on_create: (document: AppDocument) => void; on_delete: (id: string) => void; on_duplicate: (id: string) => void; on_import: (document: AppDocument) => void; on_toggle: (id: string, enabled: boolean) => void;
	on_error: (message: string) => void; on_dismiss_error: () => void; on_dismiss_notice: () => void; on_replace_unreadable: () => void;
}) {
	const file_input = useRef<HTMLInputElement>(null);
	const tools = sorted_tools(library);

	async function import_file(file: File | undefined) {
		if (!file) { return; }
		try {
			if (file.size > MAX_DOCUMENT_BYTES) { throw new Error("This file is too large. Routines must be under 100 KB."); }
			on_import(parse_document(await file.text()));
		} catch (failure) { on_error(failure instanceof Error ? failure.message : "Could not read that file."); }
		finally { if (file_input.current) { file_input.current.value = ""; } }
	}

	return <div className="workbench home"><a className="skip-link" href="#my-tools">Skip to my routines</a>
		<header className="topbar"><div className="brand"><Layers2 /><span>pocketwork<span className="brand-period">.</span></span></div><span className="workspace-label">PERSONAL APP WORKBENCH</span><div className="topbar-actions"><Button onClick={() => file_input.current?.click()}><Upload />Add from file</Button></div>
			<input ref={file_input} className="file-input" type="file" accept=".json,application/json" aria-label="Import routine file" onChange={(event) => { void import_file(event.target.files?.[0]); }} />
		</header>
		<div className="projectbar home-intro"><div><h1>My routines</h1><p className="supporting">Small iPhone routines that hold you to what you decided. Start from one that works, then make it yours.</p></div><span className={`save-status ${storage_blocked ? "has-error" : ""}`}><span />{storage_blocked ? "Saved routines need attention" : `${tools.length} saved on this browser`}</span></div>
		{error && <div className="alert-banner" role="alert"><Info /><span>{error}</span>{storage_blocked && <Button onClick={on_replace_unreadable}>Replace unreadable data</Button>}<Button variant="quiet" aria-label="Dismiss error" onClick={on_dismiss_error}><X /></Button></div>}
		{notice && <div className="notice-banner" role="status"><Check />{notice}<Button variant="quiet" aria-label="Dismiss message" onClick={on_dismiss_notice}><X /></Button></div>}
		<main className="home-main">
			<section className="home-section" id="my-tools" aria-labelledby="my-tools-heading">
				<div className="home-section-heading"><SectionLabel number="01">MY ROUTINES</SectionLabel><h2 id="my-tools-heading">{tools.length ? "Pick up where you left off." : "Nothing here yet."}</h2></div>
				{tools.length ? <ul className="tool-grid" aria-label="Your routines">{tools.map((entry) => {
					const schedule = entry.document.blocks.find((block) => block.type === "schedule");
					return <li key={entry.document.id} className="tool-card">
					<button type="button" className="tool-open" onClick={() => on_open(entry.document.id)} aria-label={`Open ${entry.document.name}`}><strong>{entry.document.name}</strong><span className="tool-summary">{summarize_tool(entry.document)}</span>{entry.document.description && <span className="supporting">{entry.document.description}</span>}<span className="tool-meta">{schedule?.type === "schedule" ? describe_status(schedule, entry.document.enabled === true, now) : format_edited(entry.updated_at, now)}</span></button>
					<div className="tool-actions">{is_standing(entry.document) && <label className="card-switch"><input type="checkbox" role="switch" aria-label={`Switch ${entry.document.name} on or off`} checked={entry.document.enabled === true} onChange={(event) => on_toggle(entry.document.id, event.target.checked)} /><span>{entry.document.enabled ? "On" : "Off"}</span></label>}<button type="button" className="text-button" onClick={() => on_duplicate(entry.document.id)} aria-label={`Duplicate ${entry.document.name}`}><Copy />Duplicate</button><button type="button" className="text-button is-danger" onClick={() => on_delete(entry.document.id)} aria-label={`Delete ${entry.document.name}`}><Trash2 />Delete</button></div>
				</li>; })}</ul> : <p className="empty-hint home-empty">Choose a routine below and it becomes your first one. You can change every part of it afterwards.</p>}
			</section>
			<section className="home-section" aria-labelledby="routines-heading">
				<div className="home-section-heading"><SectionLabel number="02">READY-MADE ROUTINES</SectionLabel><h2 id="routines-heading">Ready to use. Yours to change.</h2><p className="supporting">Some run when you start them. Some switch themselves on at set times. All keep the apps you choose out of the way.</p></div>
				<ul className="tool-grid" aria-label="Routines">{templates.map((template) => <li key={template.id} className="tool-card is-template">
					<div className="tool-body"><strong>{template.name}</strong><span className="supporting">{template.tagline}</span></div>
					<div className="tool-actions"><Button variant="primary" onClick={() => on_create(template.build())}>Use this routine<ArrowRight /></Button></div>
				</li>)}<li className="tool-card is-template is-blank">
					<div className="tool-body"><strong>Blank routine</strong><span className="supporting">Start from nothing and add the blocks you want.</span></div>
					<div className="tool-actions"><Button onClick={() => on_create(blank_tool())}><Plus />Start blank</Button></div>
				</li></ul>
			</section>
		</main><footer className="workbench-footer"><span><span className="status-dot" />Your own little routines.</span><span>LOCAL PROTOTYPE <span className="footer-separator">/</span> SCHEMA V1</span></footer>
	</div>;
}
