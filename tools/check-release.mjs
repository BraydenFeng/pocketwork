import { existsSync, readFileSync } from "node:fs";
import { loadEnvFile } from "node:process";

try {
	for (const file of [".env", ".env.local"]) { if (existsSync(file)) { loadEnvFile(file); } }
	const required = ["NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_ANON_KEY", "SITE_URL", "PUBLIC_PUBLISHER_NAME", "PUBLIC_SUPPORT_EMAIL", "SUPABASE_SERVICE_ROLE_KEY", "APPLE_SIGNIN_CLIENT_ID", "APPLE_SIGNIN_ISSUER_ID", "APPLE_SIGNIN_KEY_ID", "APPLE_SIGNIN_PRIVATE_KEY", "APP_STORE_ISSUER_ID", "APP_STORE_KEY_ID", "APP_STORE_PRIVATE_KEY", "APP_STORE_BUNDLE_ID", "APP_STORE_PRODUCT_ID"];
	const missing = required.filter(name => !process.env[name]?.trim());
	const issues = missing.map(name => `${name} is missing`);
	if (process.env.SITE_URL && !/^https:\/\/[^\s/]+\/?$/.test(process.env.SITE_URL)) { issues.push("SITE_URL must be a public HTTPS origin"); }
	if (process.env.PUBLIC_SUPPORT_EMAIL && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(process.env.PUBLIC_SUPPORT_EMAIL)) { issues.push("PUBLIC_SUPPORT_EMAIL is invalid"); }
	if (process.env.APP_STORE_ENVIRONMENT !== "Production") { issues.push("App Store environment is not Production"); }
	if (process.env.NEXT_PUBLIC_SUBSCRIPTIONS_ENABLED !== "true") { issues.push("Subscriptions are not enabled for the launch website"); }
	if (process.env.NEXT_PUBLIC_NATIVE_FORMAT4_ENABLED !== "true") { issues.push("Format-4 sync is still held back pending the phone release"); }
	if (!readFileSync("ios/project.yml", "utf8").includes("PrivacyInfo.xcprivacy")) { issues.push("Native privacy manifest resource is missing"); }
	if (issues.length) { console.error("Release configuration is NOT ready:\n" + issues.map(issue => `- ${issue}`).join("\n")); process.exitCode = 1; }
	else { console.log("Configuration is present. This does not verify Apple approval, credentials, live SQL policies, device behavior, or purchase/deletion flows. Complete RELEASE.md before submission."); }
} catch (error) { console.error("Release preflight failed:", error instanceof Error ? error.message : "Unknown error"); process.exitCode = 1; }
