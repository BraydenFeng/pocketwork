import readline from "node:readline";

const endpoint = process.env.POCKETWORK_MCP_URL || "http://127.0.0.1:3210/api/mcp";
const token = process.env.POCKETWORK_ACCESS_TOKEN;
if (!token) { console.error("Copy an agent connection from the signed-in Pocketwork website first."); process.exit(1); }
const url = new URL(endpoint);
if (url.protocol !== "https:" && !["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)) { console.error("Remote MCP connections require HTTPS."); process.exit(1); }
const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of input) {
	let message;
	try {
		if (line.length > 200000) { throw new Error("Request too large."); }
		message = JSON.parse(line);
		const response = await fetch(endpoint, { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", Accept: "application/json, text/event-stream" }, body: JSON.stringify(message), signal: AbortSignal.timeout(30000), redirect: "error" });
		if (!response.ok) { throw new Error(await response.text()); }
		if (response.status !== 202 && message.id !== undefined) { process.stdout.write(JSON.stringify(await response.json()) + "\n"); }
	} catch (error) {
		console.error(`Pocketwork MCP: ${error.message}`);
		if (message?.id !== undefined) { process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: message.id, error: { code: -32603, message: error.message } }) + "\n"); }
	}
}
