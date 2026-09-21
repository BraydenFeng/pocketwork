import { createClient, type Session, type SupabaseClient } from "@supabase/supabase-js";
import { library_schema, type Library } from "./library";
import { fetch_plan } from "./account-client";
import { assert_page_limit, plan_active } from "./page-plan";

export type Account = { id: string; email: string | null };
export type Cloud = { client: SupabaseClient };

// Returns null when the project is not configured, in which case everything stays on this device.
export function connect_cloud(): Cloud | null {
	const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
	const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
	if (!url || !key) { return null; }
	try { return { client: createClient(url, key) }; }
	catch (error) { console.warn(`Cloud sync unavailable: ${error instanceof Error ? error.message : "could not create the client."}`); return null; }
}

export function account_of(session: Session | null): Account | null {
	return session?.user ? { id: session.user.id, email: session.user.email ?? null } : null;
}

export async function current_account(cloud: Cloud): Promise<Account | null> {
	const { data, error } = await cloud.client.auth.getSession();
	if (error) { throw new Error(`Could not check who is signed in. ${error.message}`); }
	return account_of(data.session);
}

export function watch_account(cloud: Cloud, on_change: (account: Account | null) => void): () => void {
	const { data } = cloud.client.auth.onAuthStateChange((_event, session) => on_change(account_of(session)));
	return () => data.subscription.unsubscribe();
}

export async function sign_in_with_google(cloud: Cloud, provider: "apple" | "google" = "google"): Promise<void> {
	const { error } = await cloud.client.auth.signInWithOAuth({ provider, options: { redirectTo: `${window.location.origin}${window.location.pathname}` } });
	if (error) { throw new Error(`Sign-in did not start. ${error.message}`); }
}

export async function sign_out(cloud: Cloud): Promise<void> {
	const { error } = await cloud.client.auth.signOut();
	if (error) { throw new Error(`Could not sign out. ${error.message}`); }
}

export type CloudSnapshot = { library: Library; updated_at: string };

export async function fetch_library(cloud: Cloud, account: Account): Promise<CloudSnapshot | null> {
	const { data, error } = await cloud.client.from("libraries").select("library,updated_at").eq("user_id", account.id).maybeSingle();
	if (error) { throw new Error(`Could not read your cloud routines. ${error.message}`); }
	if (!data) { return null; }
	return { library: library_schema.parse(data.library), updated_at: data.updated_at };
}

export async function push_library(cloud: Cloud, account: Account, library: Library, previous: CloudSnapshot | null): Promise<boolean> {
	const old = previous?.library ?? { schema_version: 1 as const, tools: [] };
	const is_new = library.tools.some(entry => !old.tools.some(item => item.document.id === entry.document.id));
	if (is_new && library.tools.length > 3) { assert_page_limit(old, library, plan_active(await fetch_plan(cloud))); }
	const row = { user_id: account.id, library: library_schema.parse(library) };
	const query = previous
		? cloud.client.from("libraries").update(row).eq("user_id", account.id).eq("updated_at", previous.updated_at)
		: cloud.client.from("libraries").insert(row);
	const { data, error } = await query.select("user_id");
	if (error?.code === "23505") { return false; }
	if (error) { throw new Error(`Could not save your cloud routines. ${error.message}`); }
	return Boolean(data?.length);
}
