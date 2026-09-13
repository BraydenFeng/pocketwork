import { describe, expect, it } from "vitest";
import { starter_document } from "../lib/document";
import { personal_routine } from "../lib/personal-routine";
import { home_decision } from "../lib/home-policy";
import { compile_graph, connect, graph_from_document, make_node } from "../lib/logic-graph";

describe("executable logic graphs", () => {
	it("round trips normal and home routines without changing behavior", () => {
		for (const document of [starter_document, personal_routine]) { expect(compile_graph(document, graph_from_document(document))).toEqual(document); }
	});
	it("disconnecting the timer from apps disables its blocking rule", () => {
		const graph = graph_from_document(starter_document);
		graph.connections = graph.connections.filter((edge) => edge.input !== "gate");
		expect(compile_graph(starter_document, graph).rules.block_during_focus).toBe(false);
	});
	it("wiring a new notification changes the native completion rule", () => {
		let graph = graph_from_document({ ...starter_document, rules: { block_during_focus: true, notify_on_complete: false } });
		const node = make_node("notification"); graph.nodes.push(node);
		graph = connect(graph, { from: graph.nodes.find((item) => item.kind === "timer")!.id, output: "finished", to: node.id, input: "finished" });
		expect(compile_graph(starter_document, graph).rules.notify_on_complete).toBe(true);
	});
	it("edited home budgets preserve away exclusion and outside-window blocking", () => {
		const graph = graph_from_document(personal_routine);
		graph.nodes.find((node) => node.kind === "allowance")!.policy!.rules[0].allowance_minutes = 45;
		const policy = compile_graph(personal_routine, graph).home_allowance!;
		expect(home_decision(policy, 2, "19:15", true, 35).blocked).toBe(false);
		expect(home_decision(policy, 2, "19:15", true, 45).blocked).toBe(true);
		expect(home_decision(policy, 2, "19:15", false, 45)).toMatchObject({ count_usage: false, blocked: false });
		expect(home_decision(policy, 2, "20:55", true, 0).blocked).toBe(true);
	});
	it("rejects missing home guards instead of silently changing enforcement", () => {
		const graph = graph_from_document(personal_routine); graph.connections = graph.connections.filter((edge) => edge.input !== "outside");
		expect(() => compile_graph(personal_routine, graph)).toThrow("Home allowances need");
	});
	it("rejects incompatible ports and occupied inputs", () => {
		const graph = graph_from_document(personal_routine);
		expect(() => connect(graph, { from: "home-condition", output: "present", to: "daily-allowance", input: "used" })).toThrow("do not match");
		expect(() => connect(graph, graph.connections[0])).toThrow("already connected");
	});
	it("rejects duplicate engines and forged node blocks", () => {
		const graph = graph_from_document(starter_document); graph.nodes.push(make_node("timer"));
		expect(() => compile_graph(starter_document, graph)).toThrow("one timer");
		graph.nodes.pop(); graph.nodes[0].block = { id: graph.nodes[0].id, type: "note", title: "Wrong", text: "" };
		expect(() => compile_graph(starter_document, graph)).toThrow("matching page block");
	});
});
