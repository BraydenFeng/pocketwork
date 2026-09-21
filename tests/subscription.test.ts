import { expect, it } from "vitest";
import { verified_plan_response } from "../lib/server/subscription";
const user = "11111111-1111-4111-8111-111111111111";
function token(value: unknown) { return `header.${Buffer.from(JSON.stringify(value)).toString("base64url")}.signature`; }
function reply(status = 1, extra = {}, renewal = {}) { return { data: [{ lastTransactions: [{ status, signedTransactionInfo: token({ bundleId: "bundle", productId: "pro", appAccountToken: user, originalTransactionId: "123", expiresDate: 2000, environment: "Production", ...extra }), signedRenewalInfo: token(renewal) }] }] }; }
it("accepts matching Apple-returned subscription and its account token", () => {
	expect(verified_plan_response(reply(), user, "bundle", "pro", false, 1000).pro).toBe(true);
});
it.each([2, 3, 5])("does not unlock expired, retrying, or revoked status %s", status => {
	expect(verified_plan_response(reply(status), user, "bundle", "pro", false, 1000).pro).toBe(false);
});
it("rejects expiration and revocation even with an active status", () => {
	expect(verified_plan_response(reply(1, { expiresDate: 1000 }), user, "bundle", "pro", false, 1000).pro).toBe(false);
	expect(verified_plan_response(reply(1, { revocationDate: 900 }), user, "bundle", "pro", false, 1000).pro).toBe(false);
});
it("accepts only a current billing grace period", () => {
	expect(verified_plan_response(reply(4, { expiresDate: 900 }, { gracePeriodExpiresDate: 1500 }), user, "bundle", "pro", false, 1000).pro).toBe(true);
	expect(verified_plan_response(reply(4, { expiresDate: 900 }), user, "bundle", "pro", false, 1000).pro).toBe(false);
});
it.each([{ appAccountToken: "22222222-2222-4222-8222-222222222222" }, { bundleId: "other" }, { productId: "other" }, { environment: "Sandbox" }])("rejects a mismatched purchase %j", fields => {
	expect(() => verified_plan_response(reply(1, fields), user, "bundle", "pro", false, 1000)).toThrow("does not belong");
});
