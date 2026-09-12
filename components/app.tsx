"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { AppDocument } from "@/lib/document";
import { delete_tool, duplicate_tool, empty_library, find_tool, import_tool, load_library, save_library, upsert_tool, type Library } from "@/lib/library";
import { Home } from "./home";
import { Workbench } from "./workbench";

function error_message(error: unknown): string { return error instanceof Error ? error.message : "Something went wrong. Please try again."; }

function tool_from_url(): string | null {
	try { return new URLSearchParams(window.location.search).get("tool"); }
	catch { return null; }
}

export function PocketworkApp() {
	const [library, set_library] = useState<Library>(empty_library);
	const [ready, set_ready] = useState(false);
	const [storage_blocked, set_storage_blocked] = useState(false);
	const [error, set_error] = useState<string | null>(null);
	const [notice, set_notice] = useState<string | null>(null);
	const [open_id, set_open_id] = useState<string | null>(null);
	// Autosaves from the editor arrive in quick succession; the ref keeps each one building on the last.
	const library_ref = useRef(library);
	useEffect(() => { library_ref.current = library; }, [library]);
	useEffect(() => {
		if (!notice) { return; }
		const timeout = window.setTimeout(() => set_notice(null), 4500);
		return () => window.clearTimeout(timeout);
	}, [notice]);

	useEffect(() => {
		try {
			const saved = load_library(window.localStorage, Date.now());
			if (saved) { set_library(saved); }
		} catch (failure) { set_error(error_message(failure)); set_storage_blocked(true); }
		set_open_id(tool_from_url());
		set_ready(true);
		const on_pop = () => set_open_id(tool_from_url());
		window.addEventListener("popstate", on_pop);
		return () => window.removeEventListener("popstate", on_pop);
	}, []);

	// The URL carries which tool is open so the browser back button returns to My tools.
	function navigate(id: string | null) {
		const url = new URL(window.location.href);
		if (id) { url.searchParams.set("tool", id); } else { url.searchParams.delete("tool"); }
		try { window.history.pushState(null, "", url); } catch (failure) { console.warn(error_message(failure)); }
		set_open_id(id);
		window.scrollTo({ top: 0 });
	}

	function persist(next: Library) {
		set_library(next);
		if (storage_blocked) { return; }
		save_library(window.localStorage, next);
	}

	function try_persist(next: Library) {
		try { persist(next); set_error(null); }
		catch (failure) { set_error(error_message(failure)); }
	}

	const save_tool = useCallback((document: AppDocument) => {
		const next = upsert_tool(library_ref.current, document, Date.now());
		library_ref.current = next;
		set_library(next);
		if (!storage_blocked) { save_library(window.localStorage, next); }
	}, [storage_blocked]);

	function create_tool(document: AppDocument) {
		try { persist(upsert_tool(library, document, Date.now())); set_error(null); navigate(document.id); }
		catch (failure) { set_error(error_message(failure)); }
	}

	function remove_tool(id: string) {
		const tool = find_tool(library, id);
		if (!tool || !window.confirm(`Delete "${tool.name}"? This cannot be undone. Export it first if you want a copy.`)) { return; }
		try_persist(delete_tool(library, id));
		set_notice(`Deleted "${tool.name}".`);
	}

	function copy_tool(id: string) {
		try { const result = duplicate_tool(library, id, Date.now()); persist(result.library); set_error(null); set_notice(`Made a copy called "${result.document.name}".`); }
		catch (failure) { set_error(error_message(failure)); }
	}

	function add_imported(document: AppDocument) {
		try { const result = import_tool(library, document, Date.now()); persist(result.library); set_error(null); set_notice(`Added "${result.document.name}" to your tools.`); navigate(result.document.id); }
		catch (failure) { set_error(error_message(failure)); }
	}

	function replace_unreadable() {
		if (!window.confirm("Discard the unreadable saved data and start with an empty list of tools?")) { return; }
		set_storage_blocked(false); set_error(null);
		try { save_library(window.localStorage, library); } catch (failure) { set_error(error_message(failure)); }
	}

	const open_tool = open_id ? find_tool(library, open_id) : undefined;

	if (!ready) { return <div className="app-loading" role="status">Opening your tools…</div>; }

	if (open_tool) {
		return <Workbench key={open_tool.id} tool={open_tool} on_save={save_tool} on_back={() => navigate(null)} storage_blocked={storage_blocked} storage_error={error} on_replace_unreadable={replace_unreadable} on_dismiss_error={() => set_error(null)} />;
	}

	return <Home library={library} now={Date.now()} error={error} notice={notice} storage_blocked={storage_blocked}
		on_open={navigate} on_create={create_tool} on_delete={remove_tool} on_duplicate={copy_tool} on_import={add_imported}
		on_error={set_error} on_dismiss_error={() => set_error(null)} on_dismiss_notice={() => set_notice(null)} on_replace_unreadable={replace_unreadable} />;
}
