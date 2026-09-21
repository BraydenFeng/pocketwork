import { expect, test } from "@playwright/test";
import { starter_document } from "../lib/document";
import { seed_library, STARTER_URL } from "./helpers";

test("customization, preview testing, and iPhone help need no setup wizard", async ({ page }) => {
	await seed_library(page, [starter_document]); await page.goto(STARTER_URL);
	await expect(page.getByRole("region", { name: "Quick start" })).toHaveCount(0);
	await page.getByLabel("Session length").fill("30");
	await page.getByLabel("Session length").press("Tab");
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await expect(page.getByLabel("Time remaining")).toHaveText("30:00");
	await page.getByRole("button", { name: "Start focusing", exact: true }).click();
	await expect(page.locator(".preview-shield")).toContainText("simulated");
	await page.getByRole("button", { name: "More page options" }).click();
	await page.getByRole("button", { name: "Use on iPhone", exact: true }).click();
	await expect(page.locator(".creation-help")).toContainText("same sign-in to sync");
	await expect(page.locator(".creation-help")).toContainText("Browser previews never change phone restrictions");
});

test("opening and closing help never replaces an existing routine", async ({ page }) => {
	await seed_library(page, [{ ...starter_document, name: "My existing tool" }]); await page.goto(STARTER_URL);
	await page.getByRole("button", { name: "More page options" }).click();
	await page.getByRole("button", { name: "Use on iPhone", exact: true }).click();
	await page.getByRole("button", { name: "Close iPhone help" }).click();
	await expect(page.locator(".creation-help")).toHaveCount(0);
	await page.reload();
	await expect(page.getByLabel("Page name", { exact: true })).toHaveValue("My existing tool");
	await expect(page.locator(".document-row")).toHaveCount(4);
});

test("native settings are editable inline and preview is a separate mode", async ({ page }) => {
	await seed_library(page, [starter_document]); await page.goto(STARTER_URL);
	await expect(page.getByLabel("Session length")).toBeEditable();
	await expect(page.getByLabel("App blocking mode")).toBeEnabled();
	await expect(page.getByText(/Choose the actual apps privately on your iPhone/)).toBeVisible();
	await page.getByRole("tab", { name: "Routines", exact: true }).click();
	await page.getByRole("tab", { name: "Page", exact: true }).click();
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await expect(page.getByRole("button", { name: "Start focusing", exact: true })).toBeEnabled();
	await page.getByRole("button", { name: "Back to editing", exact: true }).click();
	await expect(page.getByLabel("Session length")).toBeEditable();
});

test("a routine without a timer can add a counter and test it", async ({ page }) => {
	await seed_library(page, [{ ...starter_document, blocks: [starter_document.blocks[0]], rules: { block_during_focus: false, notify_on_complete: false } }]); await page.goto(STARTER_URL);
	await expect(page.getByLabel("Supporting text: A little less noise.", { exact: true })).toBeEditable();
	await page.getByRole("button", { name: "Add a block", exact: true }).click();
	await page.getByRole("button", { name: "Add Counter", exact: true }).click();
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await page.getByRole("button", { name: "Increment Small wins", exact: true }).click();
	await expect(page.locator(".counter-value")).toContainText("1 / 5");
});

test("narrow layouts keep settings and preview reachable without an inspector", async ({ page }) => {
	await seed_library(page, [starter_document]);
	for (const width of [768, 375]) {
		await page.setViewportSize({ width, height: 900 }); await page.goto(STARTER_URL);
		await expect(page.getByLabel("Session length")).toBeEditable();
		await expect(page.getByRole("complementary", { name: "Inspector" })).toHaveCount(0);
		await page.getByRole("button", { name: "Preview", exact: true }).click();
		await expect(page.getByRole("button", { name: "Back to editing", exact: true })).toBeInViewport();
		await page.getByRole("button", { name: "Back to editing", exact: true }).click();
		await expect(page.getByRole("button", { name: "Preview", exact: true })).toBeInViewport();
		expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
	}
});

test("unavailable legacy guide storage does not block editing or saving", async ({ page }) => {
	await page.addInitScript(() => {
		const get_item = Storage.prototype.getItem; const set_item = Storage.prototype.setItem;
		Storage.prototype.getItem = function(key) { if (key === "pocketwork.guide.v1") { throw new Error("guide read denied"); } return get_item.call(this, key); };
		Storage.prototype.setItem = function(key, value) { if (key === "pocketwork.guide.v1") { throw new Error("guide write denied"); } return set_item.call(this, key, value); };
	});
	await seed_library(page, [starter_document]); await page.goto(STARTER_URL);
	await page.getByRole("button", { name: "Add a block", exact: true }).click();
	await page.getByRole("button", { name: "Add Text", exact: true }).click();
	await expect(page.getByText("Saved on this browser")).toBeVisible();
	await expect(page.locator(".document-row")).toHaveCount(5);
	await page.reload();
	await expect(page.locator(".document-row")).toHaveCount(5);
});
