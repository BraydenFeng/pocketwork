import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { admin_client } from "../lib/server/account";
import { apple_fetch } from "../lib/server/apple";
import { refresh_subscription, verify_test_subscription } from "../lib/server/subscription";
import { POST } from "../app/api/subscription/sandbox/route";

vi.mock("../lib/server/apple", async import_original => ({ ...await import_original<typeof import("../lib/server/apple")>(), apple_fetch: vi.fn(), apple_jwt: vi.fn(() => "test-only-token") }));
vi.mock("../lib/server/account", async import_original => ({ ...await import_original<typeof import("../lib/server/account")>(), admin_client: vi.fn() }));

const user = "11111111-1111-4111-8111-111111111111";
const future = Date.now() + 86400000;
const upsert = vi.fn();
function token(value: unknown) { return `header.${Buffer.from(JSON.stringify(value)).toString("base64url")}.signature`; }
function reply(environment = "Sandbox", extra = {}, status = 1) {
	return { data: [{ lastTransactions: [{ status, signedTransactionInfo: token({ bundleId: "bundle", productId: "pro", appAccountToken: user, originalTransactionId: "123", expiresDate: future, environment, ...extra }), signedRenewalInfo: token({}) }] }] };
}

beforeEach(() => {
	vi.stubEnv("APP_STORE_BUNDLE_ID", "bundle");
	vi.stubEnv("APP_STORE_PRODUCT_ID", "pro");
	vi.stubEnv("APP_STORE_ENVIRONMENT", "Production");
	vi.mocked(admin_client).mockReturnValue({ from: vi.fn(() => ({ upsert })) } as unknown as ReturnType<typeof admin_client>);
	upsert.mockResolvedValue({ error: null });
});
afterEach(() => { vi.resetAllMocks(); vi.unstubAllEnvs(); });

it("verifies sandbox purchases without creating any production entitlement", async () => {
	vi.mocked(apple_fetch).mockResolvedValue(reply());
	expect(await verify_test_subscription(user, "123")).toEqual({ pro: true, expires_at: new Date(future).toISOString(), configured: true, environment: "Sandbox" });
	expect(apple_fetch).toHaveBeenCalledWith("https://api.storekit-sandbox.apple.com/inApps/v1/subscriptions/123", expect.any(Object));
	expect(admin_client).not.toHaveBeenCalled();
});
it.each([2, 3, 5])("does not grant sandbox access for inactive status %s", async status => {
	vi.mocked(apple_fetch).mockResolvedValue(reply("Sandbox", {}, status));
	expect((await verify_test_subscription(user, "123")).pro).toBe(false);
	expect(admin_client).not.toHaveBeenCalled();
});
it.each([{ environment: "Production" }, { appAccountToken: "22222222-2222-4222-8222-222222222222" }, { bundleId: "other" }, { productId: "other" }])("rejects sandbox identity mismatch %j", async fields => {
	vi.mocked(apple_fetch).mockResolvedValue(reply("Sandbox", fields));
	await expect(verify_test_subscription(user, "123")).rejects.toThrow("does not belong");
	expect(admin_client).not.toHaveBeenCalled();
});
it("never falls back to sandbox or writes on a production Apple failure", async () => {
	vi.mocked(apple_fetch).mockRejectedValue(new Error("Apple unavailable"));
	await expect(refresh_subscription(user, "123")).rejects.toThrow("Apple unavailable");
	expect(apple_fetch).toHaveBeenCalledTimes(1);
	expect(admin_client).not.toHaveBeenCalled();
});
it("refuses a misconfigured live environment before a network call", async () => {
	vi.stubEnv("APP_STORE_ENVIRONMENT", "Sandbox");
	await expect(refresh_subscription(user, "123")).rejects.toThrow("Production environment");
	expect(apple_fetch).not.toHaveBeenCalled();
	expect(admin_client).not.toHaveBeenCalled();
});
it("persists only a matching production purchase", async () => {
	vi.mocked(apple_fetch).mockResolvedValue(reply("Production"));
	expect((await refresh_subscription(user, "123")).pro).toBe(true);
	expect(upsert).toHaveBeenCalledWith(expect.objectContaining({ user_id: user, pro: true, original_transaction_id: "123" }), { onConflict: "user_id" });
});
it("refuses a sandbox response on the live purchase path", async () => {
	vi.mocked(apple_fetch).mockResolvedValue(reply());
	await expect(refresh_subscription(user, "123")).rejects.toThrow("does not belong");
	expect(admin_client).not.toHaveBeenCalled();
});
it("requires sign-in before calling Apple for a test purchase", async () => {
	const response = await POST(new Request("https://pocketwork.test/api/subscription/sandbox", { method: "POST", body: JSON.stringify({ transaction_id: "123" }) }));
	expect(response.status).toBe(401);
	expect(apple_fetch).not.toHaveBeenCalled();
});
it("refuses cross-origin purchase verification", async () => {
	const response = await POST(new Request("https://pocketwork.test/api/subscription/sandbox", { method: "POST", headers: { Origin: "https://other.test", Authorization: "Bearer fake" }, body: JSON.stringify({ transaction_id: "123" }) }));
	expect(response.status).toBe(403);
	expect(apple_fetch).not.toHaveBeenCalled();
});
