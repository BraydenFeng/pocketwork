import { api_failure, bounded_text } from "@/lib/server/account";
import { finish_apple_deletion } from "@/lib/server/delete-account";

export const runtime = "nodejs";
export async function POST(request: Request) {
	try { return new Response(null, { status: 303, headers: { Location: await finish_apple_deletion(new URLSearchParams(await bounded_text(request))), "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" } }); }
	catch (error) { return api_failure(error); }
}
