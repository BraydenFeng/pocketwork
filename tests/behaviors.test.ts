import { describe, expect, it } from "vitest";
import fixtures from "../ios/PocketworkTests/behavior-fixtures.json";
import { behavior_order, behaviors_schema, initial_behaviors, run_behaviors, behavior_config_schema } from "../lib/behaviors";
import { compile_graph, graph_from_document, make_node, connect } from "../lib/logic-graph";
import { starter_document, document_schema } from "../lib/document";

describe("connected behavior runtime", () => {
	for (const fixture of fixtures) { it(fixture.name, () => {
		const graph = behaviors_schema.parse(fixture.graph); let state = initial_behaviors();
		for (const step of fixture.steps as { now: number; location?: boolean; usage?: number; tap?: string; values?: Record<string, number>; messages: number }[]) { const result = run_behaviors(graph, state, { now: step.now*1000, at_location: step.location, usage_minutes: step.usage, tap: step.tap }); state = result.state; expect(result.effects).toHaveLength(step.messages); for (const [id,value] of Object.entries(step.values ?? {})) { expect(state.values[id]).toBe(value); } }
	}); }
	it("counts one streak day, survives serialization, and restarts after a gap", () => {
		const config = behavior_config_schema.parse({}); const graph = behaviors_schema.parse({ nodes: [{ id:"tap",kind:"check_in",x:0,y:0,config },{ id:"streak",kind:"streak",x:0,y:0,config }], connections:[{from:"tap",output:"done",to:"streak",input:"check_in"}] });
		let state = initial_behaviors();
		for (const [day,expected] of [[1,1],[1,1],[2,2],[4,1]]) { const result = run_behaviors(graph, JSON.parse(JSON.stringify(state)), { now: new Date(2026,8,day,12).getTime(),tap:"tap" }); state=result.state; expect(result.signals.streak.days.value).toBe(expected); }
	});
	it("rejects cycles, numeric-to-boolean wiring and missing required inputs", () => {
		const config = behavior_config_schema.parse({});
		const graph = behaviors_schema.parse({nodes:[{id:"a",kind:"not",x:0,y:0,config},{id:"b",kind:"not",x:0,y:0,config}],connections:[{from:"a",output:"result",to:"b",input:"condition"},{from:"b",output:"result",to:"a",input:"condition"}]});
		expect(() => behavior_order(graph,{},true)).toThrow("loop"); graph.connections=[]; expect(() => behavior_order(graph,{},true)).toThrow("input first");
		graph.connections=[{from:"source",output:"value",to:"a",input:"condition"}]; expect(() => behavior_order(graph,{source:{value:"number"}})).toThrow("same value type");
	});
	it("persists new nodes and connections with format 3 without changing existing blocking", () => {
		let graph=graph_from_document(starter_document); const button=make_node("button"), counter=make_node("count"); graph.nodes.push(button,counter); graph=connect(graph,{from:button.id,output:"pressed",to:counter.id,input:"increment"});
		const document=compile_graph(starter_document,graph); expect(document.schema_version).toBe(3); expect(document.rules).toEqual(starter_document.rules); expect(graph_from_document(document).nodes.find(n=>n.id===counter.id)).toMatchObject({kind:"count"});
		const invalid=structuredClone(document); invalid.behaviors!.connections=[]; expect(document_schema.safeParse(invalid).success).toBe(false);
	});
});
