"use client";

import { useRef } from "react";
import { ArrowRight, Check, Copy, Info, Layers2, Plus, Trash2, Upload, X } from "lucide-react";
import { MAX_DOCUMENT_BYTES, parse_document, type AppDocument } from "@/lib/document";
import { format_edited, sorted_tools, summarize_tool, type Library } from "@/lib/library";
import { blank_tool, templates } from "@/lib/templates";
import { Button, SectionLabel } from "./ui";

export function Home({ library, now, error, notice, storage_blocked, on_open, on_create, on_delete, on_duplicate, on_import, on_error, on_dismiss_error, on_dismiss_notice, on_replace_unreadable }: {
	library: Library; now: number; error: string | null; notice: string | null; storage_blocked: boolean;
	on_open: (id: string) => void; on_create: (document: AppDocument) => void; on_delete: (id: string) => void; on_duplicate: (id: string) => void; on_import: (document: AppDocument) => void;
	on_error: (message: string) => void; on_dismiss_error: () => void; on_dismiss_notice: () => void; on_replace_unreadable: () => void;
}) {
	const file_input = useRef<HTMLInputElement>(null);
	const tools = sorted_tools(library);

	async function import_file(file: File | undefined) {
		if (!file) { return; }
		try {
			if (file.size > MAX_DOCUMENT_BYTES) { throw new Error("This file is too large. Personal tools must be under 100 KB."); }
			on_import(parse_document(await file.text()));
		} catch (failure) { on_error(failure instanceof Error ? failure.message : "Could not read that file."); }
		finally { if (file_input.current) { file_input.current.value = ""; } }
	}

	return <div className="workbench home"><a className="skip-link" href="#my-tools">Skip to my tools</a>
		<header className="topbar"><div className="brand"><Layers2 /><span>pocketwork<span className="brand-period">.</span></span></div><span className="workspace-label">PERSONAL APP WORKBENCH</span><div className="topbar-actions"><Button onClick={() => file_input.current?.click()}><Upload />Add from file</Button></div>
			<input ref={file_input} className="file-input" type="file" accept=".json,application/json" aria-label="Import tool file" onChange={(event) => { void import_file(event.target.files?.[0]); }} />
		</header>
		<div className="projectbar home-intro"><div><h1>My tools</h1><p className="supporting">Small iPhone tools that hold you to what you decided. Start from a routine, then make it yours.</p></div><span className={`save-status ${storage_blocked ? "has-error" : ""}`}><span />{storage_blocked ? "Saved tools need attention" : `${tools.length} saved on this browser`}</span></div>
		{error && <div className="alert-banner" role="alert"><Info /><span>{error}</span>{storage_blocked && <Button onClick={on_replace_unreadable}>Replace unreadable data</Button>}<Button variant="quiet" aria-label="Dismiss error" onClick={on_dismiss_error}><X /></Button></div>}
		{notice && <div className="notice-banner" role="status"><Check />{notice}<Button variant="quiet" aria-label="Dismiss message" onClick={on_dismiss_notice}><X /></Button></div>}
		<main className="home-main">
			<section className="home-section" id="my-tools" aria-labelledby="my-tools-heading">
				<div className="home-section-heading"><SectionLabel number="01">MY TOOLS</SectionLabel><h2 id="my-tools-heading">{tools.length ? "Pick up where you left off." : "Nothing here yet."}</h2></div>
				{tools.length ? <ul className="tool-grid" aria-label="Your tools">{tools.map((entry) => <li key={entry.document.id} className="tool-card">
					<button type="button" className="tool-open" onClick={() => on_open(entry.document.id)} aria-label={`Open ${entry.document.name}`}><strong>{entry.document.name}</strong><span className="tool-summary">{summarize_tool(entry.document)}</span>{entry.document.description && <span className="supporting">{entry.document.description}</span>}<span className="tool-meta">{format_edited(entry.updated_at, now)}</span></button>
					<div className="tool-actions"><button type="button" className="text-button" onClick={() => on_duplicate(entry.document.id)} aria-label={`Duplicate ${entry.document.name}`}><Copy />Duplicate</button><button type="button" className="text-button is-danger" onClick={() => on_delete(entry.document.id)} aria-label={`Delete ${entry.document.name}`}><Trash2 />Delete</button></div>
				</li>)}</ul> : <p className="empty-hint home-empty">Choose a routine below and it becomes your first tool. You can change every part of it afterwards.</p>}
			</section>
			<section className="home-section" aria-labelledby="routines-heading">
				<div className="home-section-heading"><SectionLabel number="02">START WITH A ROUTINE</SectionLabel><h2 id="routines-heading">Ready to use. Yours to change.</h2><p className="supporting">Each one runs on your iPhone with the apps you choose kept out of the way until you are done.</p></div>
				<ul className="tool-grid" aria-label="Routines">{templates.map((template) => <li key={template.id} className="tool-card is-template">
					<div className="tool-body"><strong>{template.name}</strong><span className="supporting">{template.tagline}</span></div>
					<div className="tool-actions"><Button variant="primary" onClick={() => on_create(template.build())}>Use this routine<ArrowRight /></Button></div>
				</li>)}<li className="tool-card is-template is-blank">
					<div className="tool-body"><strong>Blank tool</strong><span className="supporting">Start from nothing and add the blocks you want.</span></div>
					<div className="tool-actions"><Button onClick={() => on_create(blank_tool())}><Plus />Start blank</Button></div>
				</li></ul>
			</section>
		</main><footer className="workbench-footer"><span><span className="status-dot" />No AI credits. No tracking. Your own little tools.</span><span>LOCAL PROTOTYPE <span className="footer-separator">/</span> SCHEMA V1</span></footer>
	</div>;
}
