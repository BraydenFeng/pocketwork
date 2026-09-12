"use client";

import { useEffect, useState, type ButtonHTMLAttributes, type ReactNode } from "react";

export function Button({ children, variant = "default", className = "", ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: "default" | "primary" | "quiet" | "danger" }) {
	return <button type="button" className={`button button-${variant} ${className}`} {...props}>{children}</button>;
}

export function SectionLabel({ number, children }: { number?: string; children: ReactNode }) {
	return <div className="section-label">{number && <span className="section-number">{number}</span>}{children}</div>;
}

export function TextField({ label, value, on_commit, multiline = false, max_length = 80, required = false }: {
	label: string; value: string; on_commit: (value: string) => void; multiline?: boolean; max_length?: number; required?: boolean;
}) {
	const [draft, set_draft] = useState(value);
	const [invalid, set_invalid] = useState(false);
	useEffect(() => { set_draft(value); set_invalid(false); }, [value]);
	function commit() {
		if (required && !draft.trim()) { set_invalid(true); return; }
		set_invalid(false); on_commit(required ? draft.trim() : draft);
	}
	const props = { value: draft, maxLength: max_length, "aria-invalid": invalid, onChange: (event: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => set_draft(event.target.value), onBlur: commit };
	return <label className="field-label"><span>{label}</span>{multiline
		? <textarea className="field textarea" rows={3} {...props} />
		: <input className="field" {...props} onKeyDown={(event) => { if (event.key === "Enter") { event.currentTarget.blur(); } }} />}
		{invalid && <span className="field-error" role="alert">This field cannot be empty.</span>}
	</label>;
}

export function Toggle({ label, description, checked, disabled, on_change }: {
	label: string; description: string; checked: boolean; disabled?: boolean; on_change: (value: boolean) => void;
}) {
	return <label className={`toggle-row ${disabled ? "is-disabled" : ""}`}>
		<span><span className="toggle-title">{label}</span><span className="supporting">{description}</span></span>
		<input type="checkbox" role="switch" checked={checked} disabled={disabled} onChange={(event) => on_change(event.target.checked)} />
	</label>;
}
