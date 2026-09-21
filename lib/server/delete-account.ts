import { createHash, randomBytes } from "node:crypto";
import type { User } from "@supabase/supabase-js";
import { z } from "zod";
import { admin_client, ApiError, required_env, site_url } from "./account";
import { apple_fetch, apple_jwt, verify_apple_identity } from "./apple";

export function state_hash(state: string): string { return createHash("sha256").update(state).digest("hex"); }
async function remove_user(user_id: string): Promise<void> {
	const { error } = await admin_client().auth.admin.deleteUser(user_id);
	if (error) { throw new ApiError("Account deletion did not finish. Please sign in and retry.", 502); }
}
export async function start_deletion(user: User, platform: "web" | "ios") {
	const apple = user.identities?.find(identity => identity.provider === "apple");
	if (!apple) { await remove_user(user.id); return { deleted: true as const }; }
	const subject = apple.identity_data?.sub;
	if (typeof subject !== "string" || !subject) { throw new ApiError("Your Apple identity is missing. Contact support before deleting.", 409); }
	const client_id = required_env("APPLE_SIGNIN_CLIENT_ID");
	// Fail before redirecting if revocation is not configured.
	apple_jwt("APPLE_SIGNIN", "https://appleid.apple.com", { sub: client_id });
	const state = randomBytes(32).toString("base64url"), nonce = randomBytes(32).toString("base64url");
	const { error } = await admin_client().from("account_deletion_requests").upsert({ state_hash: state_hash(state), user_id: user.id, apple_subject: subject, nonce, platform, expires_at: new Date(Date.now() + 600000).toISOString() }, { onConflict: "user_id" });
	if (error) { throw new ApiError("Could not start account deletion. Please retry.", 502); }
	const url = new URL("https://appleid.apple.com/auth/authorize");
	url.search = new URLSearchParams({ client_id, redirect_uri: `${site_url()}/api/account/apple-callback`, response_type: "code", response_mode: "form_post", state, nonce }).toString();
	return { deleted: false as const, authorize_url: url.toString(), state };
}
export async function finish_apple_deletion(form: URLSearchParams): Promise<string> {
	const state = form.get("state") ?? "";
	if (!/^[\w-]{43}$/.test(state)) { throw new ApiError("This deletion link is invalid or expired.", 403); }
	const { data, error } = await admin_client().from("account_deletion_requests").delete().eq("state_hash", state_hash(state)).gt("expires_at", new Date().toISOString()).select("user_id,apple_subject,nonce,platform").maybeSingle();
	if (error || !data) { throw new ApiError("This deletion link is invalid, already used, or expired. Start again from Account.", 403); }
	const result = new URL(data.platform === "ios" ? "com.braydenfeng.pocketwork://account/deleted" : `${site_url()}/account`);
	result.searchParams.set("state", state);
	try {
		const code = form.get("code");
		if (!code || form.has("error")) { throw new ApiError("Deletion cancelled. Your account was not deleted."); }
		const client_id = required_env("APPLE_SIGNIN_CLIENT_ID"), client_secret = apple_jwt("APPLE_SIGNIN", "https://appleid.apple.com", { sub: client_id });
		const tokens = z.object({ access_token: z.string(), refresh_token: z.string().optional(), id_token: z.string() }).parse(await apple_fetch("https://appleid.apple.com/auth/token", { method: "POST", body: new URLSearchParams({ client_id, client_secret, code, grant_type: "authorization_code", redirect_uri: `${site_url()}/api/account/apple-callback` }) }));
		await verify_apple_identity(tokens.id_token, data.apple_subject, data.nonce);
		await apple_fetch("https://appleid.apple.com/auth/revoke", { method: "POST", body: new URLSearchParams({ client_id, client_secret, token: tokens.refresh_token ?? tokens.access_token, token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token" }) });
		await remove_user(data.user_id);
		result.searchParams.set("deleted", "true");
	} catch (failure) {
		console.error("Apple account deletion failed", failure instanceof Error ? failure.name : "Unknown error");
		result.searchParams.set("deleted", "false");
	}
	return result.toString();
}
