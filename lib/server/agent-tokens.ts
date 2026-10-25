import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import type { User } from "@supabase/supabase-js";
import { z } from "zod";
import { admin_client, ApiError } from "./account";

const prefix = "pw_agent_";
export const MAX_AGENT_TOKENS = 5;
const token_pattern = /^pw_agent_([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})_([\w-]{43})$/;
const stored_schema = z.array(z.object({ id: z.string(), hash: z.string().regex(/^[0-9a-f]{64}$/), created_at: z.string() }));
type StoredToken = z.infer<typeof stored_schema>[number];
const invalid = "This agent connection was revoked or is invalid. Copy a new one from Pocketwork.";

function digest(secret: string): string { return createHash("sha256").update(secret).digest("hex"); }
export function is_agent_token(token: string): boolean { return token.startsWith(prefix); }

// Only hashes are kept, in app_metadata, which only the service role can change.
function stored_tokens(user: User): StoredToken[] {
	const parsed = stored_schema.safeParse(user.app_metadata?.agent_tokens ?? []);
	return parsed.success ? parsed.data : [];
}
async function save_tokens(user_id: string, tokens: StoredToken[]): Promise<void> {
	const { error } = await admin_client().auth.admin.updateUserById(user_id, { app_metadata: { agent_tokens: tokens } });
	if (error) { throw new ApiError("Could not update agent connections. Please retry.", 502); }
}

export function agent_token_count(user: User): number { return stored_tokens(user).length; }

export async function create_agent_token(user: User): Promise<{ token: string; count: number }> {
	const secret = randomBytes(32).toString("base64url");
	const tokens = [...stored_tokens(user), { id: randomBytes(4).toString("hex"), hash: digest(secret), created_at: new Date().toISOString() }].slice(-MAX_AGENT_TOKENS);
	await save_tokens(user.id, tokens);
	return { token: `${prefix}${user.id}_${secret}`, count: tokens.length };
}

export async function revoke_agent_tokens(user: User): Promise<void> { await save_tokens(user.id, []); }

export async function verify_agent_token(token: string): Promise<User> {
	const match = token_pattern.exec(token);
	if (!match) { throw new ApiError(invalid, 401); }
	const { data, error } = await admin_client().auth.admin.getUserById(match[1]);
	if (error && error.status !== 404) { throw new ApiError("Could not check this agent connection. Please retry.", 502); }
	if (!data?.user) { throw new ApiError(invalid, 401); }
	const expected = Buffer.from(digest(match[2]), "hex");
	if (!stored_tokens(data.user).some(stored => timingSafeEqual(Buffer.from(stored.hash, "hex"), expected))) { throw new ApiError(invalid, 401); }
	return data.user;
}
