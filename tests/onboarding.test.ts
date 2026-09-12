import { describe, expect, it } from "vitest";
import { GUIDE_KEY, load_guide_dismissed, save_guide_dismissed } from "../lib/onboarding";

describe("quick-start preference", () => {
	it("shows guidance for a new browser or an unrecognized preference", () => {
		for (const value of [null, "open", "invalid"]) {
			expect(load_guide_dismissed({ getItem: () => value, setItem: () => {} })).toBe(false);
		}
	});
	it("remembers dismissal and reopening without touching the draft", () => {
		const values = new Map([["pocketwork.document.v1", "existing draft"]]);
		const storage = { getItem: (key: string) => values.get(key) ?? null, setItem: (key: string, value: string) => { values.set(key, value); } };
		save_guide_dismissed(storage, true);
		expect(load_guide_dismissed(storage)).toBe(true);
		expect(values.get(GUIDE_KEY)).toBe("dismissed");
		save_guide_dismissed(storage, false);
		expect(load_guide_dismissed(storage)).toBe(false);
		expect(values.get("pocketwork.document.v1")).toBe("existing draft");
	});
	it("reports storage read failures with context", () => {
		expect(() => load_guide_dismissed({ getItem: () => { throw new Error("denied"); }, setItem: () => {} })).toThrow("Could not read the quick-start preference");
	});
	it("reports storage write failures with context", () => {
		expect(() => save_guide_dismissed({ getItem: () => null, setItem: () => { throw new Error("quota"); } }, true)).toThrow("Could not remember the quick-start preference");
	});
});
