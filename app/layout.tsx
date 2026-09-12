import type { Metadata } from "next";
import "./tokens.css";
import "./globals.css";

export const metadata: Metadata = { title: "Pocketwork — your own little routines", description: "Build iPhone routines that hold you to what you decided, from small, useful blocks. No code to maintain." };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
	return <html lang="en"><body>{children}</body></html>;
}
