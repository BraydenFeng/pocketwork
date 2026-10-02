import type { Metadata } from "next";
import "./tokens.css";
import "./globals.css";
import "./creation.css";
import "./account.css";

export const metadata: Metadata = { title: "Pocketwork", description: "Build iPhone routines that block apps, run timers, and track what you do. No code." };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
	return <html lang="en"><body>{children}</body></html>;
}
