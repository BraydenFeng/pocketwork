import { expect, test } from "@playwright/test";
import { starter_document } from "../lib/document";
import { seed_library, STARTER_URL } from "./helpers";

test("a new browser goes from routine to editor to a saved tool card", async ({ page }) => {
	await page.goto("/");
	await expect(page.getByRole("heading", { name: "Nothing here yet." })).toBeVisible();
	await expect(page.locator(".tool-card:not(.is-template)")).toHaveCount(0);
	const deep_work = page.getByRole("list", { name: "Routines" }).locator(".tool-card", { hasText: "Deep work" });
	await deep_work.getByRole("button", { name: "Use this routine" }).click();
	await expect(page.getByRole("heading", { name: "Deep work", exact: true })).toBeVisible();
	await expect(page.getByLabel("Time remaining")).toHaveText("90:00");
	await expect(page).toHaveURL(/\?tool=/);
	await page.getByRole("button", { name: "My tools", exact: true }).click();
	await expect(page).not.toHaveURL(/\?tool=/);
	await expect(page.getByRole("button", { name: "Open Deep work", exact: true })).toBeVisible();
	await expect(page.locator(".tool-card:not(.is-template)").first()).toContainText("90 min session · blocks apps · 3 tasks");
	await page.reload();
	await expect(page.getByRole("button", { name: "Open Deep work", exact: true })).toBeVisible();
});

test("the browser back button returns from the editor to my tools", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto("/");
	await page.getByRole("button", { name: "Open My focus space", exact: true }).click();
	await expect(page.getByRole("heading", { name: "My focus space", exact: true })).toBeVisible();
	await page.goBack();
	await expect(page.getByRole("heading", { name: "My tools", exact: true })).toBeVisible();
	await page.goForward();
	await expect(page.getByRole("heading", { name: "My focus space", exact: true })).toBeVisible();
});

test("edits made in the editor show up on the card and survive reload", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto(STARTER_URL);
	await page.getByRole("tab", { name: "App", exact: true }).click();
	await page.getByLabel("App name", { exact: true }).fill("Evening reset");
	await page.getByLabel("App name", { exact: true }).press("Tab");
	await expect(page.getByText("Saved on this browser")).toBeVisible();
	await page.getByRole("button", { name: "Back to my tools", exact: true }).click();
	await expect(page.getByRole("button", { name: "Open Evening reset", exact: true })).toBeVisible();
	await page.reload();
	await expect(page.getByRole("button", { name: "Open Evening reset", exact: true })).toBeVisible();
});

test("duplicate and delete keep the list honest", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto("/");
	await page.getByRole("button", { name: "Duplicate My focus space", exact: true }).click();
	await expect(page.locator(".tool-card:not(.is-template)")).toHaveCount(2);
	await expect(page.getByRole("button", { name: "Open My focus space copy", exact: true })).toBeVisible();
	page.once("dialog", (dialog) => dialog.dismiss());
	await page.getByRole("button", { name: "Delete My focus space copy", exact: true }).click();
	await expect(page.locator(".tool-card:not(.is-template)")).toHaveCount(2);
	page.once("dialog", (dialog) => dialog.accept());
	await page.getByRole("button", { name: "Delete My focus space copy", exact: true }).click();
	await expect(page.locator(".tool-card:not(.is-template)")).toHaveCount(1);
	await expect(page.locator(".notice-banner")).toContainText("Deleted");
	await page.reload();
	await expect(page.locator(".tool-card:not(.is-template)")).toHaveCount(1);
});

test("a v1 single draft appears as the first tool without being erased", async ({ page }) => {
	await page.addInitScript((draft) => localStorage.setItem("pocketwork.document.v1", JSON.stringify(draft)), { ...starter_document, name: "My old draft" });
	await page.goto("/");
	await expect(page.getByRole("button", { name: "Open My old draft", exact: true })).toBeVisible();
	expect(await page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.document.v1")!).name)).toBe("My old draft");
	await page.getByRole("button", { name: "Open My old draft", exact: true }).click();
	await expect(page.getByLabel("Time remaining")).toHaveText("25:00");
});

test("an unknown tool link falls back to my tools", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto("/?tool=does-not-exist");
	await expect(page.getByRole("heading", { name: "My tools", exact: true })).toBeVisible();
});
