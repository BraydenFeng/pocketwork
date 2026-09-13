"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { AppDocument } from "@/lib/document";
import { connect_cloud, current_account, fetch_library, push_library, sign_in_with_google, sign_out, watch_account, type Account, type Cloud } from "@/lib/cloud";
import { add_group, delete_tool, duplicate_tool, empty_library, find_tool, import_tool, load_library, remove_group, rename_group, save_library, upsert_tool, LIBRARY_KEY, library_schema, type Library } from "@/lib/library";
import { merge_libraries, same_library } from "@/lib/sync";
import { HomeAllowance } from "./home-allowance";
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
	const active_owner = useRef<string | null>(null);
	const account_ready = useRef(false);
	const storage = useCallback(() => ({ getItem: (key: string) => window.localStorage.getItem(active_owner.current ? `${key}.${active_owner.current}` : key), setItem: (key: string, value: string) => window.localStorage.setItem(active_owner.current ? `${key}.${active_owner.current}` : key, value) }), []);
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

	useEffect(() => {
		const owner = account?.id ?? null;
		if (active_owner.current === owner && (!owner || account_ready.current)) { account_ready.current = true; return; }
		account_ready.current = false;
		try {
			const previous_owner = active_owner.current;
			active_owner.current = owner;
			const raw = storage().getItem(LIBRARY_KEY);
			const next = raw ? library_schema.parse(JSON.parse(raw)) : !previous_owner ? library_ref.current : empty_library;
			library_ref.current = next; set_library(next); set_open_id(null);
			save_library(storage(), next);
			if (owner && !previous_owner) { window.localStorage.removeItem(LIBRARY_KEY); window.localStorage.removeItem("pocketwork.document.v1"); }
			set_storage_blocked(false); last_pushed.current = null; account_ready.current = true;
		} catch (failure) { set_storage_blocked(true); set_error(error_message(failure)); }
	}, [account, storage]);

	const sync_now = useCallback(async () => {
		const connection = cloud; const who = account_ref.current;
		if (!connection || !who || !account_ready.current || storage_blocked || syncing.current) { return; }
		syncing.current = true; set_sync("syncing");
		try {
			for (let attempt = 0; attempt < 5; attempt++) {
				const remote = await fetch_library(connection, who);
				if (account_ref.current?.id !== who.id) { return; }
				const merged = remote ? merge_libraries(library_ref.current, remote.library, Date.now()) : library_ref.current;
				library_schema.parse(merged);
				if (!same_library(merged, library_ref.current)) { library_ref.current = merged; set_library(merged); save_library(storage(), merged); }
				if (remote && same_library(merged, remote.library) || await push_library(connection, who, merged, remote)) {
					if (account_ref.current?.id !== who.id) { return; }
					last_pushed.current = JSON.stringify(merged);
					if (!same_library(merged, library_ref.current)) { continue; }
					set_sync("synced"); return;
				}
			}
			throw new Error("Your other device is saving changes. Sync will retry shortly.");
		} catch (failure) { set_sync("error"); set_error(error_message(failure)); }
		finally { syncing.current = false; }
	}, [cloud, storage_blocked, storage]);

	useEffect(() => {
		if (!account) { set_sync("off"); return; }
		void sync_now();
		const on_focus = () => { if (document.visibilityState === "visible") { void sync_now(); } };
		const interval = window.setInterval(on_focus, 15000);
		window.addEventListener("focus", on_focus);
		window.addEventListener("online", on_focus);
		return () => { clearInterval(interval); window.removeEventListener("focus", on_focus); window.removeEventListener("online", on_focus); };
	}, [account, sync_now]);

	useEffect(() => {
		if (!account || !ready || JSON.stringify(library) === last_pushed.current) { return; }
		const timeout = window.setTimeout(() => { void sync_now(); }, 800);
		return () => window.clearTimeout(timeout);
	}, [library, account, ready, sync_now]);

	useEffect(() => {
		if (!ready || !account || storage_blocked || !account_ready.current || new URLSearchParams(window.location.search).get("seed") !== "home") { return; }
		let cancelled = false;
		void (async () => {
			if (!cloud) { return; }
			const { data, error } = await cloud.client.auth.getSession();
			if (error || !data.session) { throw new Error("Sign in to seed your routine."); }
			const response = await fetch("/api/mcp", { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${data.session.access_token}` }, body: JSON.stringify({ jsonrpc: "2.0", id: "seed-home", method: "tools/call", params: { name: "seed_home_allowance", arguments: {} } }) });
			if (!response.ok) { throw new Error("Could not seed the routine. Please retry."); }
			const reply = await response.json();
			if (reply.error || reply.result?.isError) { throw new Error(reply.error?.message ?? reply.result.content[0].text); }
			if (cancelled) { return; }
			const remote = await fetch_library(cloud, account);
			if (cancelled || !remote) { return; }
			const next = merge_libraries(library_ref.current, remote.library, Date.now());
			save_library(storage(), next); library_ref.current = next; set_library(next);
			const url = new URL(window.location.href); url.searchParams.delete("seed"); window.history.replaceState(null, "", url);
			set_open_id("home-distraction-allowance");
		})().catch((failure) => set_error(error_message(failure)));
		return () => { cancelled = true; };
	}, [ready, account, storage_blocked, storage, cloud]);

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
		save_library(storage(), next);
	}

	function try_persist(next: Library) {
		try { persist(next); set_error(null); }
		catch (failure) { set_error(error_message(failure)); }
	}

	const save_tool = useCallback((document: AppDocument) => {
		if (active_owner.current !== (account?.id ?? null)) { return; }
		const next = upsert_tool(library_ref.current, document, Date.now());
		library_ref.current = next;
		set_library(next);
		if (!storage_blocked) { save_library(storage(), next); }
	}, [storage_blocked, storage, account?.id]);

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
		try { save_library(storage(), library); } catch (failure) { set_error(error_message(failure)); }
	}

	// Group operations validate before they persist, so the whole step sits inside the try.
	function attempt(step: () => Library) {
		try { persist(step()); set_error(null); }
		catch (failure) { set_error(error_message(failure)); }
	}
	function create_group(name: string) { attempt(() => add_group(library, name)); }
	function change_group_name(id: string, name: string) { attempt(() => rename_group(library, id, name, Date.now())); }
	function drop_group(id: string) {
		const group = (library.groups ?? []).find((entry) => entry.id === id);
		if (!group || !window.confirm(`Delete the app group "${group.name}"? The apps chosen for it on your iPhone are forgotten too.`)) { return; }
		attempt(() => remove_group(library, id));
	}

	async function start_sign_in(provider: "apple" | "google") {
		if (!cloud) { return; }
		try { await sign_in_with_google(cloud, provider); } catch (failure) { set_error(error_message(failure)); }
	}

	async function copy_agent_connection() {
		if (!cloud) { return; }
		try {
			const { data, error } = await cloud.client.auth.getSession();
			if (error || !data.session) { throw new Error("Sign in before connecting an agent."); }
			await navigator.clipboard.writeText(JSON.stringify({ mcpServers: { pocketwork: { type: "http", url: `${window.location.origin}/api/mcp`, headers: { Authorization: `Bearer ${data.session.access_token}` } } } }, null, 2));
			set_notice("Agent connection copied. It contains a private, short-lived account token. Paste it only into your own agent. Copy again when it expires.");
		} catch (failure) { set_error(error_message(failure)); }
	}

	async function finish_sign_out() {
		if (!cloud) { return; }
		try { await sign_out(cloud); set_account(null); set_notice("Signed out. Your account routines are kept separately on this browser."); }
		catch (failure) { set_error(error_message(failure)); }
	}

	const open_tool = open_id ? find_tool(library, open_id) : undefined;

	if (!ready) { return <div className="app-loading" role="status">Opening your routines…</div>; }

	if (open_tool?.home_allowance) { return <HomeAllowance document={open_tool} on_back={() => navigate(null)} />; }
	if (open_tool) {
		return <Workbench key={open_tool.id} tool={open_tool} groups={library.groups ?? []} on_save={save_tool} on_back={() => navigate(null)} storage_blocked={storage_blocked} storage_error={error} on_replace_unreadable={replace_unreadable} on_dismiss_error={() => set_error(null)} sync={account ? sync : "off"} />;
	}

	return <Home library={library} now={Date.now()} error={error} notice={notice} storage_blocked={storage_blocked}
		on_connect_agent={() => { void copy_agent_connection(); }} cloud_available={cloud !== null} account={account} sync={sync} on_sign_in={(provider) => { void start_sign_in(provider); }} on_sign_out={() => { void finish_sign_out(); }}
		on_open={navigate} on_create={create_tool} on_delete={remove_tool} on_duplicate={copy_tool} on_import={add_imported} on_toggle={toggle_tool}
		on_add_group={create_group} on_rename_group={change_group_name} on_remove_group={drop_group}
		on_error={set_error} on_dismiss_error={() => set_error(null)} on_dismiss_notice={() => set_notice(null)} on_replace_unreadable={replace_unreadable} />;
}
