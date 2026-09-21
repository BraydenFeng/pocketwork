import { expect, test } from "@playwright/test";
import { blank_tool } from "../lib/templates";
import { seed_library } from "./helpers";

test("free pages preserve existing edits and a deletion makes room", async ({ page }) => {
	const documents = ["one", "two", "three"].map(id => ({ ...blank_tool(), id, name: id }));
	await seed_library(page, documents); await page.goto("/");
	await page.getByRole("button", { name: "New page", exact: true }).click();
	await expect(page.getByRole("alert").filter({ hasText: "3 pages" })).toBeVisible();
	await page.getByRole("button", { name: "Open one", exact: true }).click();
	await page.getByLabel("Page name", { exact: true }).fill("Edited one"); await page.getByLabel("Page name", { exact: true }).press("Tab");
	await expect(page.getByText("Saved on this browser", { exact: true })).toBeVisible();
	await page.getByRole("button", { name: "My pages", exact: true }).click();
	page.once("dialog", dialog => dialog.accept()); await page.getByRole("button", { name: "Delete two", exact: true }).click();
	await page.getByRole("button", { name: "New page", exact: true }).click();
	await expect(page.getByLabel("Page name", { exact: true })).toHaveValue("Untitled page");
});
test("routines and data are distinct views of one editable page", async ({ page }) => {
	await page.goto("/"); await page.getByRole("button", { name: "New page", exact: true }).click();
	await page.getByRole("button", { name: "Add a block", exact: true }).click(); await page.getByRole("button", { name: "Add Variable", exact: true }).click();
	await expect(page.getByRole("tab", { name: "Data", exact: true })).toHaveAttribute("aria-selected", "true");
	await page.getByRole("tab", { name: "Routines", exact: true }).click();
	await expect(page.getByRole("button", { name: "Configure Variable", exact: true })).toHaveCount(0);
	await page.getByRole("tab", { name: "Data", exact: true }).click();
	await expect(page.getByRole("button", { name: "Configure Variable", exact: true })).toBeVisible();
	await page.getByRole("button", { name: "Save connections", exact: true }).click();
});
test("account and launch documents are usable at desktop and phone sizes", async ({ page }) => {
	for (const width of [1440, 768, 375]) {
		await page.setViewportSize({ width, height: 1000 });
		for (const route of ["account", "privacy", "support", "terms"]) {
			await page.goto(`/${route}`); await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
			expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
			expect(await page.locator("main").ariaSnapshot()).toContain("My pages");
			await page.screenshot({ path: `test-results/launch-${route}-${width}.png`, fullPage: true });
		}
	}
});
