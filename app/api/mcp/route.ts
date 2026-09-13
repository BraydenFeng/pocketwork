import { createClient } from "@supabase/supabase-js";
import { call_mcp_tool, mcp_tools } from "@/lib/mcp";
export const runtime = "nodejs";
export async function POST(request: Request) {
	const origin = request.headers.get("origin");
	if (origin && origin !== new URL(request.url).origin) { return new Response("Origin not allowed", { status: 403 }); }
	const authorization = request.headers.get("authorization");
	if (!authorization?.startsWith("Bearer ")) { return new Response("Sign in first", { status: 401 }); }
	const url = process.env.NEXT_PUBLIC_SUPABASE_URL, key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
	if (!url || !key) { return new Response("Cloud not configured", { status: 503 }); }
	let id: string | number | null = null;
	try {
		const text = await request.text(); if (text.length > 200000) { return new Response("Request too large", { status: 413 }); }
		const message = JSON.parse(text); id = message.id ?? null;
		const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false }, global: { headers: { Authorization: authorization } } });
		const { data, error } = await client.auth.getUser(authorization.slice(7));
		if (error || !data.user) { return new Response("Sign-in expired. Copy a fresh agent connection from Pocketwork.", { status: 401 }); }
		const reply = (result: unknown) => Response.json({ jsonrpc: "2.0", id, result }, { headers: { "Cache-Control": "no-store" } });
		if (message.method === "initialize") { return reply({ protocolVersion: "2025-11-25", capabilities: { tools: {} }, serverInfo: { name: "pocketwork", version: "0.2.0" } }); }
		if (message.method?.startsWith("notifications/")) { return new Response(null, { status: 202 }); }
		if (message.method === "ping") { return reply({}); }
		if (message.method === "tools/list") { return reply({ tools: mcp_tools }); }
		if (message.method === "tools/call") {
			try { return reply(await call_mcp_tool({ client }, { id: data.user.id, email: data.user.email ?? null }, message.params?.name, message.params?.arguments ?? {})); }
			catch (failure) { return reply({ isError: true, content: [{ type: "text", text: failure instanceof Error ? failure.message : "Routine operation failed." }] }); }
		}
		return Response.json({ jsonrpc: "2.0", id, error: { code: -32601, message: "Method not supported" } });
	} catch (failure) { return Response.json({ jsonrpc: "2.0", id, error: { code: -32603, message: failure instanceof Error ? failure.message : "MCP request failed" } }, { status: 400 }); }
}
