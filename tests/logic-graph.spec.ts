import { expect, test, type Page } from "@playwright/test";
import { personal_routine } from "../lib/personal-routine";
import { starter_document } from "../lib/document";
import { seed_library } from "./helpers";

test("home graph edits real budgets and persists them across reload", async ({ page }) => {
	await seed_library(page, [personal_routine]);
	await page.goto("/?routine=home-distraction-allowance");
	await page.getByRole("tab", { name: "Logic", exact: true }).click();
	await page.getByRole("button", { name: "Fit graph" }).click();
	await expect(page.locator(".logic-wire")).toHaveCount(5);
	await page.getByRole("button", { name: "Configure Daily allowance", exact: true }).click();
	await page.getByLabel("Shared allowance (minutes)").first().fill("45");
	await page.getByRole("button", { name: "Apply to routine" }).click();
	await expect(page.locator(".logic-error")).toHaveCount(0);
	await page.getByRole("tab", { name: "Page", exact: true }).click();
	await expect(page.getByText("Mon, Tue, Wed, Thu: 45 minutes total")).toBeVisible();
	await page.reload();
	await expect(page.getByText("Mon, Tue, Wed, Thu: 45 minutes total")).toBeVisible();
	await page.getByRole("tab", { name: "Logic", exact: true }).click();
	await page.getByRole("button", { name: "Fit graph" }).click();
	await page.screenshot({ path: "test-results/logic-home-desktop.png", fullPage: true });
	for (const width of [768, 375]) {
		await page.setViewportSize({ width, height: 1000 });
		await page.getByRole("button", { name: width === 375 ? "Actual size" : "Fit graph" }).click();
		expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
		await page.screenshot({ path: `test-results/logic-home-${width}.png`, fullPage: true });
	}
});
test("users can add nodes, wire ports, reject invalid wiring and remove real rules", async ({ page }) => {
	const document = { ...starter_document, rules: { block_during_focus: true, notify_on_complete: false } };
	await seed_library(page, [document]);
	await page.goto("/?routine=my-focus-space&view=logic");
	await add_behavior(page, "Notify me");
	await page.getByRole("button", { name: "Fit graph" }).click();
	await page.getByRole("button", { name: "Timer output active", exact: true }).focus();
	await page.keyboard.press("Enter");
	await page.getByRole("button", { name: "Notify me input finished", exact: true }).focus();
	await page.keyboard.press("Enter");
	await expect(page.locator(".logic-error")).toContainText("do not match");
	await page.getByRole("button", { name: "Timer output finished", exact: true }).focus();
	await page.keyboard.press("Enter");
	await page.getByRole("button", { name: "Notify me input finished", exact: true }).focus();
	await page.keyboard.press("Enter");
	await page.getByRole("button", { name: "Apply to routine" }).click();
	await expect(page.locator(".logic-error")).toHaveCount(0);
	await expect.poll(async () => page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document.rules.notify_on_complete)).toBe(true);
	await page.getByRole("button", { name: "Configure Control apps", exact: true }).click();
	await page.getByRole("button", { name: "Disconnect active from gate" }).click();
	await page.getByRole("button", { name: "Apply to routine" }).click();
	await expect.poll(async () => page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document.rules.block_during_focus)).toBe(false);
	await page.getByRole("button", { name: "Timer output active", exact: true }).dragTo(page.getByRole("button", { name: "Control apps input gate", exact: true }));
	await page.getByRole("button", { name: "Apply to routine" }).click();
	await expect.poll(async () => page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document.rules.block_during_focus)).toBe(true);
	const heading = page.getByRole("button", { name: "Configure Timer", exact: true });
	const position = await heading.boundingBox();
	const before = await page.locator(".logic-node").filter({ has: heading }).getAttribute("transform");
	await page.mouse.move(position!.x + 50, position!.y + 15); await page.mouse.down(); await page.mouse.move(position!.x + 100, position!.y + 45, { steps: 5 }); await page.mouse.up();
	await expect(page.locator(".logic-node").filter({ has: heading })).not.toHaveAttribute("transform", before!);
	await page.screenshot({ path: "test-results/logic-builder-desktop.png", fullPage: true });
});


test("home logic deep links and day groups save only valid shared budgets", async ({ page }) => {
	await seed_library(page, [personal_routine]);
	await page.goto("/?routine=home-distraction-allowance&view=logic");
	await expect(page.getByRole("tab", { name: "Logic", exact: true })).toHaveAttribute("aria-selected", "true");
	await page.getByRole("button", { name: "Fit graph" }).click();
	await page.getByRole("button", { name: "Configure Daily allowance", exact: true }).click();
	await page.locator(".logic-settings fieldset").first().getByRole("checkbox", { name: "Mon", exact: true }).uncheck();
	await page.getByRole("button", { name: "Apply to routine" }).click();
	await expect(page.locator(".logic-error")).toContainText("all seven days");
	await page.getByRole("button", { name: "Add day group", exact: true }).click();
	const monday = page.locator(".logic-settings fieldset").last();
	await monday.getByLabel("Shared allowance (minutes)").fill("60");
	await monday.getByRole("button", { name: "Add window", exact: true }).click();
	await monday.getByLabel("From", { exact: true }).last().fill("19:00");
	await page.getByRole("button", { name: "Apply to routine" }).click();
	await expect(page.locator(".logic-error")).toContainText("non-overlapping");
	await monday.getByLabel("From", { exact: true }).last().fill("20:30");
	await page.getByRole("button", { name: "Apply to routine" }).click();
	await expect(page.locator(".logic-error")).toHaveCount(0);
	await expect.poll(async () => page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document.home_allowance.rules)).toEqual([
		{ ...personal_routine.home_allowance!.rules[0], days: [3, 4, 5] },
		...personal_routine.home_allowance!.rules.slice(1),
		{ days: [2], allowance_minutes: 60, windows: [{ start: "06:30", end: "20:30" }, { start: "20:30", end: "23:59" }] },
	]);
});


test("build a check-in counter goal reminder flow and test it before saving", async ({ page }) => {
	await seed_library(page, [starter_document]);
	await page.goto("/?routine=my-focus-space&view=logic");
	for (const name of ["Check-in", "Counter", "Goal", "Reminder"]) {
		await add_behavior(page, name);
		if (name === "Goal") { await page.getByLabel("Target value", { exact: true }).fill("2"); }
		if (name === "Reminder") { await page.getByLabel("Reminder message", { exact: true }).fill("Two check-ins done"); }
	}
	await page.getByRole("button", { name: "Fit graph" }).click();
	for (const [from, to] of [["Check-in output done", "Counter input increment"], ["Counter output value", "Goal input value"], ["Goal output reached", "Reminder input send"]]) {
		await page.getByRole("button", { name: from, exact: true }).focus(); await page.keyboard.press("Enter");
		await page.getByRole("button", { name: to, exact: true }).focus(); await page.keyboard.press("Enter");
	}
	await page.getByRole("button", { name: "Test logic", exact: true }).click();
	await page.getByRole("button", { name: "Check-in", exact: true }).click();
	await page.getByRole("button", { name: "Check-in", exact: true }).click();
	await expect(page.locator(".behavior-test").getByText("Two check-ins done", { exact: true })).toHaveCount(1);
	await page.getByRole("button", { name: "Apply to routine", exact: true }).click();
	await expect(page.locator(".logic-error")).toHaveCount(0);
	await expect.poll(async () => page.evaluate(() => JSON.parse(localStorage.getItem("pocketwork.library.v1")!).tools[0].document.schema_version)).toBe(3);
	await page.reload();
	await expect(page.getByRole("button", { name: "Configure Counter", exact: true })).toHaveCount(1);
	await page.getByRole("button", { name: "Fit graph" }).click();
	await page.screenshot({ path: "test-results/behaviors-desktop.png", fullPage: true });
});

async function add_behavior(page: Page, name: string) {
	const button = page.getByRole("button", { name: `Add ${name} node`, exact: true, includeHidden: true });
	if (!await button.isVisible()) { await page.locator("details.logic-category").filter({ has: button }).locator("summary").click(); }
	await button.click();
}
