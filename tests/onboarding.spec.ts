import { expect, test } from "@playwright/test";
import { starter_document } from "../lib/document";
import { seed_library, STARTER_URL } from "./helpers";

test("guides customization, preview testing, and honest iPhone setup", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto(STARTER_URL);
	const guide = page.getByRole("region", { name: "Quick start", exact: true });
	await expect(guide).toBeVisible();
	await guide.getByRole("button", { name: "Edit a block", exact: true }).click();
	await expect(page.getByLabel("Session length")).toBeVisible();
	await page.getByLabel("Session length").selectOption("30");
	await expect(page.getByLabel("Time remaining")).toHaveText("30:00");
	await guide.getByRole("button", { name: "2 Try your tool", exact: true }).click();
	await guide.getByRole("button", { name: "Open test mode", exact: true }).click();
	await expect(page.getByRole("button", { name: "Try it", exact: true })).toHaveAttribute("aria-pressed", "true");
	await page.getByRole("button", { name: "Start focusing", exact: true }).click();
	await expect(page.getByText("Blocking simulated in preview")).toBeVisible();
	await guide.getByRole("button", { name: "3 Take it to iPhone", exact: true }).click();
	await expect(guide).toContainText("there is no App Store download yet");
	await guide.getByRole("button", { name: "See iPhone setup", exact: true }).click();
	await expect(page.getByRole("heading", { name: "From canvas to iPhone" })).toBeVisible();
	await expect(page.getByRole("tab", { name: "iPhone", exact: true })).toHaveAttribute("aria-selected", "true");
});

test("dismissal persists and replay never replaces an existing draft", async ({ page }) => {
	await seed_library(page, [{ ...starter_document, name: "My existing tool" }]);
	await page.goto(STARTER_URL);
	await expect(page.getByText("Saved on this browser")).toBeVisible();
	await page.getByRole("button", { name: "Dismiss quick start" }).click();
	await expect(page.getByRole("button", { name: "Quick start", exact: true })).toBeFocused();
	await page.reload();
	await expect(page.getByText("Saved on this browser")).toBeVisible();
	await expect(page.getByRole("region", { name: "Quick start", exact: true })).toHaveCount(0);
	await page.getByRole("button", { name: "Quick start", exact: true }).click();
	await expect(page.getByRole("region", { name: "Quick start", exact: true })).toBeVisible();
	await expect(page.getByRole("heading", { name: "My existing tool", exact: true })).toBeVisible();
	await expect(page.locator(".block-outline li")).toHaveCount(4);
});

test("existing native blocks open settings instead of appearing disabled", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto(STARTER_URL);
	await page.getByRole("button", { name: "Try it", exact: true }).click();
	await page.getByRole("button", { name: "Edit Focus timer", exact: true }).click();
	await expect(page.getByLabel("Session length")).toBeVisible();
	await expect(page.getByRole("button", { name: "Edit", exact: true })).toHaveAttribute("aria-pressed", "true");
	await expect(page.locator(".block-outline li")).toHaveCount(4);
	await page.getByRole("button", { name: "Edit Screen Time", exact: true }).click();
	await expect(page.getByText("Your selection stays on your phone.")).toBeVisible();
	await page.getByRole("tab", { name: "Rules", exact: true }).click();
	await page.getByRole("button", { name: "Test these rules", exact: true }).click();
	await expect(page.getByRole("button", { name: "Start focusing", exact: true })).toBeEnabled();
});

test("guidance works for a blank tool with no timer", async ({ page }) => {
	await seed_library(page, [{ ...starter_document, blocks: [starter_document.blocks[0]], rules: { block_during_focus: false, notify_on_complete: false } }]);
	await page.goto(STARTER_URL);
	await page.getByRole("button", { name: "Edit a block", exact: true }).click();
	await expect(page.getByRole("textbox", { name: "Supporting text", exact: true })).toBeVisible();
	await page.getByRole("button", { name: "Add Counter", exact: true }).click();
	await page.getByRole("button", { name: "2 Try your tool", exact: true }).click();
	await page.getByRole("button", { name: "Open test mode", exact: true }).click();
	await page.getByRole("button", { name: "Increment Small wins", exact: true }).click();
	await expect(page.locator(".counter-value")).toContainText("1 / 5");
});

test("narrow layouts take block selection to settings and back to preview", async ({ page }) => {
	await seed_library(page, [starter_document]);
	for (const width of [768, 375]) {
		await page.setViewportSize({ width, height: 900 });
		await page.goto(STARTER_URL);
		await page.getByRole("button", { name: "Edit Focus timer", exact: true }).click();
		await expect(page.getByRole("complementary", { name: "Inspector", exact: true })).toBeFocused();
		await expect(page.getByRole("button", { name: "Back to preview", exact: true })).toBeInViewport();
		await page.getByRole("button", { name: "Back to preview", exact: true }).click();
		await expect(page.getByRole("region", { name: "Workbench canvas", exact: true })).toBeFocused();
		await expect(page.getByRole("button", { name: "Try it", exact: true })).toBeInViewport();
		expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
	}
});

test("unavailable guide storage does not block editing or saving the tool", async ({ page }) => {
	await page.addInitScript(() => {
		const get_item = Storage.prototype.getItem;
		const set_item = Storage.prototype.setItem;
		Storage.prototype.getItem = function(key) { if (key === "pocketwork.guide.v1") { throw new Error("guide read denied"); } return get_item.call(this, key); };
		Storage.prototype.setItem = function(key, value) { if (key === "pocketwork.guide.v1") { throw new Error("guide write denied"); } return set_item.call(this, key, value); };
	});
	await seed_library(page, [starter_document]);
	await page.goto(STARTER_URL);
	await page.getByRole("button", { name: "Dismiss quick start" }).click();
	await expect(page.getByRole("region", { name: "Quick start", exact: true })).toHaveCount(0);
	await expect(page.getByText("Could not remember the quick-start preference. Your tool is unaffected.")).toBeVisible();
	await page.getByRole("button", { name: "Add Note", exact: true }).click();
	await expect(page.getByText("Saved on this browser")).toBeVisible();
	await expect(page.locator(".block-outline li")).toHaveCount(5);
});
