import SwiftUI

struct PrimitiveTimerView: View {
	let node: BehaviorNode
	let outputs: [String: BehaviorSignal]
	let command: (PrimitiveTimerCommand) -> Void
	private var running: Bool { outputs["running"]?.value == 1 }
	private var finished: Bool { outputs["finished"]?.value == 1 }
	private var elapsed: Double { outputs["elapsed"]?.value ?? 0 }
	private var time: String {
		let minutes = node.config.timer_mode == "stopwatch" ? elapsed : outputs["remaining"]?.value ?? node.config.value
		let seconds = Int(max(0, minutes * 60).rounded())
		return String(format: "%d:%02d", seconds / 60, seconds % 60)
	}
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(node.config.label).heading_font(17)
			Text(time).font(.system(size: 32, weight: .medium, design: .monospaced)).monospacedDigit().accessibilityIdentifier("primitive.timer." + node.id)
			Text(running ? "Running" : finished ? "Finished" : elapsed > 0 ? "Paused" : "Ready").supporting()
			ViewThatFits(in: .horizontal) { HStack { controls }; VStack(alignment: .leading, spacing: 8) { controls } }.buttonStyle(QuietButtonStyle())
		}
	}
	@ViewBuilder private var controls: some View {
			Button(running ? "Pause" : "Start") { command(PrimitiveTimerCommand(node: node.id, action: running ? "pause" : "start")) }.accessibilityIdentifier("primitive.start." + node.id)
			Button("Stop") { command(PrimitiveTimerCommand(node: node.id, action: "stop")) }.disabled(finished || !running && elapsed == 0)
			Button("Reset") { command(PrimitiveTimerCommand(node: node.id, action: "reset")) }
	}
}

struct PrimitiveSettingsView: View {
	let kind: String
	let variables: [LogicItem]
	@Binding var config: BehaviorConfig
	var body: some View {
		if kind == "variable" { Field(label: "Unit (optional)") { TextField("minutes, points…", text: Binding(get: { config.unit ?? "" }, set: { config.unit = String($0.prefix(24)) })) } }
		if kind == "change_value" {
			Picker("Variable", selection: Binding(get: { config.variable_id ?? "" }, set: { config.variable_id = $0.isEmpty ? nil : $0 })) { Text("Choose a variable").tag(""); ForEach(variables) { Text($0.title).tag($0.id) } }
			Picker("Action", selection: Binding(get: { config.change ?? "add" }, set: { config.change = $0 })) { Text("Add").tag("add"); Text("Subtract").tag("subtract"); Text("Set to").tag("set"); Text("Reset").tag("reset") }
			if config.change != "reset" { Field(label: "Amount (unless connected)") { TextField("Amount", value: $config.value, format: .number).keyboardType(.numbersAndPunctuation) } }
		}
		if kind == "elapsed_timer" {
			Picker("Mode", selection: Binding(get: { config.timer_mode ?? "countdown" }, set: { config.timer_mode = $0 })) { Text("Countdown").tag("countdown"); Text("Stopwatch").tag("stopwatch") }
			if config.timer_mode != "stopwatch" { Field(label: "Duration in minutes (unless connected)") { TextField("Minutes", value: $config.value, format: .number).keyboardType(.decimalPad) } }
			Text("Elapsed and remaining time use minutes. Stop sends Finished. Actions run when this routine is open.").supporting()
		}
		if kind == "time_window" {
			Field(label: "From · 24-hour") { TextField("18:00", text: $config.time) }
			Field(label: "Until · 24-hour") { TextField("20:00", text: Binding(get: { config.end_time ?? "20:00" }, set: { config.end_time = $0 })) }
			ForEach(1...7, id: \.self) { day in Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { config.days.contains(day) }, set: { on in if on && !config.days.contains(day) { config.days.append(day); config.days.sort() } else if !on && config.days.count > 1 { config.days.removeAll { $0 == day } } })).tint(Theme.accent) }
		}
		if kind == "record" {
			ForEach(Array((config.fields ?? BuilderRuntime.fields).enumerated()), id: \.element.id) { index, field in
				Field(label: "Field name") { TextField("Name", text: Binding(get: { (config.fields ?? BuilderRuntime.fields)[index].label }, set: { var fields = config.fields ?? BuilderRuntime.fields; fields[index].label = $0; config.fields = fields })) }
				Picker("Type", selection: Binding(get: { (config.fields ?? BuilderRuntime.fields)[index].type }, set: { var fields = config.fields ?? BuilderRuntime.fields; fields[index].type = $0; config.fields = fields })) { Text("Number").tag("number"); Text("Text").tag("text"); Text("Yes / no").tag("boolean") }
				Text("Connect the \(field.id) input to its source.").supporting()
			}
			Button("Add field") { var fields = config.fields ?? BuilderRuntime.fields; fields.append(BuilderField(id: "field_" + UUID().uuidString.prefix(8).replacingOccurrences(of: "-", with: ""), label: "Field", type: "number", required: true)); config.fields = fields }.disabled((config.fields ?? BuilderRuntime.fields).count >= 8)
		}
	}
}
