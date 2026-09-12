"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { AppDocument } from "@/lib/document";
import { connect_cloud, current_account, fetch_library, push_library, sign_in_with_google, sign_out, watch_account, type Account, type Cloud } from "@/lib/cloud";
import { delete_tool, duplicate_tool, empty_library, find_tool, import_tool, load_library, save_library, upsert_tool, type Library } from "@/lib/library";
import { merge_libraries, same_library } from "@/lib/sync";
import { Home } from "./home";
import { Workbench } from "./workbench";

export type SyncState = "off" | "syncing" | "synced" | "error";

function error_message(error: unknown): string { return error instanceof Error ? error.message : "Something went wrong. Please try again."; }

function tool_from_url(): string | null {
	try { return new URLSearchParams(window.location.search).get("routine"); }
	catch { return null; }
}

export function PocketworkApp() {
	const [library, set_library] = useState<Library>(empty_library);
	const [ready, set_ready] = useState(false);
	const [storage_blocked, set_storage_blocked] = useState(false);
	const [error, set_error] = useState<string | null>(null);
	const [notice, set_notice] = useState<string | null>(null);
	const [open_id, set_open_id] = useState<string | null>(null);
	const [cloud, set_cloud] = useState<Cloud | null>(null);
	const [account, set_account] = useState<Account | null>(null);
	const [sync, set_sync] = useState<SyncState>("off");
	// Autosaves from the editor arrive in quick succession; the ref keeps each one building on the last.
	const library_ref = useRef(library);
	const account_ref = useRef(account);
	const syncing = useRef(false);
	const last_pushed = useRef<string | null>(null);
	useEffect(() => { library_ref.current = library; }, [library]);
	useEffect(() => { account_ref.current = account; }, [account]);
	useEffect(() => {
		if (!notice) { return; }
		const timeout = window.setTimeout(() => set_notice(null), 4500);
		return () => window.clearTimeout(timeout);
	}, [notice]);

	useEffect(() => {
		try {
			const saved = load_library(window.localStorage, Date.now());
			if (saved) { set_library(saved); library_ref.current = saved; }
		} catch (failure) { set_error(error_message(failure)); set_storage_blocked(true); }
		set_open_id(tool_from_url());
		set_ready(true);
		const on_pop = () => set_open_id(tool_from_url());
		window.addEventListener("popstate", on_pop);
		return () => window.removeEventListener("popstate", on_pop);
	}, []);

	// The account layer is optional: without a configured project everything stays on this device.
	useEffect(() => {
		const connection = connect_cloud();
		if (!connection) { return; }
		set_cloud(connection);
		let cancelled = false;
		current_account(connection).then((found) => { if (!cancelled) { set_account(found); } }).catch((failure) => set_error(error_message(failure)));
		const stop = watch_account(connection, (found) => set_account((current) => current?.id === found?.id ? current : found));
		return () => { cancelled = true; stop(); };
	}, []);

	// Pull the account copy, reconcile with this device, and push back whatever the account was missing.
	const sync_now = useCallback(async () => {
		const connection = cloud; const who = account_ref.current;
		if (!connection || !who || syncing.current) { return; }
		syncing.current = true; set_sync("syncing");
		try {
			const remote = await fetch_library(connection, who);
			const local = library_ref.current;
			const merged = remote ? merge_libraries(local, remote, Date.now()) : local;
			if (!same_library(merged, local)) {
				library_ref.current = merged; set_library(merged);
				if (!storage_blocked) { save_library(window.localStorage, merged); }
			}
			if (!remote || !same_library(merged, remote)) { await push_library(connection, who, merged); }
			last_pushed.current = JSON.stringify(merged);
			set_sync("synced");
		} catch (failure) { set_sync("error"); set_error(error_message(failure)); }
		finally { syncing.current = false; }
	}, [cloud, storage_blocked]);

	useEffect(() => {
		if (!account) { set_sync("off"); last_pushed.current = null; return; }
		void sync_now();
		const on_focus = () => { if (document.visibilityState === "visible") { void sync_now(); } };
		window.addEventListener("focus", on_focus);
		document.addEventListener("visibilitychange", on_focus);
		return () => { window.removeEventListener("focus", on_focus); document.removeEventListener("visibilitychange", on_focus); };
	}, [account, sync_now]);

	// Every local change goes up shortly after it is saved here.
	useEffect(() => {
		if (!cloud || !account || !ready) { return; }
		const snapshot = JSON.stringify(library);
		if (snapshot === last_pushed.current) { return; }
		const timeout = window.setTimeout(async () => {
			if (syncing.current) { return; }
			set_sync("syncing");
			try { await push_library(cloud, account, library); last_pushed.current = snapshot; set_sync("synced"); }
			catch (failure) { set_sync("error"); set_error(error_message(failure)); }
		}, 800);
		return () => window.clearTimeout(timeout);
	}, [library, cloud, account, ready]);

	// The URL carries which routine is open so the browser back button returns to My routines.
	function navigate(id: string | null) {
		const url = new URL(window.location.href);
		if (id) { url.searchParams.set("routine", id); } else { url.searchParams.delete("routine"); }
		try { window.history.pushState(null, "", url); } catch (failure) { console.warn(error_message(failure)); }
		set_open_id(id);
		window.scrollTo({ top: 0 });
	}

	function persist(next: Library) {
		library_ref.current = next;
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

	function toggle_tool(id: string, enabled: boolean) {
		const tool = find_tool(library, id);
		if (!tool) { return; }
		try_persist(upsert_tool(library, { ...tool, enabled }, Date.now()));
	}

	function remove_tool(id: string) {
		const tool = find_tool(library, id);
		if (!tool || !window.confirm(`Delete "${tool.name}"? This cannot be undone. Export it first if you want a copy.`)) { return; }
		try_persist(delete_tool(library, id, Date.now()));
		set_notice(`Deleted "${tool.name}".`);
	}

	function copy_tool(id: string) {
		try { const result = duplicate_tool(library, id, Date.now()); persist(result.library); set_error(null); set_notice(`Made a copy called "${result.document.name}".`); }
		catch (failure) { set_error(error_message(failure)); }
	}

	function add_imported(document: AppDocument) {
		try { const result = import_tool(library, document, Date.now()); persist(result.library); set_error(null); set_notice(`Added "${result.document.name}" to your routines.`); navigate(result.document.id); }
		catch (failure) { set_error(error_message(failure)); }
	}

	function replace_unreadable() {
		if (!window.confirm("Discard the unreadable saved data and start with an empty list of routines?")) { return; }
		set_storage_blocked(false); set_error(null);
		try { save_library(window.localStorage, library); } catch (failure) { set_error(error_message(failure)); }
	}

	async function start_sign_in() {
		if (!cloud) { return; }
		try { await sign_in_with_google(cloud); } catch (failure) { set_error(error_message(failure)); }
	}

	async function finish_sign_out() {
		if (!cloud) { return; }
		try { await sign_out(cloud); set_account(null); set_notice("Signed out. Your routines stay on this browser."); }
		catch (failure) { set_error(error_message(failure)); }
	}

	const open_tool = open_id ? find_tool(library, open_id) : undefined;

	if (!ready) { return <div className="app-loading" role="status">Opening your routines…</div>; }

	if (open_tool) {
		return <Workbench key={open_tool.id} tool={open_tool} on_save={save_tool} on_back={() => navigate(null)} storage_blocked={storage_blocked} storage_error={error} on_replace_unreadable={replace_unreadable} on_dismiss_error={() => set_error(null)} sync={account ? sync : "off"} />;
	}

	return <Home library={library} now={Date.now()} error={error} notice={notice} storage_blocked={storage_blocked}
		cloud_available={cloud !== null} account={account} sync={sync} on_sign_in={() => { void start_sign_in(); }} on_sign_out={() => { void finish_sign_out(); }}
		on_open={navigate} on_create={create_tool} on_delete={remove_tool} on_duplicate={copy_tool} on_import={add_imported} on_toggle={toggle_tool}
		on_error={set_error} on_dismiss_error={() => set_error(null)} on_dismiss_notice={() => set_notice(null)} on_replace_unreadable={replace_unreadable} />;
}
