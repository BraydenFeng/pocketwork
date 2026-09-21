import { createPrivateKey, createPublicKey, sign, verify } from "node:crypto";
import { z } from "zod";
import { ApiError, required_env } from "./account";

export function apple_jwt(prefix: "APPLE_SIGNIN" | "APP_STORE", audience: string, extra: Record<string, unknown> = {}): string {
	const now = Math.floor(Date.now() / 1000);
	const header = Buffer.from(JSON.stringify({ alg: "ES256", kid: required_env(`${prefix}_KEY_ID`), typ: "JWT" })).toString("base64url");
	const payload = Buffer.from(JSON.stringify({ iss: required_env(`${prefix}_ISSUER_ID`), iat: now, exp: now + 300, aud: audience, ...extra })).toString("base64url");
	const key = createPrivateKey(required_env(`${prefix}_PRIVATE_KEY`).replaceAll("\\n", "\n"));
	return `${header}.${payload}.${sign("sha256", Buffer.from(`${header}.${payload}`), { key, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}
export async function apple_fetch(url: string, init: RequestInit = {}): Promise<unknown> {
	const response = await fetch(url, { ...init, signal: AbortSignal.timeout(15000), cache: "no-store", redirect: "error" });
	if (!response.ok) { throw new ApiError(`Apple could not complete this request (${response.status}). Please retry.`, 502); }
	const text = await response.text();
	if (text.length > 1000000) { throw new ApiError("Apple returned an oversized response.", 502); }
	try { return text ? JSON.parse(text) : {}; } catch { throw new ApiError("Apple returned an unreadable response.", 502); }
}
export function jws_payload(token: string): unknown {
	try {
		if (token.length > 30000 || token.split(".").length !== 3) { throw new Error("Invalid token"); }
		return JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString("utf8"));
	} catch { throw new ApiError("Invalid Apple response.", 502); }
}
export async function verify_apple_identity(token: string, subject: string, nonce: string): Promise<void> {
	const header = z.object({ alg: z.literal("RS256"), kid: z.string() }).parse(JSON.parse(Buffer.from(token.split(".")[0], "base64url").toString("utf8")));
	const keys = z.object({ keys: z.array(z.object({ kid: z.string(), kty: z.literal("RSA"), n: z.string(), e: z.string() })) }).parse(await apple_fetch("https://appleid.apple.com/auth/keys"));
	const key = keys.keys.find(entry => entry.kid === header.kid);
	if (!key || !verify("RSA-SHA256", Buffer.from(token.split(".").slice(0, 2).join(".")), createPublicKey({ key, format: "jwk" }), Buffer.from(token.split(".")[2], "base64url"))) { throw new ApiError("Apple identity could not be verified.", 403); }
	const claims = z.object({ iss: z.literal("https://appleid.apple.com"), aud: z.string(), sub: z.string(), exp: z.number(), nonce: z.string() }).parse(jws_payload(token));
	if (claims.aud !== required_env("APPLE_SIGNIN_CLIENT_ID") || claims.sub !== subject || claims.nonce !== nonce || claims.exp <= Date.now() / 1000) { throw new ApiError("Sign in with the Apple account linked to Pocketwork.", 403); }
}
