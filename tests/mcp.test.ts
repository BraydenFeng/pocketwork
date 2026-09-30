import { beforeEach, expect, it, vi } from "vitest";
import { fetch_library, push_library, type Cloud, type CloudSnapshot } from "../lib/cloud";
import { empty_library, type Library } from "../lib/library";
import { requested_home_policy } from "../lib/home-policy";
import { call_mcp_tool, mcp_tools } from "../lib/mcp";
import { personal_routine } from "../lib/personal-routine";
import * as release_flags from "../lib/release-flags";

vi.mock("../lib/cloud", () => ({ fetch_library: vi.fn(), push_library: vi.fn() }));
vi.mock("../lib/release-flags", () => ({ native_format_four: false, native_format_five: false }));

const cloud = {} as Cloud;
const account = { id: "owner", email: "test@example.com" };

function parsed(result: Awaited<ReturnType<typeof call_mcp_tool>>) {
	return JSON.parse(result.content[0].text!);
}

function use_memory_cloud(initial: Library | null = null) {
	let snapshot: CloudSnapshot | null = initial ? { library: initial, updated_at: "initial" } : null;
	vi.mocked(fetch_library).mockImplementation(async () => snapshot);
	vi.mocked(push_library).mockImplementation(async (_cloud, who, library) => {
		expect(who).toEqual(account);
		snapshot = { library, updated_at: `revision-${Date.now()}` };
		return true;
	});
	return () => snapshot?.library ?? empty_library;
}

beforeEach(() => {
	vi.resetAllMocks();
	vi.spyOn(release_flags, "native_format_four", "get").mockReturnValue(false);
	vi.spyOn(release_flags, "native_format_five", "get").mockReturnValue(false);
});

it("advertises Every only after the format-5 phone rollout", async () => {
	vi.spyOn(release_flags, "native_format_four", "get").mockReturnValue(true);
	let catalog = parsed(await call_mcp_tool(cloud, account, "get_block_catalog", {}));
	expect(catalog.native_format_five).toBe(false);
	expect(catalog.blocks.some((block: { kind: string }) => block.kind === "interval")).toBe(false);
	vi.spyOn(release_flags, "native_format_five", "get").mockReturnValue(true);
	catalog = parsed(await call_mcp_tool(cloud, account, "get_block_catalog", {}));
	expect(catalog.blocks).toEqual(expect.arrayContaining([expect.objectContaining({ kind: "interval", name: "Every", settings: ["value", "interval_unit"], outputs: [expect.objectContaining({ output: "due", label: "every interval" })] })]));
	expect(catalog.blocks.find((block: { kind: string }) => block.kind === "add_allowance").inputs).toEqual(expect.arrayContaining([expect.objectContaining({ input: "minutes" })]));
	expect(catalog.blocks.find((block: { kind: string }) => block.kind === "app_usage").outputs).toEqual(expect.arrayContaining([expect.objectContaining({ output: "history" })]));
});

it("creates an Every block through the shared MCP model once format 5 is available", async () => {
	vi.spyOn(release_flags, "native_format_four", "get").mockReturnValue(true);
	const library = use_memory_cloud();
	await call_mcp_tool(cloud, account, "create_page", { id: "hourly", name: "Hourly" });
	await expect(call_mcp_tool(cloud, account, "add_block", { page_id: "hourly", kind: "interval" })).rejects.toThrow("phone update");
	vi.spyOn(release_flags, "native_format_five", "get").mockReturnValue(true);
	const every = parsed(await call_mcp_tool(cloud, account, "add_block", { page_id: "hourly", kind: "interval", settings: { value: 1, interval_unit: "hours" } }));
	await call_mcp_tool(cloud, account, "add_block", { page_id: "hourly", kind: "reminder", settings: { message: "One hour passed." }, inputs: { send: { block_id: every.block_id, output: "due" } } });
	expect(library().tools[0].document.schema_version).toBe(5);
	expect(library().tools[0].document.behaviors?.connections).toContainEqual(expect.objectContaining({ from: every.block_id, output: "due", input: "send" }));
});

it("builds calculated Screen Time rewards and a usage chart through public MCP blocks", async () => {
	vi.spyOn(release_flags, "native_format_four", "get").mockReturnValue(true);
	vi.spyOn(release_flags, "native_format_five", "get").mockReturnValue(true);
	const library = use_memory_cloud({ schema_version: 1, tools: [{ document: personal_routine, updated_at: "2026-09-29T00:00:00.000Z" }] });
	const add = async (kind: string, options: Record<string, unknown> = {}) => parsed(await call_mcp_tool(cloud, account, "add_block", { page_id: personal_routine.id, kind, ...options }));
	const steps = await add("health", { name: "Today's steps", settings: { metric: "steps" } });
	const step_size = await add("number_input", { name: "Steps per reward", settings: { value: 3000 } });
	const groups = await add("calculate", { name: "Step groups", settings: { operation: "divide" }, inputs: { a: { block_id: steps.block_id, output: "value" }, b: { block_id: step_size.block_id, output: "value" } } });
	const whole_groups = await add("calculate", { name: "Whole step groups", settings: { operation: "floor" }, inputs: { a: { block_id: groups.block_id, output: "value" } } });
	const reward_size = await add("number_input", { name: "Minutes per reward", settings: { value: 40 } });
	const reward_minutes = await add("calculate", { name: "Earned minutes", settings: { operation: "multiply" }, inputs: { a: { block_id: whole_groups.block_id, output: "value" }, b: { block_id: reward_size.block_id, output: "value" } } });
	const weekend = await add("time_window", { name: "Weekend", settings: { days: [1, 7], time: "00:00", end_time: "23:59" } });
	await add("add_allowance", { name: "Add earned weekend time", inputs: { grant: { block_id: weekend.block_id, output: "active" }, minutes: { block_id: reward_minutes.block_id, output: "value" } } });
	const usage = await add("app_usage", { name: "Distraction time" });
	await add("chart", { name: "Distraction time over time", settings: { field: "minutes" }, inputs: { rows: { block_id: usage.block_id, output: "history" } } });
	const document = library().tools[0].document;
	expect(document.schema_version).toBe(5);
	expect(document.behaviors?.connections).toEqual(expect.arrayContaining([
		expect.objectContaining({ from: reward_minutes.block_id, output: "value", input: "minutes" }),
		expect.objectContaining({ from: usage.block_id, output: "history", input: "rows" }),
	]));
});

it("advertises block operations instead of raw graphs, documents, or presets", () => {
	const names = mcp_tools.map(tool => tool.name);
	expect(names).toEqual(expect.arrayContaining(["get_block_catalog", "list_pages", "get_page", "create_page", "add_block", "update_block", "remove_block", "delete_page"]));
	expect(names).not.toEqual(expect.arrayContaining(["get_routine_graph", "save_routine_graph", "save_routine", "seed_home_allowance"]));
});

it.each([false, true])("reports the actual block rollout flag (%s)", async enabled => {
	vi.spyOn(release_flags, "native_format_four", "get").mockReturnValue(enabled);
	const catalog = parsed(await call_mcp_tool(cloud, account, "get_block_catalog", {}));
	expect(catalog.native_format_four).toBe(enabled);
	expect(catalog.execution).toContain(enabled ? "completion actions run on reopening" : "cloud writes reject them");
	expect(catalog.blocks).toEqual(expect.arrayContaining([
		expect.objectContaining({ kind: "branch", name: "If", description: "Run when a condition is true", settings: ["else_enabled"], outputs: expect.arrayContaining([expect.objectContaining({ output: "no", label: "else", optional: true })]) }),
	]));
	expect(fetch_library).not.toHaveBeenCalled();
});

it("creates pages and builds real connected blocks from the shared catalog", async () => {
	vi.spyOn(release_flags, "native_format_four", "get").mockReturnValue(true);
	const library = use_memory_cloud();
	await call_mcp_tool(cloud, account, "create_page", { id: "gym-page", name: "Gym rewards", description: "Earn free time at the gym." });
	const toggle = parsed(await call_mcp_tool(cloud, account, "add_block", { page_id: "gym-page", kind: "checkbox", name: "Gym mode" }));
	const branch = parsed(await call_mcp_tool(cloud, account, "add_block", { page_id: "gym-page", kind: "branch", name: "If gym mode is on", inputs: { condition: { block_id: toggle.block_id, output: "checked" } } }));
	const initial_branch = branch.page.sections.routines.find((block: { id: string }) => block.id === branch.block_id);
	expect(initial_branch.outputs.map((output: { output: string }) => output.output)).toEqual(["yes"]);
	const enabled = parsed(await call_mcp_tool(cloud, account, "update_block", { page_id: "gym-page", block_id: branch.block_id, settings: { else_enabled: true } }));
	const enabled_branch = enabled.page.sections.routines.find((block: { id: string }) => block.id === branch.block_id);
	expect(enabled_branch.outputs.map((output: { output: string }) => output.output)).toEqual(["yes", "no"]);
	const disabled = parsed(await call_mcp_tool(cloud, account, "update_block", { page_id: "gym-page", block_id: branch.block_id, settings: { else_enabled: false } }));
	const disabled_branch = disabled.page.sections.routines.find((block: { id: string }) => block.id === branch.block_id);
	expect(disabled_branch.outputs.map((output: { output: string }) => output.output)).toEqual(["yes"]);
	await call_mcp_tool(cloud, account, "update_block", { page_id: "gym-page", block_id: branch.block_id, settings: { else_enabled: true } });
	await call_mcp_tool(cloud, account, "add_block", { page_id: "gym-page", kind: "reminder", name: "Celebrate", settings: { message: "Gym time counted." }, inputs: { send: { block_id: branch.block_id, output: "yes" } } });
	await call_mcp_tool(cloud, account, "add_block", { page_id: "gym-page", kind: "reminder", name: "Try again", settings: { message: "Gym mode is off." }, inputs: { send: { block_id: branch.block_id, output: "no" } } });
	const page = parsed(await call_mcp_tool(cloud, account, "get_page", { page_id: "gym-page" }));
	expect(page.sections.routines).toEqual(expect.arrayContaining([
		expect.objectContaining({ id: branch.block_id, kind: "branch", inputs: { condition: expect.objectContaining({ source: { block_id: toggle.block_id, output: "checked" } }) } }),
	]));
	expect(library().tools[0].document.behaviors?.connections).toEqual(expect.arrayContaining([
		expect.objectContaining({ from: toggle.block_id, output: "checked", to: branch.block_id, input: "condition" }),
		expect.objectContaining({ from: branch.block_id, output: "no", input: "send" }),
	]));
	await expect(call_mcp_tool(cloud, account, "update_block", { page_id: "gym-page", block_id: branch.block_id, settings: { else_enabled: false } })).rejects.toThrow("Else is still used");
});

it("rebuilds the native home allowance through only public catalog blocks", async () => {
	vi.spyOn(release_flags, "native_format_four", "get").mockReturnValue(true);
	const library = use_memory_cloud({ schema_version: 1, tools: [{ document: personal_routine, updated_at: "2026-09-29T00:00:00.000Z" }] });
	const add = async (kind: string, options: Record<string, unknown> = {}) => parsed(await call_mcp_tool(cloud, account, "add_block", { page_id: personal_routine.id, kind, ...options }));
	const home = await add("location", { name: "At home" });
	const usage = await add("app_usage", { name: "Distraction time" });
	const weekday_early = await add("time_window", { name: "Weekday early window", settings: { days: [2, 3, 4, 5], time: "18:00", end_time: "18:30" } });
	const weekday_late = await add("time_window", { name: "Weekday late window", settings: { days: [2, 3, 4, 5], time: "19:00", end_time: "20:50" } });
	const friday = await add("time_window", { name: "Friday window", settings: { days: [6], time: "14:30", end_time: "20:20" } });
	const weekend = await add("time_window", { name: "Weekend window", settings: { days: [1, 7], time: "06:30", end_time: "20:30" } });
	const weekday_window = await add("or", { name: "Either weekday window", inputs: { a: { block_id: weekday_early.block_id, output: "active" }, b: { block_id: weekday_late.block_id, output: "active" } } });
	const weekday_used = await add("compare", { name: "Used 30 minutes", settings: { operator: "gte", value: 30 }, inputs: { value: { block_id: usage.block_id, output: "minutes" } } });
	const friday_used = await add("compare", { name: "Used 120 minutes", settings: { operator: "gte", value: 120 }, inputs: { value: { block_id: usage.block_id, output: "minutes" } } });
	const weekend_used = await add("compare", { name: "Used 180 minutes", settings: { operator: "gte", value: 180 }, inputs: { value: { block_id: usage.block_id, output: "minutes" } } });
	const weekday_limit = await add("and", { name: "Weekday limit reached", inputs: { a: { block_id: weekday_window.block_id, output: "result" }, b: { block_id: weekday_used.block_id, output: "result" } } });
	const friday_limit = await add("and", { name: "Friday limit reached", inputs: { a: { block_id: friday.block_id, output: "active" }, b: { block_id: friday_used.block_id, output: "result" } } });
	const weekend_limit = await add("and", { name: "Weekend limit reached", inputs: { a: { block_id: weekend.block_id, output: "active" }, b: { block_id: weekend_used.block_id, output: "result" } } });
	const first_limits = await add("or", { name: "Weekday or Friday limit", inputs: { a: { block_id: weekday_limit.block_id, output: "result" }, b: { block_id: friday_limit.block_id, output: "result" } } });
	const all_limits = await add("or", { name: "Any daily limit", inputs: { a: { block_id: first_limits.block_id, output: "result" }, b: { block_id: weekend_limit.block_id, output: "result" } } });
	const home_limit = await add("and", { name: "At home with limit reached", inputs: { a: { block_id: home.block_id, output: "present" }, b: { block_id: all_limits.block_id, output: "result" } } });
	const completed = await add("app_gate", { name: "Block distractions", settings: { groups: ["Distractions"] }, inputs: { closed: { block_id: home_limit.block_id, output: "result" } } });
	const document = library().tools[0].document;
	const routines = completed.page.sections.routines as { kind: string }[];
	expect(document.home_allowance).toEqual(requested_home_policy);
	expect(routines.some(block => block.kind === "home_allowance")).toBe(false);
	expect(routines).toEqual(expect.arrayContaining([expect.objectContaining({ kind: "location" }), expect.objectContaining({ kind: "app_gate" })]));
});

it("updates and removes the same stored blocks", async () => {
	const library = use_memory_cloud();
	await call_mcp_tool(cloud, account, "create_page", { id: "simple-page", name: "Simple" });
	const added = parsed(await call_mcp_tool(cloud, account, "add_block", { page_id: "simple-page", kind: "button", name: "Start" }));
	await call_mcp_tool(cloud, account, "update_block", { page_id: "simple-page", block_id: added.block_id, name: "Begin" });
	expect(library().tools[0].document.behaviors?.nodes[0].config.label).toBe("Begin");
	await call_mcp_tool(cloud, account, "remove_block", { page_id: "simple-page", block_id: added.block_id });
	expect(library().tools[0].document.behaviors).toBeUndefined();
});

it("never publishes newer blocks to an older phone", async () => {
	use_memory_cloud();
	await call_mcp_tool(cloud, account, "create_page", { id: "timer-page", name: "Timer" });
	vi.mocked(push_library).mockClear();
	await expect(call_mcp_tool(cloud, account, "add_block", { page_id: "timer-page", kind: "elapsed_timer" })).rejects.toThrow("local web drafts");
	expect(push_library).not.toHaveBeenCalled();
});

it("retries writes after concurrent cloud saves", async () => {
	vi.mocked(fetch_library).mockResolvedValue(null);
	vi.mocked(push_library).mockResolvedValueOnce(false).mockResolvedValueOnce(true);
	await call_mcp_tool(cloud, account, "create_page", { id: "retry-page", name: "Retry" });
	expect(fetch_library).toHaveBeenCalledTimes(2);
});

it("reads only pages from the authenticated account", async () => {
	vi.mocked(fetch_library).mockResolvedValue(null);
	await expect(call_mcp_tool(cloud, account, "get_page", { page_id: "missing" })).rejects.toThrow("not found");
	expect(fetch_library).toHaveBeenCalledWith(cloud, account);
});

it("rejects retired write formats instead of spawning a private routine", async () => {
	for (const tool of ["save_routine", "save_routine_graph", "seed_home_allowance"]) {
		await expect(call_mcp_tool(cloud, account, tool, {})).rejects.toThrow("retired");
	}
	expect(fetch_library).not.toHaveBeenCalled();
	expect(push_library).not.toHaveBeenCalled();
});
