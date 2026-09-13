import { describe, expect, it, vi } from "vitest";
import { createClient } from "@supabase/supabase-js";
import { fetch_library, push_library } from "../lib/cloud";
import { empty_library } from "../lib/library";

const account = { id: "f81d4fae-7dec-11d0-a765-00a0c91e6bf6", email: "test@example.com" };
function connection(status: number, body: unknown) {
	const request = vi.fn(async () => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } }));
	const client = createClient("https://example.supabase.co", "test-key", { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: request } });
	return { cloud: { client }, request };
}
describe("cloud concurrency boundary", () => {
	it("constrains writes to the signed-in owner and exact read revision", async () => {
		const { cloud, request } = connection(200, [{ user_id: account.id }]);
		expect(await push_library(cloud, account, empty_library, { library: empty_library, updated_at: "2026-09-13T17:00:00Z" })).toBe(true);
		const [url, options] = request.mock.calls[0] as unknown as [string, RequestInit];
		expect(String(url)).toContain("updated_at=eq.");
		expect(String(url)).toContain(account.id);
		expect(options.method).toBe("PATCH");
	});
	it("retries a revision that another device already changed", async () => {
		const { cloud } = connection(200, []);
		expect(await push_library(cloud, account, empty_library, { library: empty_library, updated_at: "old" })).toBe(false);
	});
	it("does not overwrite a row created concurrently", async () => {
		const { cloud } = connection(409, { code: "23505", message: "duplicate key" });
		expect(await push_library(cloud, account, empty_library, null)).toBe(false);
	});
	it("rejects malformed cloud libraries instead of replacing the local copy", async () => {
		const { cloud } = connection(200, { library: { schema_version: 9 }, updated_at: "now" });
		await expect(fetch_library(cloud, account)).rejects.toThrow();
	});
	it("reports access errors as failures rather than empty libraries", async () => {
		const { cloud } = connection(403, { message: "permission denied" });
		await expect(fetch_library(cloud, account)).rejects.toThrow("Could not read");
	});
});
