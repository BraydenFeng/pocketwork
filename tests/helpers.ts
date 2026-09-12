import type { Page } from "@playwright/test";
import type { AppDocument } from "../lib/document";

export const STARTER_URL = "/?tool=my-focus-space";

// Seeds the library before the page loads so specs can start inside the editor with a known tool.
export async function seed_library(page: Page, documents: AppDocument[]): Promise<void> {
	await page.addInitScript((tools) => {
		if (!localStorage.getItem("pocketwork.library.v1")) {
			localStorage.setItem("pocketwork.library.v1", JSON.stringify({ schema_version: 1, tools: tools.map((document: unknown) => ({ document, updated_at: new Date().toISOString() })) }));
		}
	}, documents);
}
