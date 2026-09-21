import type { Library } from "./library";

export const FREE_PAGES = 3;
export const PRO_PAGES = 50;
export type PagePlan = { pro: boolean; expires_at: string | null; configured: boolean };
export const free_plan: PagePlan = { pro: false, expires_at: null, configured: false };

export function assert_page_limit(previous: Library, next: Library, pro: boolean): void {
	const limit = pro ? PRO_PAGES : FREE_PAGES;
	const old_ids = new Set(previous.tools.map(entry => entry.document.id));
	if (next.tools.length > limit && next.tools.some(entry => !old_ids.has(entry.document.id))) {
		throw new Error(pro ? "This workspace supports up to 50 pages." : "Your free plan holds 3 pages. Delete a page to make room, or upgrade in the iPhone app. Your existing pages are still available.");
	}
}

export function plan_active(plan: PagePlan, now = Date.now()): boolean {
	return plan.pro && plan.expires_at !== null && Date.parse(plan.expires_at) > now;
}
