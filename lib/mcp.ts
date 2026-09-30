import { native_format_five, native_format_four } from "./release-flags";
import { z } from "zod";
import { creation_catalog, type CreationKind } from "./creation";
import { empty_library, upsert_tool, delete_tool, find_tool, type Library } from "./library";
import { fetch_library, push_library, type Account, type Cloud } from "./cloud";
import { add_actual_block, block_catalog, page_snapshot, remove_actual_block, update_actual_block, type BlockInputs } from "./page-blocks";
import { fetch_status, render_history_png, summarize_status } from "./status";
import { blank_tool } from "./templates";

const object = { type: "object", properties: {}, additionalProperties: false };
const identifier_schema = z.string().regex(/^[a-zA-Z0-9_-]{1,64}$/);
const creation_kind_schema = z.enum(creation_catalog.map(entry => entry.kind) as [CreationKind, ...CreationKind[]]);
const settings_schema = z.record(z.string(), z.unknown());
const source_schema = z.object({ block_id: identifier_schema, output: identifier_schema }).strict();
const inputs_schema = z.record(z.string(), z.union([source_schema, z.null()]));
const page_id_schema = z.object({ page_id: identifier_schema }).strict();
const create_page_schema = z.object({ id: identifier_schema.optional(), name: z.string().trim().min(1).max(80), description: z.string().max(500).optional() }).strict();
const update_page_schema = z.object({ page_id: identifier_schema, name: z.string().trim().min(1).max(80).optional(), description: z.string().max(500).optional() }).strict().refine(value => value.name !== undefined || value.description !== undefined, "Give at least one page field to update.");
const add_block_schema = z.object({ page_id: identifier_schema, kind: creation_kind_schema, name: z.string().trim().min(1).max(80).optional(), settings: settings_schema.optional(), inputs: inputs_schema.optional(), before_block_id: identifier_schema.optional() }).strict();
const update_block_schema = z.object({ page_id: identifier_schema, block_id: identifier_schema, name: z.string().trim().min(1).max(80).optional(), settings: settings_schema.optional(), inputs: inputs_schema.optional() }).strict().refine(value => value.name !== undefined || value.settings !== undefined || value.inputs !== undefined, "Give at least one block field to update.");
const remove_block_schema = z.object({ page_id: identifier_schema, block_id: identifier_schema }).strict();

export const mcp_tools = [
	{ name: "get_block_catalog", description: "List the exact Page, Routine, and Data blocks available in Pocketwork, including each block's settings, inputs, and outputs.", inputSchema: object, annotations: { readOnlyHint: true } },
	{ name: "list_pages", description: "List this account's Pocketwork pages.", inputSchema: object, annotations: { readOnlyHint: true } },
	{ name: "get_page", description: "Read one page as the same Page, Routine, and Data blocks shown in the visual builder.", inputSchema: z.toJSONSchema(page_id_schema), annotations: { readOnlyHint: true } },
	{ name: "create_page", description: "Create a blank Pocketwork page. Add functionality with add_block using kinds from get_block_catalog.", inputSchema: z.toJSONSchema(create_page_schema), annotations: { destructiveHint: false, idempotentHint: false } },
	{ name: "update_page", description: "Rename a page or change its description.", inputSchema: z.toJSONSchema(update_page_schema), annotations: { destructiveHint: false, idempotentHint: true } },
	{ name: "add_block", description: "Add one of Pocketwork's actual visual-builder blocks to a page and connect its named inputs to earlier block outputs.", inputSchema: z.toJSONSchema(add_block_schema), annotations: { destructiveHint: false, idempotentHint: false } },
	{ name: "update_block", description: "Change an actual block's name, settings, or named input connections.", inputSchema: z.toJSONSchema(update_block_schema), annotations: { destructiveHint: false, idempotentHint: true } },
	{ name: "remove_block", description: "Remove an actual block and its connections from a page.", inputSchema: z.toJSONSchema(remove_block_schema), annotations: { destructiveHint: true, idempotentHint: true } },
	{ name: "delete_page", description: "Delete a page from this account and remember the deletion for other devices.", inputSchema: z.toJSONSchema(page_id_schema), annotations: { destructiveHint: true, idempotentHint: true } },
	{ name: "get_status", description: "What the phone last reported: running session, home allowance minutes left today, which routines are switched on, and a 30-day history. Requires Share status to be on in the iPhone app. Minute counts only; never app identities.", inputSchema: object, annotations: { readOnlyHint: true } },
	{ name: "render_status_chart", description: "A PNG bar chart of the last 14 days (allowance minutes used against budget, or focus minutes), with the same status summary as text.", inputSchema: object, annotations: { readOnlyHint: true } },
];
function content(value: unknown) { return { content: [{ type: "text", text: JSON.stringify(value) }] }; }

function capabilities() {
	const primitives = native_format_four
		? "These blocks can sync to a compatible updated iPhone. Connected logic runs while its page is open. Timers track elapsed time while away, but completion actions run on reopening."
		: "Routine and Data blocks are local web drafts only; cloud writes reject them until the compatible phone update is rolled out.";
	const blocks = block_catalog().filter(block => block.kind !== "interval" || native_format_five).map(block => !native_format_five && block.kind === "add_allowance"
		? { ...block, inputs: block.inputs.filter(input => input.input !== "minutes") }
		: !native_format_five && block.kind === "app_usage"
			? { ...block, outputs: block.outputs.filter(output => output.output !== "history") }
			: block);
	return {
		model: "Pages contain Page, Routine, and Data blocks. Agents use the same block catalog and editing operations as the visual builder.",
		native_format_four,
		native_format_five,
		blocks,
		execution: `${primitives} Native focus, schedule, and home-allowance pages have separate background support. Browser Preview simulates events. Progress is device-local; no AI API is used.`,
		limits: "Three free pages at a time. MCP and sync are free. Existing pages stay usable after cancellation.",
		phone: "App selections and saved locations stay on the phone. Cloud changes apply when the phone app opens.",
	};
}

function list_pages(library: Library) {
	return library.tools.map(entry => ({
		id: entry.document.id,
		name: entry.document.name,
		description: entry.document.description,
		updated_at: entry.updated_at,
		block_counts: Object.fromEntries(Object.entries(page_snapshot(entry.document).sections).map(([section, blocks]) => [section, blocks.length])),
	}));
}

function require_page(library: Library, page_id: string) {
	const page = find_tool(library, page_id);
	if (!page) { throw new Error("Page not found in this account."); }
	return page;
}

function assert_syncable(document: ReturnType<typeof blank_tool>) {
	if (document.schema_version === 5 && !native_format_five) {
		throw new Error("This page uses newer blocks that are currently a local web draft. Do not sync it until the compatible native update is released.");
	}
	if (document.schema_version === 4 && !native_format_four) {
		throw new Error("Routine and Data blocks are currently local web drafts. Do not sync them until the compatible native update is released.");
	}
}

async function read_library(cloud: Cloud, account: Account): Promise<Library> {
	try { return (await fetch_library(cloud, account))?.library ?? empty_library; }
	catch (failure) { throw new Error(`Could not read this account's pages. ${failure instanceof Error ? failure.message : "Cloud read failed."}`); }
}

async function mutate_library<Result>(cloud: Cloud, account: Account, change: (library: Library) => { library: Library; result: Result }): Promise<Result> {
	for (let attempt = 0; attempt < 5; attempt++) {
		let remote;
		try { remote = await fetch_library(cloud, account); }
		catch (failure) { throw new Error(`Could not read this account before saving. ${failure instanceof Error ? failure.message : "Cloud read failed."}`); }
		const changed = change(remote?.library ?? empty_library);
		try {
			if (await push_library(cloud, account, changed.library, remote)) { return changed.result; }
		}
		catch (failure) { throw new Error(`Could not save this account's pages. ${failure instanceof Error ? failure.message : "Cloud save failed."}`); }
	}
	throw new Error("Another device is saving. Retry this tool call.");
}

export async function call_mcp_tool(cloud: Cloud, account: Account, name: string, args: unknown) {
	if (name === "get_status" || name === "render_status_chart") {
		let found;
		try { found = await fetch_status(cloud, account); }
		catch (failure) { throw new Error(`Could not read phone status. ${failure instanceof Error ? failure.message : "Status read failed."}`); }
		if (!found) { return { content: [{ type: "text", text: "The phone has not shared any status. In Pocketwork on iPhone, open Account & sync and switch on Share status with your agents, then open the app once." }] }; }
		const summary = summarize_status(found.status, Date.now());
		if (name === "get_status") { return { content: [{ type: "text", text: summary }, { type: "text", text: JSON.stringify(found.status) }] }; }
		const chart = render_history_png(found.status);
		return { content: [{ type: "text", text: `${summary} ${chart.caption}` }, { type: "image", data: chart.png.toString("base64"), mimeType: "image/png" }] };
	}
	if (name === "get_block_catalog" || name === "get_capabilities") { return content(capabilities()); }
	if (name === "list_pages" || name === "list_routines") { return content({ pages: list_pages(await read_library(cloud, account)) }); }
	if (name === "get_page" || name === "get_routine_graph") {
		const page_id = name === "get_page" ? page_id_schema.parse(args).page_id : z.object({ id: identifier_schema }).strict().parse(args).id;
		return content(page_snapshot(require_page(await read_library(cloud, account), page_id)));
	}
	if (name === "create_page") {
		const input = create_page_schema.parse(args);
		const blank = blank_tool();
		const page = { ...blank, id: input.id ?? blank.id, name: input.name, description: input.description ?? "" };
		const snapshot = await mutate_library(cloud, account, library => {
			if (find_tool(library, page.id)) { throw new Error("A page with that ID already exists."); }
			return { library: upsert_tool(library, page, Date.now()), result: page_snapshot(page) };
		});
		return content({ saved: true, page: snapshot, phone_sync: "Open Pocketwork on your iPhone to apply changes." });
	}
	if (name === "update_page") {
		const input = update_page_schema.parse(args);
		const snapshot = await mutate_library(cloud, account, library => {
			const current = require_page(library, input.page_id);
			const page = { ...current, name: input.name ?? current.name, description: input.description ?? current.description };
			return { library: upsert_tool(library, page, Date.now()), result: page_snapshot(page) };
		});
		return content({ saved: true, page: snapshot, phone_sync: "Open Pocketwork on your iPhone to apply changes." });
	}
	if (name === "add_block") {
		const input = add_block_schema.parse(args);
		if (input.kind === "interval" && !native_format_five) { throw new Error("The Every block is not available to agents until its compatible phone update is released."); }
		const result = await mutate_library(cloud, account, library => {
			const current = require_page(library, input.page_id);
			const added = add_actual_block(current, input.kind, { name: input.name, settings: input.settings, inputs: input.inputs as BlockInputs | undefined, before_block_id: input.before_block_id });
			assert_syncable(added.document);
			return { library: upsert_tool(library, added.document, Date.now()), result: { block_id: added.block_id, page: page_snapshot(added.document) } };
		});
		return content({ saved: true, ...result, phone_sync: "Open Pocketwork on your iPhone to apply changes." });
	}
	if (name === "update_block") {
		const input = update_block_schema.parse(args);
		const snapshot = await mutate_library(cloud, account, library => {
			const current = require_page(library, input.page_id);
			const page = update_actual_block(current, input.block_id, { name: input.name, settings: input.settings, inputs: input.inputs as BlockInputs | undefined });
			assert_syncable(page);
			return { library: upsert_tool(library, page, Date.now()), result: page_snapshot(page) };
		});
		return content({ saved: true, page: snapshot, phone_sync: "Open Pocketwork on your iPhone to apply changes." });
	}
	if (name === "remove_block") {
		const input = remove_block_schema.parse(args);
		const snapshot = await mutate_library(cloud, account, library => {
			const current = require_page(library, input.page_id);
			const page = remove_actual_block(current, input.block_id);
			assert_syncable(page);
			return { library: upsert_tool(library, page, Date.now()), result: page_snapshot(page) };
		});
		return content({ saved: true, page: snapshot, phone_sync: "Open Pocketwork on your iPhone to apply changes." });
	}
	if (name === "delete_page" || name === "delete_routine") {
		const page_id = name === "delete_page" ? page_id_schema.parse(args).page_id : z.object({ id: identifier_schema }).strict().parse(args).id;
		await mutate_library(cloud, account, library => ({ library: delete_tool(library, page_id, Date.now()), result: null }));
		return content({ saved: true, page_id });
	}
	if (["save_routine", "save_routine_graph", "seed_home_allowance"].includes(name)) {
		throw new Error("That MCP tool was retired. Use create_page, add_block, and update_block so the agent edits the same blocks as the visual builder.");
	}
	throw new Error("Unknown Pocketwork tool.");
}
