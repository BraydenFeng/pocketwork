import { document_schema, type AppDocument } from "./document";
import { requested_home_policy } from "./home-policy";

export const personal_routine: AppDocument = document_schema.parse({
	schema_version: 2, id: "home-distraction-allowance", name: "Home distraction allowance",
	description: "Your daily allowance counts only at home. Away time never counts. Set home and select distractions on your iPhone.", enabled: false,
	home_allowance: requested_home_policy,
	blocks: [
		{ id: "heading", type: "heading", title: "A little distraction. On your terms.", subtitle: "One daily allowance, shared across your windows. Away time does not count." },
		{ id: "schedule", type: "schedule", title: "Home allowance", days: [1, 2, 3, 4, 5, 6, 7], start: "00:00", end: "23:59" },
		{ id: "shield", type: "screen_time", title: "Distractions", mode: "block", groups: ["Distractions"] },
	], rules: { block_during_focus: true, notify_on_complete: false },
});
