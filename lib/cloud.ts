import { createClient, type Session, type SupabaseClient } from "@supabase/supabase-js";
import { library_schema, type Library } from "./library";

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

export async function sign_in_with_google(cloud: Cloud): Promise<void> {
	const { error } = await cloud.client.auth.signInWithOAuth({ provider: "google", options: { redirectTo: `${window.location.origin}${window.location.pathname}` } });
	if (error) { throw new Error(`Google sign-in did not start. ${error.message}`); }
}

export async function sign_out(cloud: Cloud): Promise<void> {
	const { error } = await cloud.client.auth.signOut();
	if (error) { throw new Error(`Could not sign out. ${error.message}`); }
}

export async function fetch_library(cloud: Cloud, account: Account): Promise<Library | null> {
	const { data, error } = await cloud.client.from("libraries").select("library").eq("user_id", account.id).maybeSingle();
	if (error) { throw new Error(`Could not read your routines from your account. ${error.message}`); }
	if (!data) { return null; }
	const result = library_schema.safeParse(data.library);
	if (!result.success) { throw new Error(`The routines saved to your account could not be read. ${result.error.issues[0].message}`); }
	return result.data;
}

export async function push_library(cloud: Cloud, account: Account, library: Library): Promise<void> {
	const { error } = await cloud.client.from("libraries").upsert({ user_id: account.id, library: library_schema.parse(library) }, { onConflict: "user_id" });
	if (error) { throw new Error(`Could not save your routines to your account. ${error.message}`); }
}
