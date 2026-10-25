import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { User } from "@supabase/supabase-js";
import { create_agent_token, MAX_AGENT_TOKENS, revoke_agent_tokens, verify_agent_token } from "../lib/server/agent-tokens";
import { call_mcp_tool } from "../lib/mcp";
import { POST as mcp } from "../app/api/mcp/route";
import { DELETE as revoke_route, GET as count_route, POST as create_route } from "../app/api/agent-tokens/route";

const mocks = vi.hoisted(() => ({ update: vi.fn(), get_by_id: vi.fn(), get_user: vi.fn() }));
vi.mock("@supabase/supabase-js", () => ({ createClient: () => ({ auth: { getUser: mocks.get_user, admin: { updateUserById: mocks.update, getUserById: mocks.get_by_id } } }) }));
vi.mock("../lib/mcp", () => ({ call_mcp_tool: vi.fn(async () => ({ content: [] })), mcp_tools: [] }));

const owner_id = "0b5c3a1e-2f4d-4e6a-8b9c-1d2e3f4a5b6c";
let metadata: Record<string, unknown> = {};
const owner = () => ({ id: owner_id, email: "owner@example.com", app_metadata: structuredClone(metadata) }) as unknown as User;
const secret_of = (token: string) => token.slice(-43);

beforeEach(() => {
	vi.clearAllMocks(); metadata = {};
	vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://example.supabase.co"); vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "test-anon"); vi.stubEnv("SUPABASE_SERVICE_ROLE_KEY", "test-only");
	mocks.update.mockImplementation(async (_id: string, attributes: { app_metadata: Record<string, unknown> }) => { metadata = { ...metadata, ...attributes.app_metadata }; return { data: { user: owner() }, error: null }; });
	mocks.get_by_id.mockImplementation(async (id: string) => id === owner_id ? { data: { user: owner() }, error: null } : { data: { user: null }, error: { status: 404, message: "User not found" } });
	mocks.get_user.mockImplementation(async (jwt: string) => jwt === "session-jwt" ? { data: { user: owner() }, error: null } : { data: { user: null }, error: { status: 401, message: "invalid JWT" } });
});
afterEach(() => { vi.unstubAllEnvs(); });

it("stores only a hash and accepts the token until it is revoked", async () => {
	const { token, count } = await create_agent_token(owner());
	expect(count).toBe(1); expect(token.startsWith(`pw_agent_${owner_id}_`)).toBe(true);
	expect(JSON.stringify(metadata)).not.toContain(secret_of(token));
	expect((await verify_agent_token(token)).id).toBe(owner_id);
	await revoke_agent_tokens(owner());
	await expect(verify_agent_token(token)).rejects.toThrow("revoked");
});

it("keeps at most five connections and drops the oldest", async () => {
	const tokens: string[] = [];
	for (let index = 0; index <= MAX_AGENT_TOKENS; index++) { tokens.push((await create_agent_token(owner())).token); }
	expect(metadata.agent_tokens).toHaveLength(MAX_AGENT_TOKENS);
	await expect(verify_agent_token(tokens[0])).rejects.toThrow("revoked");
	expect((await verify_agent_token(tokens[MAX_AGENT_TOKENS])).id).toBe(owner_id);
});

it("rejects malformed, altered, and other-account tokens", async () => {
	const { token } = await create_agent_token(owner());
	await expect(verify_agent_token("pw_agent_not-a-token")).rejects.toThrow("revoked");
	await expect(verify_agent_token(token.slice(0, -1) + (token.endsWith("A") ? "B" : "A"))).rejects.toThrow("revoked");
	await expect(verify_agent_token(token.replace(owner_id, "11111111-2222-4333-8444-555555555555"))).rejects.toThrow("revoked");
});

it("reports an outage instead of calling a working connection revoked", async () => {
	const { token } = await create_agent_token(owner());
	mocks.get_by_id.mockResolvedValueOnce({ data: { user: null }, error: { status: 500, message: "unavailable" } });
	await expect(verify_agent_token(token)).rejects.toMatchObject({ status: 502 });
});

it("runs MCP tools as the verified account and stops after revocation", async () => {
	const { token } = await create_agent_token(owner());
	const request = () => new Request("https://pocketwork.example/api/mcp", { method: "POST", headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "list_pages", arguments: {} } }) });
	expect((await mcp(request())).status).toBe(200);
	expect(call_mcp_tool).toHaveBeenCalledWith(expect.objectContaining({ client: expect.anything() }), { id: owner_id, email: "owner@example.com" }, "list_pages", {});
	await revoke_agent_tokens(owner());
	const revoked = await mcp(request());
	expect(revoked.status).toBe(401); expect(await revoked.text()).toContain("revoked");
	expect(call_mcp_tool).toHaveBeenCalledTimes(1);
});

it("lets only a signed-in session create, count, or revoke connections", async () => {
	const request = (method: string, bearer: string) => new Request("https://pocketwork.example/api/agent-tokens", { method, headers: { authorization: `Bearer ${bearer}` } });
	const created = await (await create_route(request("POST", "session-jwt"))).json();
	expect(created.token.startsWith("pw_agent_")).toBe(true);
	expect((await create_route(request("POST", created.token))).status).toBe(401);
	expect(await (await count_route(request("GET", "session-jwt"))).json()).toEqual({ count: 1 });
	expect((await revoke_route(request("DELETE", created.token))).status).toBe(401);
	expect(await (await revoke_route(request("DELETE", "session-jwt"))).json()).toEqual({ count: 0 });
	expect(metadata.agent_tokens).toEqual([]);
});
