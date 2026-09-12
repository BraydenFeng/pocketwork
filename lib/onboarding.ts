import type { DraftStorage } from "./storage";

export const GUIDE_KEY = "pocketwork.guide.v1";

export function load_guide_dismissed(storage: DraftStorage): boolean {
	try { return storage.getItem(GUIDE_KEY) === "dismissed"; }
	catch (error) { throw new Error("Could not read the quick-start preference. Your tool is unaffected.", { cause: error }); }
}

export function save_guide_dismissed(storage: DraftStorage, dismissed: boolean): void {
	try { storage.setItem(GUIDE_KEY, dismissed ? "dismissed" : "open"); }
	catch (error) { throw new Error("Could not remember the quick-start preference. Your tool is unaffected.", { cause: error }); }
}
