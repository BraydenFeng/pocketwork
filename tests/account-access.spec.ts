import { expect, test } from "@playwright/test";
import { starter_document } from "../lib/document";
import { seed_library } from "./helpers";

const unconfigured = process.env.POCKETWORK_AUTH_TEST_MODE === "unconfigured";

test("account entry remains visible and local pages survive dismissing it", async ({ page }) => {
	await seed_library(page, [starter_document]);
	for (const width of [1440, 768, 375]) {
		await page.setViewportSize({ width, height: 1000 });
		await page.goto("/");
		await expect(page.getByRole("link", { name: "Create account", exact: true })).toBeVisible();
		await expect(page.getByRole("link", { name: "Sign in", exact: true })).toBeVisible();
		await page.screenshot({ path: `test-results/account-home-${width}.png`, fullPage: true });
		await page.getByRole("link", { name: "Create account", exact: true }).click();
		await expect(page.getByRole("heading", { name: "Create your account", exact: true })).toBeVisible();
		await expect(page.getByText("Your first sign-in creates your Pocketwork account. No separate password needed.")).toBeVisible();
		const apple = page.getByRole("button", { name: "Continue with Apple" });
		await expect(apple).toBeVisible();
		if (unconfigured) {
			await expect(apple).toBeDisabled();
			await expect(page.getByRole("status")).toContainText("Account access is unavailable");
		} else { await expect(apple).toBeEnabled(); }
		expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
		expect(await page.locator("main").ariaSnapshot()).toContain("Continue without an account");
		const contrast = await page.evaluate(() => {
			const canvas = document.createElement("canvas"); canvas.width = 1; canvas.height = 1;
			const context = canvas.getContext("2d", { willReadFrequently: true })!;
			function light(color: string) {
				context.clearRect(0, 0, 1, 1); context.fillStyle = color; context.fillRect(0, 0, 1, 1);
				const values = [...context.getImageData(0, 0, 1, 1).data].slice(0, 3).map(value => { const channel = value / 255; return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4; });
				return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722;
			}
			return [...document.querySelectorAll(".legal-page p, .legal-page a, .legal-page button:not(:disabled)")].map(element => {
				const style = getComputedStyle(element);
				const background = element.tagName === "BUTTON" ? style.backgroundColor : getComputedStyle(document.body).backgroundColor;
				const values = [light(style.color), light(background)].sort((a, b) => b - a);
				return { text: element.textContent, ratio: (values[0] + 0.05) / (values[1] + 0.05) };
			});
		});
		for (const result of contrast) { expect(result.ratio, result.text ?? "Account text contrast").toBeGreaterThanOrEqual(4.5); }
		await apple.focus();
		if (!unconfigured) { await expect(apple).toBeFocused(); }
		await page.screenshot({ path: `test-results/account-create-${unconfigured ? "unavailable" : "ready"}-${width}.png`, fullPage: true });
		await page.getByRole("link", { name: "Sign in", exact: true }).click();
		await expect(page.getByRole("heading", { name: "Sign in to Pocketwork" })).toBeVisible();
		await page.getByRole("link", { name: "Continue without an account" }).click();
		await expect(page.getByRole("button", { name: "Open My focus space", exact: true })).toBeVisible();
	}
});

test("cancelled OAuth explains the failure and allows another attempt", async ({ page }) => {
	test.skip(unconfigured, "No provider can start without configuration.");
	await page.route("https://example.supabase.co/auth/v1/authorize**", async route => {
		const url = new URL(route.request().url());
		expect(url.searchParams.get("provider")).toBe("apple");
		const destination = new URL(url.searchParams.get("redirect_to")!);
		expect(destination.pathname).toBe("/account");
		destination.hash = "error=access_denied&error_description=Cancelled";
		await route.fulfill({ status: 302, headers: { location: destination.href } });
	});
	await page.goto("/account?mode=create");
	await page.getByRole("button", { name: "Continue with Apple" }).click();
	await expect(page.locator(".account-error[role=alert]")).toBeVisible();
	await expect(page.getByRole("button", { name: "Continue with Apple" })).toBeEnabled();
	await expect(page.getByRole("link", { name: "Continue without an account" })).toBeVisible();
});

test("Google routes through the configured provider without creating a local account", async ({ page }) => {
	test.skip(unconfigured, "No provider can start without configuration.");
	await page.route("https://example.supabase.co/auth/v1/authorize**", async route => {
		expect(new URL(route.request().url()).searchParams.get("provider")).toBe("google");
		await route.fulfill({ contentType: "text/html", body: "<p>Test provider handoff</p>" });
	});
	await page.goto("/account?mode=signin");
	await page.getByRole("button", { name: "Continue with Google" }).click();
	await expect(page.getByText("Test provider handoff")).toBeVisible();
});

test("a simulated successful sign-in syncs guest pages into the account", async ({ page }) => {
	test.skip(unconfigured, "No provider can start without configuration.");
	const user_id = "11111111-1111-4111-8111-111111111111";
	const user = { id: user_id, aud: "authenticated", role: "authenticated", email: "test@example.com", app_metadata: { provider: "apple", providers: ["apple"] }, user_metadata: {}, created_at: "2026-09-26T00:00:00Z" };
	const expires_at = Math.floor(Date.now() / 1000) + 3600;
	const token = [Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url"), Buffer.from(JSON.stringify({ sub: user_id, exp: expires_at })).toString("base64url"), "test-signature"].join(".");
	let saved: { user_id: string; library: { tools: { document: { name: string } }[] } } | null = null;
	await page.route("https://example.supabase.co/**", async route => {
		const url = new URL(route.request().url());
		if (url.pathname === "/auth/v1/authorize") {
			const destination = new URL(url.searchParams.get("redirect_to")!);
			destination.hash = new URLSearchParams({ access_token: token, refresh_token: "test-refresh-token", expires_in: "3600", token_type: "bearer", type: "signup" }).toString();
			await route.fulfill({ status: 302, headers: { location: destination.href } });
		} else if (url.pathname === "/auth/v1/user") { await route.fulfill({ json: user }); }
		else if (url.pathname === "/rest/v1/libraries" && route.request().method() === "GET") { await route.fulfill({ json: saved ? [{ ...saved, updated_at: "2026-09-26T00:00:00Z" }] : [] }); }
		else if (url.pathname === "/rest/v1/libraries" && route.request().method() === "POST") {
			saved = route.request().postDataJSON();
			await route.fulfill({ json: [{ user_id }] });
		} else if (url.pathname === "/rest/v1/routine_status") { await route.fulfill({ json: [] }); }
		else { throw new Error(`Unexpected auth fixture request: ${route.request().method()} ${url.pathname}`); }
	});
	await seed_library(page, [starter_document]);
	await page.goto("/");
	await page.getByRole("link", { name: "Create account", exact: true }).click();
	await page.getByRole("button", { name: "Continue with Apple" }).click();
	await expect(page.getByText("test@example.com", { exact: true })).toBeVisible();
	await page.getByRole("link", { name: "← My pages" }).click();
	await expect(page.locator(".save-status")).toContainText("synced to test@example.com");
	await expect(page.getByRole("button", { name: "Open My focus space", exact: true })).toBeVisible();
	await expect(page.getByRole("link", { name: "Create account", exact: true })).toHaveCount(0);
	expect(saved).toMatchObject({ user_id, library: { tools: [{ document: { name: "My focus space" } }] } });
});
