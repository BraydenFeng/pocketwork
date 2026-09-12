"use client";

import { ArrowRight, X } from "lucide-react";
import { Button, SectionLabel } from "./ui";

export type GuideStep = "customize" | "test" | "iphone";

const steps = [
	{ id: "customize", label: "Make it yours", title: "Start with something that already works.", description: "Choose a block in the phone preview, then change its settings. Add a note or counter from Add blocks. Your draft saves automatically in this browser.", action: "Edit a block" },
	{ id: "test", label: "Try your tool", title: "Switch from arranging to actually using it.", description: "In Try it mode, start the timer, tick a task, or tap a counter. Preview actions are temporary. Screen Time blocking is simulated, not applied to your phone.", action: "Open test mode" },
	{ id: "iphone", label: "Take it to iPhone", title: "Export a tool, not a standalone app.", description: "Export saves a file for the Pocketwork iPhone app. That native app still needs to be built and installed with Xcode; there is no App Store download yet.", action: "See iPhone setup" },
] as const;

export function QuickStart({ step, on_step, on_action, on_dismiss }: {
	step: GuideStep; on_step: (step: GuideStep) => void; on_action: () => void; on_dismiss: () => void;
}) {
	const current = steps.find((entry) => entry.id === step)!;
	return <section className="quick-start" id="quick-start" aria-label="Quick start">
		<div className="guide-heading"><div><SectionLabel>QUICK START</SectionLabel><h2>Your first tool, in three steps.</h2></div><Button variant="quiet" onClick={on_dismiss} aria-label="Dismiss quick start"><X /><span>I’ll explore</span></Button></div>
		<div className="guide-layout"><ol className="guide-steps" aria-label="Quick-start steps">{steps.map((entry, index) => <li key={entry.id}><button type="button" aria-pressed={step === entry.id} aria-controls="guide-instruction" onClick={() => on_step(entry.id)}><span className="guide-number">{index + 1}</span>{entry.label}</button></li>)}</ol>
			<div className="guide-instruction" id="guide-instruction"><div aria-live="polite"><h3>{current.title}</h3><p>{current.description}</p></div><Button onClick={on_action}>{current.action}<ArrowRight /></Button></div>
		</div>
	</section>;
}
