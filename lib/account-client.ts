import type { Cloud } from "./cloud";
import { z } from "zod";
import { free_plan, type PagePlan } from "./page-plan";

export async function account_request(cloud: Cloud, path: string, body?: unknown): Promise<unknown> {
	const { data, error } = await cloud.client.auth.getSession();
	if (error || !data.session) { throw new Error("Sign in to continue."); }
	const response = await fetch(path, { method: body === undefined ? "GET" : "POST", headers: { Authorization: `Bearer ${data.session.access_token}`, "Content-Type": "application/json" }, ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(30000), cache: "no-store" });
	const reply = await response.json();
	if (!response.ok) { throw new Error(typeof reply.error === "string" ? reply.error : "The account service is unavailable."); }
	return reply;
}
export async function fetch_plan(cloud: Cloud): Promise<PagePlan> {
	if (process.env.NEXT_PUBLIC_SUBSCRIPTIONS_ENABLED !== "true") { return free_plan; }
	return z.object({ pro: z.boolean(), expires_at: z.string().nullable(), configured: z.boolean() }).parse(await account_request(cloud, "/api/subscription"));
}
