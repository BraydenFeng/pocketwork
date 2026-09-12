import type { Metadata } from "next";
import "./tokens.css";
import "./globals.css";

export const metadata: Metadata = { title: "Pocketwork — your personal app workbench", description: "Build personal iPhone tools from small, useful blocks. No AI credits. No code to maintain." };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
	return <html lang="en"><body>{children}</body></html>;
}
