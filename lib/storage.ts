import { parse_document, serialize_document, type AppDocument } from "./document";

export const DRAFT_KEY = "pocketwork.document.v1";
export type DraftStorage = Pick<Storage, "getItem" | "setItem">;

export function load_draft(storage: DraftStorage): AppDocument | null {
	try {
		const raw = storage.getItem(DRAFT_KEY);
		return raw === null ? null : parse_document(raw);
	} catch (error) {
		throw new Error(`Your saved draft could not be opened. It has not been overwritten. ${error instanceof Error ? error.message : "Storage unavailable."}`);
	}
}

export function save_draft(storage: DraftStorage, document: AppDocument): void {
	try { storage.setItem(DRAFT_KEY, serialize_document(document)); }
	catch (error) { throw new Error(`Could not save to this browser. Export a backup. ${error instanceof Error ? error.message : "Storage unavailable."}`); }
}
