import { api_failure, require_user } from "../../../lib/server/account";
import { agent_token_count, create_agent_token, revoke_agent_tokens } from "../../../lib/server/agent-tokens";

export const runtime = "nodejs";
const headers = { "Cache-Control": "no-store" };
export async function GET(request: Request) {
	try { return Response.json({ count: agent_token_count(await require_user(request)) }, { headers }); }
	catch (error) { return api_failure(error); }
}
export async function POST(request: Request) {
	try { return Response.json(await create_agent_token(await require_user(request)), { headers }); }
	catch (error) { return api_failure(error); }
}
export async function DELETE(request: Request) {
	try { await revoke_agent_tokens(await require_user(request)); return Response.json({ count: 0 }, { headers }); }
	catch (error) { return api_failure(error); }
}
