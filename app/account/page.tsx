"use client";

import { useEffect, useState } from "react";
import { z } from "zod";
import { account_request, fetch_plan } from "@/lib/account-client";
import { connect_cloud, current_account, sign_in_with_google, type Account, type Cloud } from "@/lib/cloud";
import { LIBRARY_KEY } from "@/lib/library";
import { free_plan, plan_active, type PagePlan } from "@/lib/page-plan";
import { Button } from "@/components/ui";
import { LegalPage } from "@/components/legal-page";

const pending_key = "pocketwork.delete.pending";
export default function AccountPage() {
	const [cloud, set_cloud] = useState<Cloud | null>(null);
	const [account, set_account] = useState<Account | null>(null);
	const [plan, set_plan] = useState<PagePlan>(free_plan);
	const [busy, set_busy] = useState(true);
	const [confirm, set_confirm] = useState("");
	const [error, set_error] = useState<string | null>(null);
	const [deleted, set_deleted] = useState(false);
	const [creating, set_creating] = useState(false);
	const [signing_in, set_signing_in] = useState<"apple" | "google" | null>(null);
	async function clear_account(connection: Cloud, id: string) {
		window.localStorage.removeItem(`${LIBRARY_KEY}.${id}`);
		window.localStorage.removeItem(`pocketwork.document.v1.${id}`);
		const { error } = await connection.client.auth.signOut({ scope: "local" });
		if (error) { throw new Error("Account deleted, but clearing this browser's sign-in failed. Clear this site's storage in browser settings."); }
		window.sessionStorage.removeItem(pending_key); window.history.replaceState(null, "", "/account");
		set_account(null); set_deleted(true);
	}
	useEffect(() => {
		let cancelled = false;
		void (async () => {
			const query = new URLSearchParams(window.location.search);
			set_creating(query.get("mode") === "create");
			const callback = new URLSearchParams(window.location.hash.slice(1));
			if (query.has("error") || callback.has("error")) { set_error("Sign-in was not completed. Please try again."); }
			const connection = connect_cloud(); set_cloud(connection);
			if (!connection) { return; }
			const found = await current_account(connection); if (cancelled) { return; } set_account(found);
			if (query.has("deleted")) {
				const pending = z.object({ id: z.string(), state: z.string() }).parse(JSON.parse(window.sessionStorage.getItem(pending_key) ?? "null"));
				if (query.get("state") !== pending.state || found && found.id !== pending.id) { throw new Error("This deletion result does not match your request."); }
				if (query.get("deleted") !== "true") { window.sessionStorage.removeItem(pending_key); throw new Error("Deletion did not finish. Your account has not been confirmed deleted. Start again below."); }
				await clear_account(connection, pending.id); return;
			}
			if (found) { const next = await fetch_plan(connection); if (!cancelled) { set_plan(next); } }
		})().catch(failure => { if (!cancelled) { set_error(failure instanceof Error ? failure.message : "Could not load your account."); } }).finally(() => { if (!cancelled) { set_busy(false); } });
		return () => { cancelled = true; };
	}, []);
	async function start_sign_in(provider: "apple" | "google") {
		if (!cloud || busy || signing_in) { return; }
		set_signing_in(provider); set_error(null);
		try { await sign_in_with_google(cloud, provider); }
		catch (failure) { set_error(failure instanceof Error ? failure.message : "Could not open sign-in. Please try again."); set_signing_in(null); }
	}
	async function remove_account() {
		if (!cloud || !account || confirm !== "DELETE" || busy) { return; }
		set_busy(true); set_error(null);
		try {
			const result = z.discriminatedUnion("deleted", [z.object({ deleted: z.literal(true) }), z.object({ deleted: z.literal(false), authorize_url: z.string().url(), state: z.string() })]).parse(await account_request(cloud, "/api/account/delete", { confirm, platform: "web" }));
			if (result.deleted) { await clear_account(cloud, account.id); }
			else {
				const url = new URL(result.authorize_url); if (url.origin !== "https://appleid.apple.com") { throw new Error("Invalid Apple sign-in address."); }
				window.sessionStorage.setItem(pending_key, JSON.stringify({ id: account.id, state: result.state })); window.location.assign(url);
			}
		} catch (failure) { set_error(failure instanceof Error ? failure.message : "Could not delete your account."); }
		finally { set_busy(false); }
	}
	return <LegalPage title={account || deleted || busy ? "Account" : creating ? "Create your account" : "Sign in to Pocketwork"}>
		{(deleted || account || busy) && <p>{deleted ? "Your account and its cloud data have been deleted. This browser's account library and sign-in have been cleared." : account?.email ?? "Loading your account…"}</p>}
		{error && <p className="account-error" role="alert">{error}</p>}
		{!account && !busy && <section aria-label="Account access">
			<p>{creating ? "Save your pages and open them on your iPhone or computer." : "Use the same Apple or Google account you used before."}</p>
			<p>Your first sign-in creates your Pocketwork account. No separate password needed.</p>
			{!cloud && <p role="status">Account access is unavailable in this build. You can still use pages on this device. Please try again after the app is updated.</p>}
			<div className="account-auth-actions" aria-busy={signing_in !== null}>
				<Button variant="primary" disabled={!cloud || signing_in !== null} onClick={() => { void start_sign_in("apple"); }}>Continue with Apple</Button>
				{process.env.NEXT_PUBLIC_GOOGLE_ENABLED === "true" && <Button disabled={!cloud || signing_in !== null} onClick={() => { void start_sign_in("google"); }}>Continue with Google</Button>}
			</div>
			{signing_in && <p role="status">Opening {signing_in === "apple" ? "Apple" : "Google"}…</p>}
			<p>{creating ? "Already have an account? " : "New to Pocketwork? "}<a href={creating ? "/account?mode=signin" : "/account?mode=create"}>{creating ? "Sign in" : "Create account"}</a></p>
			<a href="/">Continue without an account</a>
		</section>}
		{account && <><section><h2>{plan_active(plan) ? "Pocketwork Pro" : "Free plan"}</h2><p>{plan_active(plan) ? "Up to 50 pages, with cloud sync and MCP." : "Keep 3 pages at a time. Delete one to make room for another. Cloud sync and MCP are included."}</p><p>Routines are the actions. Data holds the values, entries, and displays. Pages hold both.</p><p>Upgrade or restore purchases in the iPhone app. Subscriptions renew automatically until cancelled. Cancelling never deletes or disables your existing pages.</p><a href="https://apps.apple.com/account/subscriptions">Manage Apple subscriptions</a></section>
		<section><h2>Delete account</h2><p>This permanently removes your account, cloud pages, shared status, and subscription link. Export any pages you want to keep first. Copies and exports on other devices may remain until you remove them there.</p><p>Deleting your account does not cancel an Apple subscription. Cancel it through the link above first. If you signed in with Apple, you will confirm with Apple to revoke access.</p><label className="connection-field"><span>Type DELETE to confirm</span><input className="field" value={confirm} onChange={event => set_confirm(event.target.value)} autoComplete="off" /></label><Button variant="danger" disabled={confirm !== "DELETE" || busy} onClick={() => { void remove_account(); }}>{busy ? "Please wait…" : "Delete my account"}</Button></section></>}
	</LegalPage>;
}
