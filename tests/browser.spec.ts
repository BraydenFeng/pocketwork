import { expect, test } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { parse_document, starter_document } from "../lib/document";
import { seed_library, STARTER_URL } from "./helpers";

test("edits, adds, reorders, undoes, and persists a tool", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto(STARTER_URL);
	await expect(page.getByText("Saved on this browser")).toBeVisible();
	await page.getByLabel("Page name", { exact: true }).fill("My quiet morning");
	await page.getByLabel("Page name", { exact: true }).press("Tab");
	await expect(page.getByRole("heading", { name: "My quiet morning" })).toBeVisible();
	await page.getByRole("button", { name: "Add a block", exact: true }).click();
	await page.getByRole("button", { name: "Add Counter", exact: true }).click();
	await page.getByLabel("Block title: Small wins", { exact: true }).fill("Pages read");
	await page.getByLabel("Block title: Small wins", { exact: true }).press("Tab");
	await expect(page.getByLabel("Block title: Pages read", { exact: true })).toBeVisible();
	await page.getByRole("button", { name: "Actions for Pages read", exact: true }).click();
	await page.getByRole("button", { name: "Move up", exact: true }).click();
	await expect(page.locator(".document-row").nth(3).getByRole("textbox")).toHaveValue("Pages read");
	await page.getByRole("button", { name: "Undo edit", exact: true }).click();
	await expect(page.locator(".document-row").nth(4).getByRole("textbox")).toHaveValue("Pages read");
	await page.getByRole("button", { name: "Redo edit", exact: true }).click();
	await expect(page.getByText("Saved on this browser")).toBeVisible();
	await page.reload();
	await expect(page.getByRole("heading", { name: "My quiet morning" })).toBeVisible();
	await expect(page.locator(".document-row").nth(3).getByRole("textbox")).toHaveValue("Pages read");
});

test("runs the preview and completes its simulated rules", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto(STARTER_URL);
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await page.getByRole("button", { name: "Start focusing", exact: true }).click();
	await expect(page.locator(".preview-shield")).toContainText("simulated");
	await page.getByRole("checkbox", { name: "Choose one thing to work on" }).check();
	await expect(page.locator(".preview-label-row")).toContainText("1/3");
	await page.getByRole("button", { name: "Simulate timer finishing" }).click();
	await expect(page.getByText("Session completed", { exact: true })).toBeVisible();
	await expect(page.locator(".event-log")).toContainText("notification simulated");
	await page.getByRole("button", { name: "Start again", exact: true }).click();
	await page.getByRole("button", { name: "End session", exact: true }).click();
	await expect(page.getByText("Ready when you are", { exact: true })).toBeVisible();
});

test("exports strict JSON and cleans dependent rules when deleting blocks", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto(STARTER_URL);
	await expect(page.getByText("Saved on this browser")).toBeVisible();
	await page.getByRole("button", { name: "Actions for Leave distractions outside", exact: true }).click();
	await page.getByRole("button", { name: "Remove block", exact: true }).click();
	const download_event = page.waitForEvent("download");
	await page.getByRole("button", { name: "More page options", exact: true }).click();
	await page.getByRole("button", { name: "Export page", exact: true }).click();
	const download = await download_event;
	const file = await download.path();
	expect(file).not.toBeNull();
	const document = parse_document(await readFile(file!, "utf8"));
	expect(document.rules.block_during_focus).toBe(false);
	expect(document.blocks.some((block) => block.type === "screen_time")).toBe(false);
	expect(download.suggestedFilename()).toBe("my-focus-space.pocketwork.json");
});

test("bad import leaves the library alone; a valid file becomes a new tool", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto("/");
	await page.getByLabel("Import page file").setInputFiles({ name: "broken.json", mimeType: "application/json", buffer: Buffer.from("broken") });
	await expect(page.locator(".alert-banner")).toContainText("not a valid JSON");
	await expect(page.locator(".tool-card:not(.is-template)")).toHaveCount(1);
	await page.getByLabel("Import page file").setInputFiles({ name: "new.json", mimeType: "application/json", buffer: Buffer.from(JSON.stringify({ ...starter_document, name: "Imported space" })) });
	await expect(page.getByRole("heading", { name: "Imported space", exact: true })).toBeVisible();
	await page.getByRole("button", { name: "My pages", exact: true }).click();
	await expect(page.locator(".tool-card:not(.is-template)")).toHaveCount(2);
	await expect(page.getByRole("button", { name: "Open Imported space", exact: true })).toBeVisible();
	await expect(page.getByRole("button", { name: "Open My focus space", exact: true })).toBeVisible();
});

test("unreadable storage is never silently overwritten", async ({ page }) => {
	await page.addInitScript(() => localStorage.setItem("pocketwork.library.v1", "unreadable"));
	await page.goto("/");
	await expect(page.locator(".alert-banner")).toContainText("not been overwritten");
	await page.getByRole("button", { name: "New page", exact: true }).click();
	await page.getByRole("button", { name: "Add a block", exact: true }).click();
	await page.getByRole("button", { name: "Add Text", exact: true }).click();
	await page.waitForTimeout(500);
	expect(await page.evaluate(() => localStorage.getItem("pocketwork.library.v1"))).toBe("unreadable");
});

test("layout reflows without document overflow", async ({ page }) => {
	await seed_library(page, [starter_document]);
	for (const width of [1440, 768, 375]) {
		await page.setViewportSize({ width, height: 1000 });
		await page.goto("/");
		await expect(page.getByRole("heading", { name: "My pages", exact: true })).toBeVisible();
		expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
		await page.screenshot({ path: `test-results/home-${width}.png`, fullPage: true });
		await page.goto(STARTER_URL);
		await expect(page.getByRole("heading", { name: "My focus space", exact: true })).toBeVisible();
		await expect(page.getByText("Saved on this browser")).toBeVisible();
		expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
		await page.screenshot({ path: `test-results/workbench-${width}.png`, fullPage: true });
	}
});

test("text and surface contrast meet AA", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto(STARTER_URL);
	const ratios = await page.evaluate(() => {
		const canvas = document.createElement("canvas"); canvas.width = 1; canvas.height = 1;
		const context = canvas.getContext("2d", { willReadFrequently: true })!;
		const root = getComputedStyle(document.documentElement);
		function luminance(token: string) {
			context.clearRect(0, 0, 1, 1); context.fillStyle = root.getPropertyValue(token).trim(); context.fillRect(0, 0, 1, 1);
			const channels = [...context.getImageData(0, 0, 1, 1).data].slice(0, 3).map((value) => { const channel = value / 255; return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4; });
			return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
		}
		return [["--c-text", "--c-surface"], ["--c-text-faint", "--c-bg"], ["--c-text-dim", "--c-surface"], ["--c-accent-text", "--c-accent"]].map(([text, background]) => {
			const values = [luminance(text), luminance(background)].sort((left, right) => right - left);
			return { pair: `${text}/${background}`, ratio: (values[0] + 0.05) / (values[1] + 0.05) };
		});
	});
	for (const result of ratios) { expect(result.ratio, result.pair).toBeGreaterThanOrEqual(4.5); }
});
