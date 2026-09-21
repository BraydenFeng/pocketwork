import { expect, test, type Page } from "@playwright/test";
import { starter_document } from "../lib/document";
import { templates } from "../lib/templates";
import { seed_library, STARTER_URL } from "./helpers";

async function add_block(page: Page, title: string) {
	await page.getByRole("button", { name: "Add a block", exact: true }).click();
	await page.getByRole("dialog").getByRole("button", { name: `Add ${title}`, exact: true }).click();
}

test("creates directly on the page, edits numeric values, and keeps changes after reload", async ({ page }) => {
	await page.goto("/"); await page.getByRole("button", { name: "New page", exact: true }).click();
	await expect(page.getByLabel("Page name", { exact: true })).toHaveValue("Untitled page");
	await expect(page.getByRole("complementary", { name: "Inspector" })).toHaveCount(0);
	await page.getByLabel("Page name", { exact: true }).fill("Evening focus");
	await page.getByLabel("Page name", { exact: true }).press("Tab");
	await add_block(page, "App blocker");
	await expect(page.getByLabel("Session length", { exact: true })).toHaveValue("25");
	await page.getByLabel("Session length", { exact: true }).fill("");
	await page.getByLabel("Session length", { exact: true }).press("Tab");
	await expect(page.getByRole("alert").filter({ hasText: "15 to 120" })).toBeVisible();
	await page.getByLabel("Session length", { exact: true }).fill("45");
	await page.getByLabel("Session length", { exact: true }).press("Tab");
	await expect(page.getByText("Saved on this browser", { exact: true })).toBeVisible();
	await page.reload();
	await expect(page.getByLabel("Page name", { exact: true })).toHaveValue("Evening focus");
	await expect(page.getByLabel("Session length", { exact: true })).toHaveValue("45");
});

test("slash picker supports search, keyboard selection, escape, and focus restoration", async ({ page }) => {
	await page.goto("/"); await page.getByRole("button", { name: "New page", exact: true }).click();
	await page.getByLabel("Text: Text", { exact: true }).press("/");
	await expect(page.getByRole("dialog")).toBeVisible();
	await page.getByLabel("Find a block", { exact: true }).fill("checklist");
	await page.getByLabel("Find a block", { exact: true }).press("Enter");
	await expect(page.getByLabel("Task 1: On my list", { exact: true })).toBeVisible();
	await page.getByRole("button", { name: "Add a block", exact: true }).click();
	await page.getByLabel("Find a block", { exact: true }).press("Escape");
	await expect(page.getByRole("dialog")).toHaveCount(0);
	await expect(page.getByRole("button", { name: "Add a block", exact: true })).toBeFocused();
});

test("a form, saved log and chart work together without drawing any wires", async ({ page }) => {
	await page.goto("/"); await page.getByRole("button", { name: "New page", exact: true }).click();
	await add_block(page, "Log");
	await page.getByLabel("Name for My log", { exact: true }).fill("Gym log");
	await page.getByLabel("Name for My log", { exact: true }).press("Tab");
	await page.getByLabel("Field name", { exact: true }).fill("Minutes at gym");
	await expect(page.getByLabel("Field ID", { exact: true })).toHaveCount(0);
	await page.getByRole("button", { name: "Save connections", exact: true }).click();
	await add_block(page, "Chart");
	await expect(page.getByLabel("Show data from: Chart", { exact: true })).not.toHaveValue("");
	await page.getByRole("button", { name: "Save connections", exact: true }).click();
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await page.getByLabel("Minutes at gym", { exact: true }).fill("45");
	await page.getByRole("button", { name: "Submit Gym log", exact: true }).click();
	await page.getByLabel("Minutes at gym", { exact: true }).fill("60");
	await page.getByRole("button", { name: "Submit Gym log", exact: true }).click();
	await expect(page.getByRole("img", { name: "Chart, 2 values, from 45 to 60", exact: true })).toBeVisible();
	await page.screenshot({ path: "test-results/editor-log-chart-preview.png", fullPage: true });
	await page.getByRole("button", { name: "Back to editing", exact: true }).click();
	await expect(page.getByText("Saved on this browser", { exact: true })).toBeVisible();
	await page.reload();
	await expect(page.locator(".connected-page-block")).toHaveCount(2);
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await expect(page.getByText("No entries yet.", { exact: true })).toBeVisible();
});

test("a switch controls named app groups without advanced wiring", async ({ page }) => {
	await page.goto("/"); await page.getByRole("button", { name: "New page", exact: true }).click();
	await add_block(page, "Switch");
	await page.getByRole("button", { name: "Save connections", exact: true }).click();
	await add_block(page, "Control app access");
	await page.getByLabel("Block apps when: Control app access", { exact: true }).selectOption({ label: "Switch · switched on" });
	await page.getByLabel("App groups to control", { exact: true }).fill("Social, Games");
	await page.getByLabel("App groups to control", { exact: true }).press("Tab");
	await page.getByRole("button", { name: "Save connections", exact: true }).click();
	await expect(page.getByText("Saved on this browser", { exact: true })).toBeVisible();
	await page.reload();
	const groups = await page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document.behaviors.nodes.find((node: { kind: string }) => node.kind === "app_gate").config.groups);
	expect(groups).toEqual(["Social", "Games"]);
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await page.getByRole("checkbox", { name: "Switch", exact: true }).check();
	await expect(page.getByText("Simulated: app gate closed", { exact: true })).toBeVisible();
	await page.getByRole("checkbox", { name: "Switch", exact: true }).uncheck();
	await expect(page.getByText("Simulated: app gate open", { exact: true }).last()).toBeVisible();
});

test("incomplete connections cannot replace a saved routine and require a discard decision", async ({ page }) => {
	await seed_library(page, [starter_document]); await page.goto(STARTER_URL);
	await add_block(page, "Chart");
	await expect(page.getByRole("button", { name: "Save connections", exact: true })).toBeDisabled();
	expect(await page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document.behaviors)).toBeUndefined();
	page.once("dialog", dialog => dialog.dismiss());
	await page.getByRole("tab", { name: "Page", exact: true }).click();
	await expect(page.getByRole("heading", { name: "Data", exact: true })).toBeVisible();
	page.once("dialog", dialog => dialog.accept());
	await page.getByRole("button", { name: "Discard changes", exact: true }).click();
	await page.getByRole("tab", { name: "Page", exact: true }).click();
	await expect(page.getByLabel("Page name", { exact: true })).toHaveValue(starter_document.name);
});

test("block ordering and undo stay accessible without an inspector", async ({ page }) => {
	await seed_library(page, [starter_document]); await page.goto(STARTER_URL);
	await page.getByRole("button", { name: "Actions for Make some headway", exact: true }).click();
	await page.getByRole("button", { name: "Move down", exact: true }).click();
	await expect(page.locator(".document-row").nth(2)).toContainText("Session length");
	await page.getByRole("button", { name: "Undo edit", exact: true }).click();
	await expect(page.locator(".document-row").nth(1)).toContainText("Session length");
	await page.getByRole("button", { name: "Redo edit", exact: true }).click();
	await expect(page.locator(".document-row").nth(2)).toContainText("Session length");
});

test("previewing a scheduled routine never enables it on the account", async ({ page }) => {
	const document = templates.find(template => template.id === "bedtime")!.build();
	await seed_library(page, [document]); await page.goto(`/?routine=${document.id}`);
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await page.getByRole("switch", { name: "Switch Every night on or off", exact: true }).check();
	await page.getByRole("button", { name: "Back to editing", exact: true }).click();
	expect(await page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document.enabled)).toBe(false);
	await expect(page.getByText("Off until you enable it on your iPhone", { exact: true })).toBeVisible();
});

test("page and connections reflow and retain readable contrast", async ({ page }) => {
	await seed_library(page, [starter_document]);
	for (const width of [1440, 768, 375]) {
		await page.setViewportSize({ width, height: 1000 }); await page.goto(STARTER_URL);
		await expect(page.getByLabel("Page name", { exact: true })).toBeVisible();
		expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
		await page.screenshot({ path: `test-results/editor-page-${width}.png`, fullPage: true });
		await page.getByRole("tab", { name: "Routines", exact: true }).click();
		expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
		await page.screenshot({ path: `test-results/editor-connections-${width}.png`, fullPage: true });
		await page.getByRole("button", { name: "Add a connected block", exact: true }).click();
		await page.screenshot({ path: `test-results/editor-picker-${width}.png` });
		await page.getByLabel("Find a block", { exact: true }).press("Escape");
	}
	const ratios = await page.evaluate(() => {
		const canvas = document.createElement("canvas"); canvas.width = 1; canvas.height = 1;
		const ctx = canvas.getContext("2d", { willReadFrequently: true })!; const style = getComputedStyle(document.documentElement);
		function light(token: string) { ctx.clearRect(0, 0, 1, 1); ctx.fillStyle = style.getPropertyValue(token).trim(); ctx.fillRect(0, 0, 1, 1); const c = [...ctx.getImageData(0, 0, 1, 1).data].slice(0, 3).map(value => value / 255 <= .04045 ? value / 255 / 12.92 : ((value / 255 + .055) / 1.055) ** 2.4); return c[0] * .2126 + c[1] * .7152 + c[2] * .0722; }
		return [["--c-text", "--c-surface"], ["--c-text-faint", "--c-surface"], ["--c-text-dim", "--c-bg"], ["--c-accent-text", "--c-accent"]].map(([a, b]) => { const values = [light(a), light(b)].sort((x, y) => y - x); return (values[0] + .05) / (values[1] + .05); });
	});
	for (const ratio of ratios) { expect(ratio).toBeGreaterThanOrEqual(4.5); }
});
