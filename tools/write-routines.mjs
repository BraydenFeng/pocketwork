// Writes public/routines.pocketwork.json from lib/templates.ts so the iPhone app ships the same routines as the web editor.
import { writeFileSync } from "node:fs";
import { createServer } from "vite";

const server = await createServer({ configFile: false, logLevel: "error", server: { middlewareMode: true }, optimizeDeps: { noDiscovery: true } });
try {
	const { templates } = await server.ssrLoadModule("./lib/templates.ts");
	const routines = templates.map((template) => ({ template_id: template.id, tagline: template.tagline, document: { ...template.build(), id: template.id } }));
	writeFileSync("public/routines.pocketwork.json", JSON.stringify({ schema_version: 1, routines }, null, 2) + "\n");
	console.log(`Wrote ${routines.length} routines.`);
} finally {
	await server.close();
}
