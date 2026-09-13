import { z } from "zod";
import { document_schema } from "./document";
import { empty_library, upsert_tool, delete_tool } from "./library";
import { fetch_library, push_library, type Account, type Cloud } from "./cloud";
import { personal_routine } from "./personal-routine";

const object = { type: "object", properties: {}, additionalProperties: false };
export const mcp_tools = [
	{ name: "list_routines", description: "Read your saved routine library. App selections and home coordinates stay on the phone.", inputSchema: object, annotations: { readOnlyHint: true } },
	{ name: "get_capabilities", description: "Read routine format and enforcement limits before designing a routine.", inputSchema: object, annotations: { readOnlyHint: true } },
	{ name: "save_routine", description: "Create or update a validated routine in this account. Requires a supplied routine document. Never executes code.", inputSchema: { type: "object", properties: { document: { type: "object" } }, required: ["document"], additionalProperties: false }, annotations: { destructiveHint: false, idempotentHint: true } },
	{ name: "delete_routine", description: "Delete a routine from this account and remember the deletion for other devices.", inputSchema: { type: "object", properties: { id: { type: "string" } }, required: ["id"], additionalProperties: false }, annotations: { destructiveHint: true, idempotentHint: true } },
	{ name: "seed_home_allowance", description: "Add the requested home-only distraction routine if absent. Never overwrites later edits. Phone setup is required before activation.", inputSchema: object, annotations: { destructiveHint: false, idempotentHint: true } },
];
function content(value: unknown) { return { content: [{ type: "text", text: JSON.stringify(value) }] }; }
export async function call_mcp_tool(cloud: Cloud, account: Account, name: string, args: unknown) {
	if (name === "get_capabilities") { return content({ document_schema: z.toJSONSchema(document_schema, { unrepresentable: "any" }), home_allowance: "One home allowance per phone, daily shared windows, home-only whole-minute usage checkpoints; a final partial minute may be lost at departure. Home geofence is 150 m and OS callbacks may be delayed. Phone setup/permissions required. Cloud changes apply when the phone app opens." }); }
	if (name === "list_routines") { return content((await fetch_library(cloud, account))?.library ?? empty_library); }
	if (!["save_routine", "delete_routine", "seed_home_allowance"].includes(name)) { throw new Error("Unknown routine tool."); }
	const id = name === "delete_routine" ? z.object({ id: z.string().regex(/^[a-zA-Z0-9_-]{1,64}$/) }).strict().parse(args).id : null;
	const document = name === "save_routine" ? z.object({ document: document_schema }).strict().parse(args).document : personal_routine;
	for (let attempt = 0; attempt < 5; attempt++) {
		const remote = await fetch_library(cloud, account);
		const library = remote?.library ?? empty_library;
		if (name === "seed_home_allowance" && library.tools.some((entry) => entry.document.id === document.id)) { return content({ saved: true, already_exists: true, id: document.id }); }
		const next = id ? delete_tool(library, id, Date.now()) : upsert_tool(library, document, Date.now());
		if (await push_library(cloud, account, next, remote)) { return content({ saved: true, id: id ?? document.id, device_setup_required: Boolean(document.home_allowance), phone_sync: "Open Pocketwork on your iPhone to apply changes." }); }
	}
	throw new Error("Another device is saving. Retry this tool call.");
}
