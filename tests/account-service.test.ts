import { beforeEach, afterEach, expect, it, vi } from "vitest";
import type { User } from "@supabase/supabase-js";
import { bounded_text, require_user } from "../lib/server/account";
import { start_deletion, finish_apple_deletion, state_hash } from "../lib/server/delete-account";
const mocks = vi.hoisted(() => ({ remove: vi.fn(), get_user: vi.fn(), from: vi.fn(), apple: vi.fn(), identity: vi.fn() }));
vi.mock("@supabase/supabase-js", () => ({ createClient: () => ({ auth: { getUser: mocks.get_user, admin: { deleteUser: mocks.remove } }, from: mocks.from }) }));
vi.mock("../lib/server/apple", () => ({ apple_fetch: mocks.apple, verify_apple_identity: mocks.identity, apple_jwt: () => "signed-server-secret" }));
const user = { id: "owner", identities: [] } as unknown as User;
const apple_user = { ...user, identities: [{ provider: "apple", identity_data: { sub: "apple-owner" } }] } as unknown as User;
beforeEach(() => {
	vi.resetAllMocks(); vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://example.supabase.co"); vi.stubEnv("SUPABASE_SERVICE_ROLE_KEY", "test-only"); vi.stubEnv("SITE_URL", "https://pocketwork.example"); vi.stubEnv("APPLE_SIGNIN_CLIENT_ID", "test.client");
	mocks.remove.mockResolvedValue({ error: null }); mocks.identity.mockResolvedValue(undefined);
});
afterEach(() => { vi.unstubAllEnvs(); });
it("requires bearer auth and refuses foreign browser origins", async () => {
	await expect(require_user(new Request("https://pocketwork.example/api/account/delete"))).rejects.toThrow("Sign in");
	await expect(require_user(new Request("https://pocketwork.example/api/account/delete", { headers: { origin: "https://evil.example", authorization: "Bearer token" } }))).rejects.toThrow("Cross-origin");
	expect(mocks.get_user).not.toHaveBeenCalled();
});
it("validates the bearer with Supabase rather than decoding it locally", async () => {
	mocks.get_user.mockResolvedValue({ data: { user }, error: null });
	expect(await require_user(new Request("https://pocketwork.example/api", { headers: { authorization: "Bearer test-token" } }))).toEqual(user);
	expect(mocks.get_user).toHaveBeenCalledWith("test-token");
});
it("bounds streamed input even without a content-length", async () => {
	await expect(bounded_text(new Request("https://pocketwork.example", { method: "POST", body: "0123456789" }), 5)).rejects.toThrow("too large");
});
it("deletes only the validated non-Apple account", async () => {
	expect(await start_deletion(user, "web")).toEqual({ deleted: true });
	expect(mocks.remove).toHaveBeenCalledWith("owner");
});
it("does not claim deletion when the administrator call fails", async () => {
	mocks.remove.mockResolvedValue({ error: { message: "failure" } });
	await expect(start_deletion(user, "web")).rejects.toThrow("did not finish");
});
it("stores a hashed, expiring handshake before Apple confirmation", async () => {
	const upsert = vi.fn().mockResolvedValue({ error: null }); mocks.from.mockReturnValue({ upsert });
	const reply = await start_deletion(apple_user, "ios");
	if (reply.deleted) { throw new Error("Unexpected deletion"); }
	expect(upsert.mock.calls[0][0]).toMatchObject({ user_id: "owner", apple_subject: "apple-owner", state_hash: state_hash(reply.state), platform: "ios" });
	expect(reply.authorize_url).toContain("https://appleid.apple.com/auth/authorize?"); expect(mocks.remove).not.toHaveBeenCalled();
});
function handshake(found = true) {
	const chain = { delete: vi.fn(), eq: vi.fn(), gt: vi.fn(), select: vi.fn(), maybeSingle: vi.fn() };
	for (const name of ["delete", "eq", "gt", "select"] as const) { chain[name].mockReturnValue(chain); }
	chain.maybeSingle.mockResolvedValue({ error: null, data: found ? { user_id: "owner", apple_subject: "apple-owner", nonce: "nonce", platform: "web" } : null }); mocks.from.mockReturnValue(chain); return chain;
}
it("consumes a handshake, verifies identity, revokes Apple, then deletes", async () => {
	handshake(); mocks.apple.mockResolvedValueOnce({ access_token: "access", refresh_token: "refresh", id_token: "identity" }).mockResolvedValueOnce({});
	const result = await finish_apple_deletion(new URLSearchParams({ state: "a".repeat(43), code: "code" }));
	expect(result).toContain("deleted=true"); expect(mocks.identity).toHaveBeenCalledWith("identity", "apple-owner", "nonce");
	expect(mocks.apple.mock.calls[1][0]).toBe("https://appleid.apple.com/auth/revoke"); expect(mocks.remove).toHaveBeenCalledWith("owner");
});
it("rejects a replay and never deletes after failed Apple verification", async () => {
	handshake(false); await expect(finish_apple_deletion(new URLSearchParams({ state: "a".repeat(43), code: "code" }))).rejects.toThrow("already used");
	handshake(); mocks.apple.mockResolvedValueOnce({ access_token: "access", id_token: "identity" }); mocks.identity.mockRejectedValueOnce(new Error("wrong account"));
	const log = vi.spyOn(console, "error").mockImplementation(() => undefined);
	expect(await finish_apple_deletion(new URLSearchParams({ state: "a".repeat(43), code: "code" }))).toContain("deleted=false");
	expect(mocks.remove).not.toHaveBeenCalled(); log.mockRestore();
});
