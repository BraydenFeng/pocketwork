import { native_format_four } from "./release-flags";
import { z } from "zod";
import { behavior_catalog } from "./behaviors";
import { document_schema } from "./document";
import { empty_library, upsert_tool, delete_tool } from "./library";
import { fetch_library, push_library, type Account, type Cloud } from "./cloud";
import { compile_graph, graph_from_document, graph_schema, node_catalog } from "./logic-graph";
import { personal_routine } from "./personal-routine";
import { fetch_status, render_history_png, summarize_status } from "./status";

const object = { type: "object", properties: {}, additionalProperties: false };
export const mcp_tools = [
	{ name: "get_routine_graph", description: "Read a routine as connected native-capability nodes, with its current document for safe editing.", inputSchema: { type: "object", properties: { id: { type: "string" } }, required: ["id"], additionalProperties: false }, annotations: { readOnlyHint: true } },
	{ name: "save_routine_graph", description: "Validate and apply connected logic to a routine. Supply the unmodified base_document from get_routine_graph to prevent overwriting newer edits. Node positions are temporary; executable connections sync to iPhone. Supports the native capabilities from get_capabilities, not arbitrary code.", inputSchema: { type: "object", properties: { base_document: { type: "object" }, graph: z.toJSONSchema(graph_schema) }, required: ["base_document", "graph"], additionalProperties: false }, annotations: { destructiveHint: false, idempotentHint: true } },
	{ name: "get_status", description: "What the phone last reported: running session, home allowance minutes left today, which routines are switched on, and a 30-day history. Requires Share status to be on in the iPhone app. Minute counts only; never app identities.", inputSchema: object, annotations: { readOnlyHint: true } },
	{ name: "render_status_chart", description: "A PNG bar chart of the last 14 days (allowance minutes used against budget, or focus minutes), with the same status summary as text.", inputSchema: object, annotations: { readOnlyHint: true } },
	{ name: "list_routines", description: "Read your saved routine library. App selections and home coordinates stay on the phone.", inputSchema: object, annotations: { readOnlyHint: true } },
	{ name: "get_capabilities", description: "Read routine format and enforcement limits before designing a routine.", inputSchema: object, annotations: { readOnlyHint: true } },
	{ name: "save_routine", description: "Create or update a validated routine in this account. Requires a supplied routine document. Never executes code.", inputSchema: { type: "object", properties: { document: { type: "object" } }, required: ["document"], additionalProperties: false }, annotations: { destructiveHint: false, idempotentHint: true } },
	{ name: "delete_routine", description: "Delete a routine from this account and remember the deletion for other devices.", inputSchema: { type: "object", properties: { id: { type: "string" } }, required: ["id"], additionalProperties: false }, annotations: { destructiveHint: true, idempotentHint: true } },
	{ name: "seed_home_allowance", description: "Add the requested home-only distraction routine if absent. Never overwrites later edits. Phone setup is required before activation.", inputSchema: object, annotations: { destructiveHint: false, idempotentHint: true } },
];
function content(value: unknown) { return { content: [{ type: "text", text: JSON.stringify(value) }] }; }
export async function call_mcp_tool(cloud: Cloud, account: Account, name: string, args: unknown) {
	if (name === "get_status" || name === "render_status_chart") {
		const found = await fetch_status(cloud, account);
		if (!found) { return { content: [{ type: "text", text: "The phone has not shared any status. In Pocketwork on iPhone, open Account & sync and switch on Share status with your agents, then open the app once." }] }; }
		const summary = summarize_status(found.status, Date.now());
		if (name === "get_status") { return { content: [{ type: "text", text: summary }, { type: "text", text: JSON.stringify(found.status) }] }; }
		const chart = render_history_png(found.status);
		return { content: [{ type: "text", text: `${summary} ${chart.caption}` }, { type: "image", data: chart.png.toString("base64"), mimeType: "image/png" }] };
	}
	if (name === "get_capabilities") { return content({ model: "Pages hold routines (actions) and data (values, entries, displays). API routine names are kept for compatibility. Three free pages at a time; MCP and sync are free. Existing pages stay usable after cancellation.", native_format_four, graph_schema: z.toJSONSchema(graph_schema), graph_nodes: node_catalog, behaviors: behavior_catalog, execution: "Format-3 behaviors require their phone update and run while the routine is open. Format-4 primitives (general timers, variable change actions, independent time windows, records and connected targets) are local web drafts only; cloud save tools reject them until compatible native support ships. Existing Screen Time enforcement remains background capable. Browser Preview simulates events. Progress is device-local; no AI API is used.", document_schema: z.toJSONSchema(document_schema, { unrepresentable: "any" }), home_allowance: "One home allowance per phone, daily shared windows, home-only whole-minute usage checkpoints; a final partial minute may be lost at departure. Home geofence is 150 m and OS callbacks may be delayed. Phone setup/permissions required. Cloud changes apply when the phone app opens." }); }
	if (name === "get_routine_graph") {
		const { id } = z.object({ id: z.string() }).strict().parse(args);
		const document = (await fetch_library(cloud, account))?.library.tools.find((entry) => entry.document.id === id)?.document;
		if (!document) { throw new Error("Routine not found in this account."); }
		return content({ base_document: document, graph: graph_from_document(document) });
	}
	if (name === "save_routine_graph") {
		const { base_document, graph } = z.object({ base_document: document_schema, graph: graph_schema }).strict().parse(args);
		const updated = compile_graph(base_document, graph);
		if (updated.schema_version === 4 && !native_format_four) { throw new Error("Format-4 building blocks are currently local web drafts. Do not sync them until the compatible native update is released."); }
		for (let attempt = 0; attempt < 5; attempt++) {
			const remote = await fetch_library(cloud, account);
			const current = remote?.library.tools.find((entry) => entry.document.id === base_document.id)?.document;
			if (!current) { throw new Error("Routine not found in this account."); }
			const current_json = JSON.stringify(document_schema.parse(current));
			if (current_json === JSON.stringify(updated)) { return content({ saved: true, id: updated.id }); }
			if (current_json !== JSON.stringify(base_document)) { throw new Error("Routine changed. Read its current graph before applying changes."); }
			if (await push_library(cloud, account, upsert_tool(remote!.library, updated, Date.now()), remote)) { return content({ saved: true, id: updated.id, phone_sync: "Open Pocketwork on your iPhone to apply changes." }); }
		}
		throw new Error("Another device is saving. Retry this tool call.");
	}
	if (name === "list_routines") { return content((await fetch_library(cloud, account))?.library ?? empty_library); }
	if (!["save_routine", "delete_routine", "seed_home_allowance"].includes(name)) { throw new Error("Unknown routine tool."); }
	const id = name === "delete_routine" ? z.object({ id: z.string().regex(/^[a-zA-Z0-9_-]{1,64}$/) }).strict().parse(args).id : null;
	const document = name === "save_routine" ? z.object({ document: document_schema }).strict().parse(args).document : personal_routine;
	if (!id && document.schema_version === 4 && !native_format_four) { throw new Error("Format-4 building blocks are currently local web drafts. Do not sync them until the compatible native update is released."); }
	for (let attempt = 0; attempt < 5; attempt++) {
		const remote = await fetch_library(cloud, account);
		const library = remote?.library ?? empty_library;
		if (name === "seed_home_allowance" && library.tools.some((entry) => entry.document.id === document.id)) { return content({ saved: true, already_exists: true, id: document.id }); }
		const next = id ? delete_tool(library, id, Date.now()) : upsert_tool(library, document, Date.now());
		if (await push_library(cloud, account, next, remote)) { return content({ saved: true, id: id ?? document.id, device_setup_required: Boolean(document.home_allowance), phone_sync: "Open Pocketwork on your iPhone to apply changes." }); }
	}
	throw new Error("Another device is saving. Retry this tool call.");
}
