import { expect, test } from "@playwright/test";
import { personal_routine } from "../lib/personal-routine";
import { seed_library } from "./helpers";

test("home allowance shows all windows and honest phone setup", async ({ page }) => {
	await seed_library(page, [personal_routine]);
	await page.goto("/?routine=home-distraction-allowance");
	await expect(page.getByRole("heading", { name: "Home distraction allowance", exact: true })).toBeVisible();
	await page.getByRole("button", { name: "Edit Home screen-time allowance", exact: true }).click();
	const groups = page.locator(".allowance-rule");
	await expect(groups).toHaveCount(3);
	await expect(groups.nth(0).getByRole("heading", { name: "Mon, Tue, Wed, Thu", exact: true })).toBeVisible();
	await expect(groups.nth(0).getByLabel("Daily allowance")).toHaveValue("30");
	await expect(groups.nth(0).getByLabel("Group 1 window 1 starts")).toHaveValue("18:00");
	await expect(groups.nth(0).getByLabel("Group 1 window 2 ends")).toHaveValue("20:50");
	await expect(groups.nth(1).getByRole("heading", { name: "Fri", exact: true })).toBeVisible();
	await expect(groups.nth(1).getByLabel("Daily allowance")).toHaveValue("120");
	await expect(groups.nth(2).getByRole("heading", { name: "Sun, Sat", exact: true })).toBeVisible();
	await expect(groups.nth(2).getByLabel("Daily allowance")).toHaveValue("180");
	await expect(page.getByText(/Whole-minute Screen Time checkpoints/)).toBeVisible();
	for (const width of [1440, 768, 375]) {
		await page.setViewportSize({ width, height: 1000 });
		expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
		await page.screenshot({ path: `test-results/home-policy-${width}.png`, fullPage: true });
	}
});
test("MCP refuses unauthenticated and cross-origin requests", async ({ request }) => {
	const unauthenticated = await request.post("/api/mcp", { data: { jsonrpc: "2.0", id: 1, method: "tools/list" } });
	expect(unauthenticated.status()).toBe(401);
	const same_origin = await request.post("/api/mcp", { headers: { Origin: new URL(unauthenticated.url()).origin }, data: {} });
	expect(same_origin.status()).toBe(401);
	const foreign = await request.post("/api/mcp", { headers: { Origin: "https://untrusted.example" }, data: {} });
	expect(foreign.status()).toBe(403);
});
