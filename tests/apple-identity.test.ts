import { generateKeyPairSync, sign } from "node:crypto";
import { afterEach, expect, it, vi } from "vitest";
import { verify_apple_identity, apple_jwt } from "../lib/server/apple";
const pair = generateKeyPairSync("rsa", { modulusLength: 2048 });
function identity(extra = {}, key = pair.privateKey) {
	const header = Buffer.from(JSON.stringify({ alg: "RS256", kid: "test-key" })).toString("base64url");
	const body = Buffer.from(JSON.stringify({ iss: "https://appleid.apple.com", aud: "client", sub: "owner", exp: Math.floor(Date.now() / 1000) + 300, nonce: "nonce", ...extra })).toString("base64url");
	return `${header}.${body}.${sign("RSA-SHA256", Buffer.from(`${header}.${body}`), key).toString("base64url")}`;
}
function setup() {
	vi.stubEnv("APPLE_SIGNIN_CLIENT_ID", "client");
	vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json({ keys: [{ ...pair.publicKey.export({ format: "jwk" }), kid: "test-key" }] })));
}
afterEach(() => { vi.unstubAllEnvs(); vi.unstubAllGlobals(); });
it("validates Apple's signature and identity claims", async () => { setup(); await expect(verify_apple_identity(identity(), "owner", "nonce")).resolves.toBeUndefined(); });
it.each([{ sub: "other" }, { aud: "other" }, { nonce: "other" }, { exp: 1 }, { iss: "https://evil.example" }])("refuses invalid identity claims %j", async extra => {
	setup(); await expect(verify_apple_identity(identity(extra), "owner", "nonce")).rejects.toThrow();
});
it("rejects a forged signature", async () => {
	setup(); const other = generateKeyPairSync("rsa", { modulusLength: 2048 });
	await expect(verify_apple_identity(identity({}, other.privateKey), "owner", "nonce")).rejects.toThrow("could not be verified");
});
it("creates short-lived ES256 server credentials without placing the key in claims", () => {
	const keys = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
	vi.stubEnv("APP_STORE_KEY_ID", "key"); vi.stubEnv("APP_STORE_ISSUER_ID", "issuer"); vi.stubEnv("APP_STORE_PRIVATE_KEY", keys.privateKey.export({ type: "pkcs8", format: "pem" }).toString());
	const jwt = apple_jwt("APP_STORE", "appstoreconnect-v1", { bid: "bundle" });
	const claims = JSON.parse(Buffer.from(jwt.split(".")[1], "base64url").toString());
	expect(claims.exp - claims.iat).toBe(300); expect(claims).toMatchObject({ iss: "issuer", bid: "bundle" }); expect(jwt).not.toContain("PRIVATE");
});
