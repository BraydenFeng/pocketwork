import type { Library, LibraryEntry } from "./library";

export const TOMBSTONE_DAYS = 30;

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
		const groups = new Map<string, { id: string; name: string }>();
		const names = new Set<string>();
		for (const group of [...(local.groups ?? []), ...(remote.groups ?? [])]) {
			if (!groups.has(group.id) && !names.has(group.name.toLowerCase())) { groups.set(group.id, group); names.add(group.name.toLowerCase()); }
		}
		if (groups.size) { merged.groups = [...groups.values()].sort((a, b) => a.id.localeCompare(b.id)); }
	}
	return merged;
}

export function same_library(left: Library, right: Library): boolean {
	return JSON.stringify(normalize(left)) === JSON.stringify(normalize(right));
}

function normalize(library: Library) {
	return { groups_updated_at: library.groups_updated_at, tools: [...library.tools].sort((left, right) => left.document.id.localeCompare(right.document.id)), removed: library.removed ?? {}, groups: [...(library.groups ?? [])].sort((left, right) => left.id.localeCompare(right.id)) };
}
