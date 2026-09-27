import { defineConfig } from "@playwright/test";

export default defineConfig({
	testDir: "./tests",
	testMatch: "**/*.spec.ts",
	fullyParallel: false,
	workers: 1,
	use: {
		baseURL: "http://127.0.0.1:3210",
		viewport: { width: 1440, height: 1000 },
		channel: process.env.PLAYWRIGHT_CHANNEL || "msedge",
		trace: "retain-on-failure",
	},
	webServer: {
		command: "npm run dev",
		url: "http://127.0.0.1:3210",
		reuseExistingServer: false,
		env: {
			NEXT_PUBLIC_SUPABASE_URL: process.env.POCKETWORK_AUTH_TEST_MODE === "unconfigured" ? "" : "https://example.supabase.co",
			NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.POCKETWORK_AUTH_TEST_MODE === "unconfigured" ? "" : "test-public-key",
			NEXT_PUBLIC_GOOGLE_ENABLED: "true",
			NEXT_PUBLIC_SUBSCRIPTIONS_ENABLED: "false",
		},
		timeout: 120_000,
	},
});
