import { expect, test } from "@playwright/test";
import { personal_routine } from "../lib/personal-routine";
import { starter_document } from "../lib/document";
import { seed_library } from "./helpers";

test("the home allowance is edited as a page without a graph", async ({ page }) => {
	await seed_library(page, [personal_routine]);
	await page.goto("/?routine=home-distraction-allowance&view=logic");
	await expect(page.getByRole("heading", { name: "Page", exact: true })).toBeVisible();
	await expect(page.getByRole("heading", { name: "Routines", exact: true })).toBeVisible();
	await expect(page.getByRole("heading", { name: "Data", exact: true })).toBeVisible();
	await expect(page.getByRole("button", { name: "Edit Home screen-time allowance", exact: true })).toHaveAttribute("aria-expanded", "false");
	await expect(page.getByLabel("Block title: Home allowance", { exact: true })).toHaveCount(0);
	await expect(page.getByLabel("App blocking mode", { exact: true })).toHaveCount(0);
	await expect(page.getByRole("tab", { name: "Logic", exact: true })).toHaveCount(0);
	await expect(page.locator(".logic-node, .logic-wire, .logic-port")).toHaveCount(0);
	await page.screenshot({ path: "test-results/allowance-unified-default.png", fullPage: true });
	await page.setViewportSize({ width: 375, height: 1000 });
	await page.screenshot({ path: "test-results/allowance-unified-default-mobile.png", fullPage: true });
	await page.setViewportSize({ width: 1280, height: 720 });
	await page.getByRole("button", { name: "Edit Home screen-time allowance", exact: true }).click();
	await page.getByLabel("Daily allowance", { exact: true }).first().fill("45");
	await page.getByLabel("Daily allowance", { exact: true }).first().press("Tab");
	await expect(page.getByText("Saved on this browser", { exact: true })).toBeVisible();
	await expect.poll(async () => page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document.home_allowance.rules[0].allowance_minutes)).toBe(45);
	await expect(page.getByText("Outside either one, this routine does not block anything.", { exact: false })).toBeVisible();
	await page.getByRole("button", { name: "Add a block", exact: true }).click();
	await page.getByRole("dialog").getByRole("button", { name: "Add Text", exact: true }).click();
	await page.getByLabel("Text: Text", { exact: true }).fill("How did today feel?");
	await page.getByLabel("Text: Text", { exact: true }).press("Tab");
	await page.getByRole("button", { name: "Add routine block", exact: true }).click();
	await page.getByRole("dialog").getByRole("button", { name: "Add Button", exact: true }).click();
	await page.getByLabel("Name for Button", { exact: true }).fill("Log today");
	await page.getByLabel("Name for Button", { exact: true }).press("Tab");
	await page.getByRole("button", { name: "Add data block", exact: true }).click();
	await page.getByRole("dialog").getByRole("button", { name: "Add Variable", exact: true }).click();
	await page.getByLabel("Name for Variable", { exact: true }).fill("Daily score");
	await page.getByLabel("Name for Variable", { exact: true }).press("Tab");
	await expect(page.getByText("Saved on this browser", { exact: true })).toBeVisible();
	await expect.poll(async () => page.evaluate(() => {
		const document = JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document;
		return {
			page: document.blocks.some((block: { type: string; text?: string }) => block.type === "note" && block.text === "How did today feel?"),
			routines: document.behaviors.nodes.some((node: { kind: string; config: { label: string } }) => node.kind === "button" && node.config.label === "Log today"),
			data: document.behaviors.nodes.some((node: { kind: string; config: { label: string } }) => node.kind === "variable" && node.config.label === "Daily score"),
		};
	})).toEqual({ page: true, routines: true, data: true });
	await page.reload();
	await expect(page.getByLabel("Text: Text", { exact: true })).toHaveValue("How did today feel?");
	await expect(page.getByRole("button", { name: "Edit Log today", exact: true })).toBeVisible();
	await expect(page.getByRole("button", { name: "Edit Daily score", exact: true })).toBeVisible();
	for (const width of [1440, 768, 375]) {
		await page.setViewportSize({ width, height: 1000 });
		expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
		await page.screenshot({ path: `test-results/allowance-page-${width}.png`, fullPage: true });
	}
});

test("old graph deep links open the same unified page editor", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto("/?routine=my-focus-space&view=logic");
	await expect(page.getByRole("heading", { name: "Routines", exact: true })).toBeVisible();
	await expect(page.getByRole("heading", { name: "Data", exact: true })).toBeVisible();
	await expect(page.locator(".logic-node, .logic-wire, .logic-port")).toHaveCount(0);
	await expect(page.getByRole("button", { name: "Advanced wiring", exact: true })).toHaveCount(0);
	await page.getByRole("button", { name: "Add routine block", exact: true }).click();
	await page.getByRole("dialog").getByRole("button", { name: "Add Button", exact: true }).click();
	await page.getByLabel("Name for Button", { exact: true }).fill("Done");
	await page.getByLabel("Name for Button", { exact: true }).press("Tab");
	await page.getByRole("button", { name: "Add routine block", exact: true }).click();
	await page.getByRole("dialog").getByRole("button", { name: "Add Show a message", exact: true }).click();
	await page.getByLabel("Message", { exact: true }).fill("Nice work");
	await page.getByLabel("Message", { exact: true }).press("Tab");
	await page.getByLabel("Show message when: Show a message", { exact: true }).selectOption({ label: "Done · when tapped" });
	await expect(page.getByText("Saved on this browser", { exact: true })).toBeVisible();
	await page.getByRole("button", { name: "Preview", exact: true }).click();
	await page.getByRole("button", { name: "Done", exact: true }).click();
	await expect(page.getByText("Nice work", { exact: true })).toBeVisible();
});

test("an incomplete day split stays visible until every day is assigned", async ({ page }) => {
	await seed_library(page, [personal_routine]);
	await page.goto("/?routine=home-distraction-allowance");
	await page.getByRole("button", { name: "Edit Home screen-time allowance", exact: true }).click();
	await page.getByRole("group", { name: "Days for group 1", exact: true }).getByRole("button", { name: "Mon", exact: true }).click();
	await expect(page.locator(".document-draft-warning")).toContainText("all seven days");
	await expect(page.getByText("Schedule needs attention", { exact: true })).toBeVisible();
	await page.getByRole("button", { name: "Add day group", exact: true }).click();
	await expect(page.getByText("Saved on this browser", { exact: true })).toBeVisible();
	await expect.poll(async () => page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document.home_allowance.rules.length)).toBe(4);
	expect(await page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document.home_allowance.outside_windows)).toBe("unrestricted");
});
