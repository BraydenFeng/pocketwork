import { z } from "zod";
import { api_failure, json_body, require_user } from "@/lib/server/account";
import { account_plan, refresh_subscription } from "@/lib/server/subscription";

export const runtime = "nodejs";
export async function GET(request: Request) {
	try { const user = await require_user(request); return Response.json(await account_plan(user.id), { headers: { "Cache-Control": "no-store" } }); }
	catch (error) { return api_failure(error); }
}
export async function POST(request: Request) {
	try {
		const user = await require_user(request);
		const { transaction_id } = z.object({ transaction_id: z.string().regex(/^\d{1,32}$/) }).strict().parse(await json_body(request));
		return Response.json(await refresh_subscription(user.id, transaction_id));
	} catch (error) { return api_failure(error); }
}
