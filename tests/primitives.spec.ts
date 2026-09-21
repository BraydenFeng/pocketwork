import { expect, test, type Page } from "@playwright/test";
import { behavior_config_schema, type BehaviorKind, type BehaviorConfig } from "../lib/behaviors";
import { compile_graph, type LogicGraph } from "../lib/logic-graph";
import { blank_tool } from "../lib/templates";
import { seed_library } from "./helpers";

async function add_block(page: Page, title: string) {
	await page.getByRole("button", { name: "Add a block", exact: true }).click();
	await page.getByRole("dialog").getByRole("button", { name: `Add ${title}`, exact: true }).click();
}
async function name_block(page: Page, current: string, name: string) {
	await page.getByLabel(`Name for ${current}`, { exact: true }).fill(name);
	await page.getByLabel(`Name for ${current}`, { exact: true }).press("Tab");
}
async function save(page: Page) { await page.getByRole("button", { name: "Save connections", exact: true }).click(); }
function node(id: string, kind: BehaviorKind, config: Partial<BehaviorConfig> = {}) { return { id, kind, x: 0, y: 0, config: behavior_config_schema.parse({ label: id, ...config }) }; }

test("users build their own allowance with a variable and an add action", async ({ page }) => {
	await page.goto("/"); await page.getByRole("button", { name: "New page", exact: true }).click();
	await add_block(page, "Variable"); await name_block(page, "Variable", "Allowance");
	await page.getByLabel("Starting value", { exact: true }).fill("30"); await page.getByLabel("Starting value", { exact: true }).press("Tab");
	await page.getByLabel("Variable unit", { exact: true }).fill("minutes"); await page.getByLabel("Variable unit", { exact: true }).press("Tab"); await save(page);
	await add_block(page, "Button"); await name_block(page, "Button", "Workout done"); await save(page);
	await add_block(page, "Change variable"); await name_block(page, "Change variable", "Earn minutes");
	await expect(page.getByLabel("Variable to change")).not.toHaveValue("");
	await page.getByLabel("Variable action").selectOption("add");
	await page.getByLabel("Amount", { exact: true }).fill("15"); await page.getByLabel("Amount", { exact: true }).press("Tab");
	await expect(page.getByLabel("When: Earn minutes", { exact: true })).not.toHaveValue("");
	await page.screenshot({ path: "test-results/primitive-action-desktop.png", fullPage: true }); await save(page);
	await expect(page.getByText("Saved here · local-only blocks", { exact: true })).toBeVisible();
	await page.reload(); await page.getByRole("button", { name: "Preview", exact: true }).click();
	await expect(page.getByLabel("Allowance value", { exact: true })).toHaveText("30 minutes");
	await page.getByRole("button", { name: "Workout done", exact: true }).click();
	await expect(page.getByLabel("Allowance value", { exact: true })).toHaveText("45 minutes");
	await page.getByRole("button", { name: "Workout done", exact: true }).click();
	await expect(page.getByLabel("Allowance value", { exact: true })).toHaveText("60 minutes");
	const document = await page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document);
	expect(document.schema_version).toBe(4); expect(document.behaviors.nodes.some((node: { kind: string }) => node.kind === "add_allowance")).toBe(false);
});

test("a general timer has no automatic blocker and supports countdown and count-up controls", async ({ page }) => {
	await page.goto("/"); await page.getByRole("button", { name: "New page", exact: true }).click();
	await add_block(page, "Timer");
	await page.getByLabel("Duration", { exact: true }).fill("2.5"); await page.getByLabel("Duration", { exact: true }).press("Tab");
	await save(page); await page.getByRole("button", { name: "Preview", exact: true }).click();
	await expect(page.getByLabel("Timer time")).toHaveText("2:30");
	await page.getByRole("button", { name: "Start Timer", exact: true }).click();
	await page.getByText("Simulate time, location, and app usage", { exact: true }).click();
	await page.getByRole("button", { name: "Advance 5 minutes", exact: true }).click();
	await expect(page.getByLabel("Timer time")).toHaveText("0:00");
	await expect(page.getByText("Finished · counting down", { exact: true })).toBeVisible();
	await page.getByRole("button", { name: "Back to editing", exact: true }).click();
	await page.locator(".connected-page-block").getByRole("button", { name: "Configure" }).click();
	await page.getByLabel("Timer mode").selectOption("stopwatch"); await save(page);
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await page.getByRole("button", { name: "Start Timer", exact: true }).click();
	await page.getByText("Simulate time, location, and app usage", { exact: true }).click();
	await page.getByRole("button", { name: "Advance 5 minutes", exact: true }).click();
	await page.getByRole("button", { name: "Stop Timer", exact: true }).click();
	await expect(page.getByText("Finished · counting up", { exact: true })).toBeVisible();
	const document = await page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document);
	expect(document.blocks.map((block: { type: string }) => block.type)).toEqual(["note"]); expect(document.rules.block_during_focus).toBe(false);
});

test("timer, saved record, chart, and allowance share values without a manual form", async ({ page }) => {
	const graph: LogicGraph = {
		nodes: [node("Workout", "elapsed_timer", { timer_mode: "stopwatch" }), node("Allowance", "variable", { value: 30, unit: "minutes" }), node("Reward", "change_value", { variable_id: "Allowance", change: "add" }), node("Session", "record"), node("History", "save_entry"), node("Chart", "chart")],
		connections: [
			{ from: "Workout", output: "finished", to: "Reward", input: "when" }, { from: "Workout", output: "elapsed", to: "Reward", input: "amount" },
			{ from: "Workout", output: "elapsed", to: "Session", input: "value" }, { from: "Session", output: "record", to: "History", input: "record" },
			{ from: "Workout", output: "finished", to: "History", input: "save" }, { from: "History", output: "rows", to: "Chart", input: "rows" },
		],
	};
	const document = compile_graph(blank_tool(), graph); await seed_library(page, [document]); await page.goto(`/?routine=${document.id}`);
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await page.getByRole("button", { name: "Start Workout", exact: true }).click();
	await page.getByText("Simulate time, location, and app usage", { exact: true }).click();
	await page.getByRole("button", { name: "Advance 5 minutes", exact: true }).click();
	await page.getByRole("button", { name: "Stop Workout", exact: true }).click();
	await expect(page.getByText("Chart · 1 entry", { exact: true })).toBeVisible();
	await expect(page.locator(".builder-data circle")).toHaveCount(1);
	await expect(page.getByLabel("Allowance value")).toContainText("35");
	await page.getByText("Simulate time, location, and app usage", { exact: true }).click();
	expect(await page.locator("main").ariaSnapshot()).toContain("Start Workout");
	for (const width of [1440, 768, 375]) {
		await page.setViewportSize({ width, height: 1000 });
		expect(await page.evaluate(() => window.document.documentElement.scrollWidth <= innerWidth)).toBe(true);
		await page.screenshot({ path: `test-results/primitive-preview-${width}.png`, fullPage: true });
	}
	await page.getByRole("button", { name: "Back to editing", exact: true }).click();
	await page.getByRole("tab", { name: "Routines", exact: true }).click();
	await page.getByRole("button", { name: "Configure Reward", exact: true }).click();
	await expect(page.getByLabel("Amount from (optional): Reward", { exact: true })).not.toHaveValue("");
	await page.screenshot({ path: "test-results/primitive-action-375.png", fullPage: true });
});

test("a change action cannot be saved without a variable and trigger", async ({ page }) => {
	await page.goto("/"); await page.getByRole("button", { name: "New page", exact: true }).click();
	await add_block(page, "Change variable");
	await expect(page.getByRole("button", { name: "Save connections", exact: true })).toBeDisabled();
	await expect(page.getByLabel("Variable to change")).toHaveValue("");
	await page.screenshot({ path: "test-results/primitive-missing-source.png", fullPage: true });
});
