import { createClient, type User } from "@supabase/supabase-js";
import { ZodError } from "zod";

export class ApiError extends Error {
	constructor(message: string, public status = 400) { super(message); }
}
export function required_env(name: string): string {
	const value = process.env[name];
	if (!value) { throw new ApiError("This service is not configured yet.", 503); }
	return value;
}
export function admin_client() {
	return createClient(required_env("NEXT_PUBLIC_SUPABASE_URL"), required_env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false, autoRefreshToken: false } });
}
export function site_url(): string {
	const url = new URL(required_env("SITE_URL"));
	if (url.protocol !== "https:" || url.username || url.password) { throw new ApiError("The public HTTPS address is not configured.", 503); }
	return url.origin;
}
export async function require_user(request: Request): Promise<User> {
	const origin = request.headers.get("origin");
	if (origin && origin !== new URL(request.url).origin) { throw new ApiError("Cross-origin request refused.", 403); }
	const token = request.headers.get("authorization")?.match(/^Bearer ([^\s]+)$/)?.[1];
	if (!token) { throw new ApiError("Sign in to continue.", 401); }
	const { data, error } = await admin_client().auth.getUser(token);
	if (error || !data.user) { throw new ApiError("Your sign-in expired. Sign in again.", 401); }
	return data.user;
}
export async function bounded_text(request: Request, limit = 16384): Promise<string> {
	if (Number(request.headers.get("content-length")) > limit) { throw new ApiError("Request is too large.", 413); }
	const reader = request.body?.getReader();
	if (!reader) { return ""; }
	const chunks: Uint8Array[] = []; let size = 0;
	try {
		while (true) {
			const { done, value } = await reader.read(); if (done) { break; }
			size += value.length;
			if (size > limit) { await reader.cancel(); throw new ApiError("Request is too large.", 413); }
			chunks.push(value);
		}
		return Buffer.concat(chunks).toString("utf8");
	} finally { reader.releaseLock(); }
}
export async function json_body(request: Request): Promise<unknown> {
	const body = await bounded_text(request);
	try { return JSON.parse(body); } catch { throw new ApiError("Invalid JSON."); }
}
export function api_failure(error: unknown): Response {
	if (error instanceof ZodError) { return Response.json({ error: "Invalid request or service response." }, { status: 400 }); }
	if (error instanceof ApiError) { return Response.json({ error: error.message }, { status: error.status }); }
	console.error("Account service failed", error instanceof Error ? error.name : "Unknown error");
	return Response.json({ error: "The service could not complete this request. Please try again." }, { status: 502 });
}
