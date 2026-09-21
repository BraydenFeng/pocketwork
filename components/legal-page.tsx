import type { ReactNode } from "react";

export function LegalPage({ title, children }: { title: string; children: ReactNode }) {
	return <main className="legal-page"><nav aria-label="Workspace"><a href="/">← My pages</a><a href="/account">Account</a></nav><h1>{title}</h1>{children}<footer><a href="/privacy">Privacy</a><a href="/terms">Terms</a><a href="/support">Support</a></footer></main>;
}
