import { beforeEach, expect, it, vi } from "vitest";
import { call_mcp_tool } from "../lib/mcp";
import { personal_routine } from "../lib/personal-routine";
import { empty_library } from "../lib/library";
import { fetch_library, push_library, type Cloud } from "../lib/cloud";
vi.mock("../lib/cloud", () => ({ fetch_library: vi.fn(), push_library: vi.fn() }));
const cloud = {} as Cloud;
const account = { id: "owner", email: "test@example.com" };
beforeEach(() => { vi.resetAllMocks(); });
it("seeds the exact disabled routine into the authenticated account", async () => {
	vi.mocked(fetch_library).mockResolvedValue(null); vi.mocked(push_library).mockResolvedValue(true);
	await call_mcp_tool(cloud, account, "seed_home_allowance", {});
	const [, who, library] = vi.mocked(push_library).mock.calls[0];
	expect(who.id).toBe("owner");
	expect(library.tools[0].document).toEqual(personal_routine);
	expect(library.groups?.map((group) => group.name)).toEqual(["Distractions"]);
});
it("never overwrites a seeded routine after the user edits it", async () => {
	vi.mocked(fetch_library).mockResolvedValue({ library: { ...empty_library, tools: [{ document: { ...personal_routine, name: "My edits" }, updated_at: new Date().toISOString() }] }, updated_at: "revision" });
	await call_mcp_tool(cloud, account, "seed_home_allowance", {});
	expect(push_library).not.toHaveBeenCalled();
});
it("retries writes after concurrent cloud saves", async () => {
	vi.mocked(fetch_library).mockResolvedValue(null); vi.mocked(push_library).mockResolvedValueOnce(false).mockResolvedValueOnce(true);
	await call_mcp_tool(cloud, account, "seed_home_allowance", {});
	expect(fetch_library).toHaveBeenCalledTimes(2);
});
it("rejects invalid documents before writing", async () => {
	await expect(call_mcp_tool(cloud, account, "save_routine", { document: { ...personal_routine, home_allowance: { ...personal_routine.home_allowance, away_usage_counts: true } } })).rejects.toThrow();
	expect(push_library).not.toHaveBeenCalled();
});
it("describes partial-minute and geofence limits", async () => {
	const result = await call_mcp_tool(cloud, account, "get_capabilities", {});
	expect(result.content[0].text).toContain("partial minute");
	expect(result.content[0].text).toContain("150 m");
});
