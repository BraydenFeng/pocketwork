import { expect, test } from "@playwright/test";
import { starter_document } from "../lib/document";
import { templates } from "../lib/templates";
import { seed_library, STARTER_URL } from "./helpers";

test("a new browser starts blank without a ready-made catalog", async ({ page }) => {
	await page.goto("/");
	await expect(page.getByRole("heading", { name: "Nothing here yet." })).toBeVisible();
	await expect(page.getByRole("button", { name: "Use this routine" })).toHaveCount(0);
	await page.getByRole("button", { name: "New page", exact: true }).click();
	await expect(page).toHaveURL(/\?routine=/);
	await page.getByRole("button", { name: "My pages", exact: true }).click();
	await expect(page.getByRole("button", { name: "Open Untitled page", exact: true })).toBeVisible();
	await page.reload();
	await expect(page.getByRole("button", { name: "Open Untitled page", exact: true })).toBeVisible();
});

test("the browser back button returns from the editor to my tools", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto("/");
	await page.getByRole("button", { name: "Open My focus space", exact: true }).click();
	await expect(page.getByRole("heading", { name: "My focus space", exact: true })).toBeVisible();
	await page.goBack();
	await expect(page.getByRole("heading", { name: "My pages", exact: true })).toBeVisible();
	await page.goForward();
	await expect(page.getByRole("heading", { name: "My focus space", exact: true })).toBeVisible();
});

test("edits made in the editor show up on the card and survive reload", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto(STARTER_URL);
	await page.getByLabel("Page name", { exact: true }).fill("Evening reset");
	await page.getByLabel("Page name", { exact: true }).press("Tab");
	await expect(page.getByText("Saved on this browser")).toBeVisible();
	await page.getByRole("button", { name: "My pages", exact: true }).click();
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
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await expect(page.getByLabel("Time remaining")).toHaveText("25:00");
});

test("an unknown tool link falls back to my tools", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto("/?routine=does-not-exist");
	await expect(page.getByRole("heading", { name: "My pages", exact: true })).toBeVisible();
});

test("a scheduled routine gets a switch instead of a start button, on the card and in the preview", async ({ page }) => {
	await seed_library(page, [templates.find((t) => t.id === "bedtime")!.build()]);
	await page.goto("/");
	await page.getByRole("button", { name: "Open Phone-free bedtime", exact: true }).click();
	await expect(page.getByRole("heading", { name: "Phone-free bedtime", exact: true })).toBeVisible();
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await expect(page.getByRole("button", { name: "Start focusing" })).toHaveCount(0);
	await expect(page.getByText("Every day · 10 PM to 7 AM")).toBeVisible();
	await expect(page.getByText("Off · switch it on to start enforcing")).toBeVisible();
	await page.getByRole("switch", { name: "Switch Every night on or off" }).check();
	await expect(page.getByText(/^(On · next|Active now)/)).toBeVisible();
	await page.getByRole("button", { name: "More page options", exact: true }).click();
	await page.getByRole("button", { name: "Advanced wiring", exact: true }).click();
	await expect(page.getByRole("button", { name: "Configure Time window" })).toBeVisible();
	await page.getByRole("button", { name: "My pages", exact: true }).click();
	const card = page.locator(".tool-card:not(.is-template)", { hasText: "Phone-free bedtime" });
	await expect(card.getByRole("switch", { name: "Switch Phone-free bedtime on or off" })).not.toBeChecked();
	await card.getByRole("switch", { name: "Switch Phone-free bedtime on or off" }).check();
	await card.getByRole("switch", { name: "Switch Phone-free bedtime on or off" }).uncheck();
	await expect(card).toContainText("Off · switch it on to start enforcing");
	await page.reload();
	await expect(page.locator(".tool-card:not(.is-template)", { hasText: "Phone-free bedtime" }).getByRole("switch")).not.toBeChecked();
});

test("the editor refuses a timer next to a schedule and edits the window", async ({ page }) => {
	await seed_library(page, [templates.find((t) => t.name === "Workday focus")!.build()]);
	await page.goto("/");
	await page.getByRole("button", { name: "Open Workday focus", exact: true }).click();
	await page.getByRole("button", { name: "Add a block", exact: true }).click();
	await page.getByRole("button", { name: "Add Focus timer", exact: true }).click();
	await expect(page.locator(".alert-banner")).toContainText("not both");
	await page.getByRole("group", { name: "Days of the week" }).getByRole("button", { name: "Sat" }).click();
	await page.getByLabel("Ends").fill("18:00");
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await expect(page.getByText("Mon, Tue, Wed, Thu, Fri, Sat · 9 AM to 6 PM")).toBeVisible();
});

test("app groups are named on the home screen and used by routines", async ({ page }) => {
	await seed_library(page, [templates.find((t) => t.name === "Workday focus")!.build()]);
	await page.goto("/");
	await page.getByLabel("New group name").fill("Social");
	await page.getByRole("button", { name: "Add group", exact: true }).click();
	await expect(page.getByRole("list", { name: "App groups" })).toContainText("Social");
	await expect(page.getByRole("list", { name: "App groups" })).toContainText("not used yet");
	await page.getByRole("button", { name: "Open Workday focus", exact: true }).click();
	await expect(page.getByLabel("App blocking mode")).toHaveValue("allow_only");
	await page.getByRole("checkbox", { name: "Social" }).check();
	await expect(page.getByText(/Only Work, Social/)).toBeVisible();
	await page.getByLabel("App blocking mode").selectOption("limit");
	await page.getByLabel("Minutes before blocking").fill("45");
	await page.getByLabel("Minutes before blocking").press("Tab");
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await expect(page.locator(".preview-shield")).toContainText("Work, Social · 45 min limit");
	await page.getByRole("button", { name: "My pages", exact: true }).click();
	const groups = page.getByRole("list", { name: "App groups" });
	await expect(groups).toContainText("Work");
	await groups.locator(".group-chip", { hasText: "Social" }).getByRole("button", { name: "Rename Social" }).click();
	await page.getByLabel("New name for Social").fill("Feeds");
	await page.getByLabel("New name for Social").press("Enter");
	await expect(page.locator(".tool-card:not(.is-template)", { hasText: "Workday focus" })).toContainText("Work, Feeds · 45 min limit");
	page.once("dialog", (dialog) => dialog.accept());
	await groups.locator(".group-chip", { hasText: "Feeds" }).getByRole("button", { name: "Delete group Feeds" }).click();
	await expect(page.locator(".alert-banner")).toContainText("used by");
});
