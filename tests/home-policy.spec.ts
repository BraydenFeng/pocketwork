import { expect, test } from "@playwright/test";
import { personal_routine } from "../lib/personal-routine";
import { seed_library } from "./helpers";

test("home allowance shows all windows and honest phone setup", async ({ page }) => {
	await seed_library(page, [personal_routine]);
	await page.goto("/?routine=home-distraction-allowance");
	await expect(page.getByRole("heading", { name: "Home distraction allowance", exact: true })).toBeVisible();
	await expect(page.getByText("Mon, Tue, Wed, Thu: 30 minutes total")).toBeVisible();
	await expect(page.getByText("18:00–18:30 and 19:00–20:50")).toBeVisible();
	await expect(page.getByText("Fri: 120 minutes total")).toBeVisible();
	await expect(page.getByText("Sun, Sat: 180 minutes total")).toBeVisible();
	await expect(page.getByText(/partial minute uncounted/)).toBeVisible();
	for (const width of [1440, 768, 375]) {
		await page.setViewportSize({ width, height: 1000 });
		expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
		await page.screenshot({ path: `test-results/home-policy-${width}.png`, fullPage: true });
	}
});
test("MCP refuses unauthenticated and cross-origin requests", async ({ request }) => {
	const unauthenticated = await request.post("/api/mcp", { data: { jsonrpc: "2.0", id: 1, method: "tools/list" } });
	expect(unauthenticated.status()).toBe(401);
	const foreign = await request.post("/api/mcp", { headers: { Origin: "https://untrusted.example" }, data: {} });
	expect(foreign.status()).toBe(403);
});
