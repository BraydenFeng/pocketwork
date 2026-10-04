import { new_id, referenced_groups } from "./document";
import type { AppGroup, Library, LibraryEntry } from "./library";
import { native_format_five, native_format_four } from "./release-flags";

export const TOMBSTONE_DAYS = 30;

// The newest page format every syncing phone can read; newer pages stay local drafts until the phone update ships.
function supported_format(): number { return native_format_five ? 5 : native_format_four ? 4 : 3; }

// New formats stay local until their phone reader is released, without removing the last compatible cloud copy.
export function cloud_compatible_library(local: Library, remote: Library | null): Library {
	const supported = supported_format();
	return { ...local, tools: local.tools.flatMap(entry => {
		if (entry.document.schema_version <= supported) { return [entry]; }
		const previous = remote?.tools.find(item => item.document.id === entry.document.id);
		return previous ? [previous] : [];
	}) };
}

// Two copies of a library, reconciled: the newer version of each routine wins, and a deletion newer than a routine removes it.
export function merge_libraries(local: Library, remote: Library, now: number): Library {
	const removed: Record<string, string> = {};
	for (const source of [local.removed ?? {}, remote.removed ?? {}]) {
		for (const [id, stamp] of Object.entries(source)) {
			if (!removed[id] || stamp > removed[id]) { removed[id] = stamp; }
		}
	}
	const by_id = new Map<string, LibraryEntry>();
	for (const entry of [...local.tools, ...remote.tools]) {
		const current = by_id.get(entry.document.id);
		// A page in a format that cannot sync yet stays this browser's local draft. Otherwise the newest edit wins, exactly as
		// on the phone; a page's format goes down when blocks are removed, and an older copy must not win back.
		if (current && current.document.schema_version > entry.document.schema_version && current.document.schema_version > supported_format()) { continue; }
		if (!current || entry.updated_at > current.updated_at) { by_id.set(entry.document.id, entry); }
	}
	const tools: LibraryEntry[] = [];
	for (const entry of by_id.values()) {
		const tombstone = removed[entry.document.id];
		if (tombstone && tombstone >= entry.updated_at) { continue; }
		if (tombstone) { delete removed[entry.document.id]; }
		tools.push(entry);
	}
	const horizon = new Date(now - TOMBSTONE_DAYS * 86_400_000).toISOString();
	for (const [id, stamp] of Object.entries(removed)) { if (stamp < horizon) { delete removed[id]; } }
	const merged: Library = { schema_version: 1, tools: tools.sort((left, right) => left.document.id.localeCompare(right.document.id)) };
	if (Object.keys(removed).length) { merged.removed = removed; }
	// Group-list edits are atomic so renames and deletions cannot return from an older device.
	if (local.groups_updated_at || remote.groups_updated_at) {
		const source = (local.groups_updated_at ?? "") > (remote.groups_updated_at ?? "") ? local : remote;
		merged.groups = source.groups ?? [];
		merged.groups_updated_at = source.groups_updated_at;
	} else {
		const groups = new Map<string, AppGroup>();
		const names = new Set<string>();
		for (const group of [...(local.groups ?? []), ...(remote.groups ?? [])]) {
			if (!groups.has(group.id) && !names.has(group.name.toLowerCase())) { groups.set(group.id, group); names.add(group.name.toLowerCase()); }
		}
		if (groups.size) { merged.groups = [...groups.values()].sort((a, b) => a.id.localeCompare(b.id)); }
	}
	// Groups added on two devices at once: keep any group a merged page still names, from whichever side has it.
	for (const name of tools.flatMap((entry) => referenced_groups(entry.document))) {
		const has = (merged.groups ?? []).some((group) => group.name.toLowerCase() === name.toLowerCase());
		const found = [...(local.groups ?? []), ...(remote.groups ?? [])].find((group) => group.name.toLowerCase() === name.toLowerCase());
		if (!has && found && !(merged.groups ?? []).some((group) => group.id === found.id)) { merged.groups = [...(merged.groups ?? []), found]; }
	}
	// App choices merge per group by their own stamp, so a rename on one device cannot wipe apps picked on another.
	if (merged.groups) {
		const newest = new Map<string, AppGroup>();
		for (const group of [...(local.groups ?? []), ...(remote.groups ?? [])]) {
			if (group.apps_updated_at && group.apps_updated_at > (newest.get(group.id)?.apps_updated_at ?? "")) { newest.set(group.id, group); }
		}
		merged.groups = merged.groups.map((group) => {
			const best = newest.get(group.id);
			if (!best || (group.apps_updated_at ?? "") >= (best.apps_updated_at ?? "")) { return group; }
			return { ...group, apps: best.apps, apps_updated_at: best.apps_updated_at };
		});
	}
	return merged;
}

export function same_library(left: Library, right: Library): boolean {
	return stable_stringify(normalize(left)) === stable_stringify(normalize(right));
}

// Key order differs between what the database returns and what this browser built; compare content, not order.
function stable_stringify(value: unknown): string {
	if (Array.isArray(value)) { return `[${value.map(stable_stringify).join(",")}]`; }
	if (value && typeof value === "object") {
		const entries = Object.entries(value as Record<string, unknown>).filter(([, item]) => item !== undefined).sort(([left], [right]) => left.localeCompare(right));
		return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${stable_stringify(item)}`).join(",")}}`;
	}
	return JSON.stringify(value);
}

// Signing in again: pages made while signed out join the account instead of being deleted. Pages past the limit, or a
// second home allowance, stay behind in the signed-out library (returned as leftover).
export function adopt_guest_pages(account: Library, guest: Library, limit: number, now: number): { library: Library; leftover: Library } {
	let library: Library = { ...account, tools: [...account.tools] };
	const leftover: Library = { schema_version: 1, tools: [] };
	for (const entry of [...guest.tools].sort((left, right) => right.updated_at.localeCompare(left.updated_at))) {
		if (library.tools.some((item) => item.document.id === entry.document.id)) { continue; }
		const second_allowance = Boolean(entry.document.home_allowance) && library.tools.some((item) => item.document.home_allowance);
		if (second_allowance || library.tools.length >= limit) { leftover.tools.push(entry); continue; }
		library.tools.push(entry);
		for (const name of referenced_groups(entry.document)) {
			if ((library.groups ?? []).some((group) => group.name.toLowerCase() === name.toLowerCase())) { continue; }
			const group = (guest.groups ?? []).find((item) => item.name.toLowerCase() === name.toLowerCase()) ?? { id: new_id(), name };
			library = { ...library, groups: [...(library.groups ?? []), group], groups_updated_at: new Date(now).toISOString() };
		}
	}
	if (leftover.tools.length) { leftover.groups = guest.groups; leftover.groups_updated_at = guest.groups_updated_at; }
	return { library, leftover };
}

function normalize(library: Library) {
	return { groups_updated_at: library.groups_updated_at, tools: [...library.tools].sort((left, right) => left.document.id.localeCompare(right.document.id)), removed: library.removed ?? {}, groups: [...(library.groups ?? [])].sort((left, right) => left.id.localeCompare(right.id)) };
}
