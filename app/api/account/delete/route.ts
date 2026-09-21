import { z } from "zod";
import { api_failure, json_body, require_user } from "@/lib/server/account";
import { start_deletion } from "@/lib/server/delete-account";

export const runtime = "nodejs";
export async function POST(request: Request) {
	try {
		const user = await require_user(request);
		const { platform } = z.object({ confirm: z.literal("DELETE"), platform: z.enum(["web", "ios"]) }).strict().parse(await json_body(request));
		return Response.json(await start_deletion(user, platform), { headers: { "Cache-Control": "no-store" } });
	} catch (error) { return api_failure(error); }
}
