import { z } from "zod";
import { admin_client, ApiError, required_env } from "./account";
import { apple_fetch, apple_jwt, jws_payload } from "./apple";
import { free_plan, type PagePlan } from "../page-plan";

const transaction_schema = z.object({ bundleId: z.string(), productId: z.string(), appAccountToken: z.string().uuid(), originalTransactionId: z.string(), expiresDate: z.number(), environment: z.enum(["Sandbox", "Production"]), revocationDate: z.number().optional() });
const statuses_schema = z.object({ data: z.array(z.object({ lastTransactions: z.array(z.object({ status: z.number(), signedTransactionInfo: z.string(), signedRenewalInfo: z.string() })) })) });

// Only accepts payloads fetched directly from Apple's HTTPS API, never client-supplied JWS.
export function verified_plan_response(value: unknown, user_id: string, bundle: string, product: string, sandbox: boolean, now = Date.now()) {
	const entries = statuses_schema.parse(value).data.flatMap(group => group.lastTransactions);
	for (const entry of entries) {
		const transaction = transaction_schema.parse(jws_payload(entry.signedTransactionInfo));
		if (transaction.appAccountToken.toLowerCase() !== user_id.toLowerCase() || transaction.bundleId !== bundle || transaction.productId !== product || transaction.environment !== (sandbox ? "Sandbox" : "Production")) { continue; }
		const renewal = z.object({ gracePeriodExpiresDate: z.number().optional() }).parse(jws_payload(entry.signedRenewalInfo));
		const expiration = entry.status === 4 ? renewal.gracePeriodExpiresDate ?? transaction.expiresDate : transaction.expiresDate;
		return { original_transaction_id: transaction.originalTransactionId, pro: [1, 4].includes(entry.status) && !transaction.revocationDate && expiration > now, expires_at: new Date(expiration).toISOString(), verified_at: new Date(now).toISOString() };
	}
	throw new ApiError("This subscription does not belong to this Pocketwork account.", 403);
}
export async function refresh_subscription(user_id: string, transaction_id: string): Promise<PagePlan> {
	if (!/^\d{1,32}$/.test(transaction_id)) { throw new ApiError("Invalid transaction ID."); }
	const sandbox = process.env.APP_STORE_ENVIRONMENT === "Sandbox";
	const host = sandbox ? "api.storekit-sandbox.itunes.apple.com" : "api.storekit.apple.com";
	const bundle = required_env("APP_STORE_BUNDLE_ID");
	const response = await apple_fetch(`https://${host}/inApps/v1/subscriptions/${transaction_id}`, { headers: { Authorization: `Bearer ${apple_jwt("APP_STORE", "appstoreconnect-v1", { bid: bundle })}` } });
	const row = verified_plan_response(response, user_id, bundle, required_env("APP_STORE_PRODUCT_ID"), sandbox);
	const { error } = await admin_client().from("page_subscriptions").upsert({ user_id, ...row }, { onConflict: "user_id" });
	if (error) { throw new ApiError("Could not save your verified subscription. Restore purchases to retry.", 502); }
	return { pro: row.pro, expires_at: row.expires_at, configured: true };
}
export async function account_plan(user_id: string): Promise<PagePlan> {
	if (!process.env.APP_STORE_PRODUCT_ID) { return free_plan; }
	const { data, error } = await admin_client().from("page_subscriptions").select("original_transaction_id,pro,expires_at,verified_at").eq("user_id", user_id).maybeSingle();
	if (error) { throw new ApiError("Could not read your subscription.", 502); }
	if (!data) { return { ...free_plan, configured: true }; }
	if (Date.parse(data.verified_at) < Date.now() - 60000) { return refresh_subscription(user_id, data.original_transaction_id); }
	return { pro: data.pro && Date.parse(data.expires_at) > Date.now(), expires_at: data.expires_at, configured: true };
}
