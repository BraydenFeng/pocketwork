import Charts
import SwiftUI

struct BuilderNodeView: View {
	let node: BehaviorNode
	let state: BuilderState?
	let outputs: [String: BehaviorSignal]
	let input: (BuilderValue) -> Void
	let submit: ([String: BuilderValue]) -> Void
	var body: some View {
		Group {
			switch node.kind {
			case "number_input", "text_input", "checkbox", "form": BuilderInputView(node: node, saved: state?.inputs[node.id], record: state?.forms[node.id], input: input, submit: submit)
			case "table", "chart": BuilderDataView(node: node, rows: outputs["rows"]?.rows ?? [])
			case "progress":
				VStack(alignment: .leading, spacing: 8) { Text(node.config.label).heading_font(15); ProgressView(value: max(0,min(1,outputs["fraction"]?.value ?? 0))).tint(Theme.accent); Text(outputs["value"]?.available == false ? "Unavailable" : "\((outputs["value"]?.value ?? 0).formatted()) / \(node.config.value.formatted())").supporting() }
			case "health", "aggregate", "calculate":
				HStack { Text(node.config.label).heading_font(15); Spacer(); Text(outputs["value"]?.available == false || outputs["value"] == nil ? "Unavailable" : (outputs["value"]?.value ?? 0).formatted()).supporting() }
			case "app_gate": HStack { Text(node.config.label).heading_font(15); Spacer(); Text(outputs["active"]?.available == false || outputs["active"] == nil ? "Waiting for data" : outputs["active"]?.value == 1 ? "Closed" : "Open").supporting() }
			default: EmptyView()
			}
		}
	}
}
private struct BuilderInputView: View {
	let node: BehaviorNode
	let saved: BuilderValue?
	let record: [String: BuilderValue]?
	let input: (BuilderValue) -> Void
	let submit: ([String: BuilderValue]) -> Void
	@State private var text = ""
	@State private var values: [String: String] = [:]
	@State private var checks: [String: Bool] = [:]
	@State private var error: String?
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			if node.kind == "checkbox" {
				Toggle(node.config.label, isOn: Binding(get: { if case .boolean(let value) = saved { return value }; return false }, set: { input(.boolean($0)) })).tint(Theme.accent)
			} else if node.kind == "form" {
				Text(node.config.label).heading_font(17)
				ForEach(node.config.fields ?? BuilderRuntime.fields) { field in
					if field.type == "boolean" { Toggle(field.label, isOn: Binding(get: { checks[field.id] ?? false }, set: { checks[field.id] = $0 })).tint(Theme.accent) }
					else { Field(label: field.label + (field.required ? " *" : "")) { TextField(field.label, text: Binding(get: { values[field.id] ?? "" }, set: { values[field.id] = String($0.prefix(240)) })).keyboardType(field.type == "number" ? .numbersAndPunctuation : .default).accessibilityIdentifier("builder.field." + field.id) } }
				}
				Button("Submit " + node.config.label) { submit_form() }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("builder.submit." + node.id)
			} else {
				Field(label: node.config.label) { TextField(node.config.label, text: $text).keyboardType(node.kind == "number_input" ? .numbersAndPunctuation : .default).accessibilityIdentifier("builder.input." + node.id) }
				Button("Set value") { if node.kind == "number_input" { guard let value = Double(text), value.isFinite, abs(value) <= 1000000 else { error = "Enter a number between -1,000,000 and 1,000,000."; return }; error = nil; input(.number(value)) } else { error = nil; input(.text(String(text.prefix(240)))) } }.buttonStyle(QuietButtonStyle())
			}
			if let error { Text(error).foregroundStyle(Theme.danger).font(.system(size: 13)) }
		}.onAppear {
			text = saved?.display ?? (node.kind == "number_input" ? String(node.config.value) : node.config.text ?? "")
			for (key, value) in record ?? [:] { if case .boolean(let flag) = value { checks[key] = flag } else { values[key] = value.display } }
		}
	}
	private func submit_form() {
		var result: [String: BuilderValue] = [:]
		for field in node.config.fields ?? BuilderRuntime.fields {
			if field.type == "boolean" { result[field.id] = .boolean(checks[field.id] ?? false); continue }
			let value = values[field.id] ?? ""
			if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { if field.required { error = "Fill in " + field.label + "."; return }; continue }
			if field.type == "number" { guard let number = Double(value), number.isFinite, abs(number) <= 1000000 else { error = "Enter a valid number for " + field.label + "."; return }; result[field.id] = .number(number) }
			else { result[field.id] = .text(String(value.prefix(240))) }
		}
		error = nil; submit(result)
	}
}
private struct BuilderDataView: View {
	let node: BehaviorNode
	let rows: [BuilderEntry]
	private var columns: [String] { Array(Set(rows.flatMap { $0.values.keys })).sorted() }
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(node.config.label).heading_font(17)
			if rows.isEmpty { Text("No entries yet.").supporting() }
			else {
				if node.kind == "chart" {
					Chart(Array(rows.suffix(50))) { row in if let value = row.values[node.config.field ?? "value"]?.number { LineMark(x: .value("Time", Date(timeIntervalSince1970: row.at / 1000)), y: .value("Value", value)).foregroundStyle(Theme.accent); PointMark(x: .value("Time", Date(timeIntervalSince1970: row.at / 1000)), y: .value("Value", value)).foregroundStyle(Theme.accent) } }.frame(height: 160).accessibilityLabel(node.config.label)
				}
				ScrollView(.horizontal) {
					Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
						GridRow { Text("Time").fontWeight(.semibold); ForEach(columns, id: \.self) { Text($0).fontWeight(.semibold) } }
						ForEach(Array(rows.suffix(20))) { row in GridRow { Text(Date(timeIntervalSince1970: row.at / 1000), format: .dateTime.month().day().hour().minute()); ForEach(columns, id: \.self) { Text(row.values[$0]?.display ?? "") } } }
					}.font(.system(size: 12)).foregroundStyle(Theme.text_dim)
				}
				Text("\(rows.count) entries · latest 200 kept on this device").supporting()
			}
		}
	}
}
