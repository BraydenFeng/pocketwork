import SwiftUI

struct LogicEditorView: View {
	@Binding var document: AppDocument
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var library: LibraryController
	@State private var graph: LogicEditing
	@State private var palette = false
	@State private var search = ""
	@State private var inspector: LogicSelection?
	@State private var port: LogicPortSelection?
	@State private var failure: String?
	@State private var discard = false
	@State private var zoom = 1.0
	@State private var drag_start: CGPoint?
	@State private var focus: String?
	private let original: AppDocument
	private let initial: LogicEditing

	init(document: Binding<AppDocument>) {
		_document = document
		original = document.wrappedValue
		let graph = LogicEditing(document: document.wrappedValue)
		initial = graph; _graph = State(initialValue: graph)
	}
	private var width: Double { max(800, (graph.nodes.map { position($0).x + 290 }.max() ?? 0)) }
	private var height: Double { max(700, (graph.nodes.map { position($0).y + $0.height + 60 }.max() ?? 0)) }
	private func position(_ node: LogicItem) -> CGPoint {
		let min_x = min(0, graph.nodes.map(\.x).min() ?? 0); let min_y = min(0, graph.nodes.map(\.y).min() ?? 0)
		return CGPoint(x: min(16000, max(0, node.x - min_x)), y: min(16000, max(0, node.y - min_y)))
	}
	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				HStack {
					Text("\(graph.nodes.count) blocks · \(graph.connections.count) connections").mono_caption()
					Spacer()
					Menu { ForEach(graph.nodes) { node in Button(node.title) { focus = node.id } } } label: { Image(systemName: "scope").frame(width: 44, height: 44) }.accessibilityLabel("Find a block")
				}.padding(.horizontal, Theme.pad)
				Hairline()
				canvas
				Hairline()
				Text(graph.nodes.isEmpty ? "Add a block to start building." : "Drag a heading to move it. Tap a port to connect.").supporting().padding(12)
				EditorBar {
					Button { palette = true } label: { Label("Add block", systemImage: "plus") }.buttonStyle(TextButtonStyle()).frame(minHeight: 44).accessibilityIdentifier("logic.add")
					Spacer()
					Button { zoom = max(0.5, zoom - 0.25) } label: { Image(systemName: "minus.magnifyingglass").frame(width: 44, height: 44) }.accessibilityLabel("Zoom out")
					Button("\(Int(zoom * 100))%") { zoom = 1 }.font(.system(size: 12, design: .monospaced)).accessibilityLabel("Reset zoom")
					Button { zoom = min(1.5, zoom + 0.25) } label: { Image(systemName: "plus.magnifyingglass").frame(width: 44, height: 44) }.accessibilityLabel("Zoom in")
				}
			}.paper_page().navigationTitle("Logic").navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { Button("Back") { if graph != initial { discard = true } else { dismiss() } } }
				ToolbarItem(placement: .confirmationAction) { Button("Apply") { apply() }.fontWeight(.semibold).accessibilityIdentifier("logic.apply") }
			}
			.sheet(isPresented: $palette) { block_library }
			.sheet(item: $inspector) { selected in settings(selected.id) }
			.sheet(item: $port) { selected in connections(selected) }
			.interactiveDismissDisabled(graph != initial)
			.confirmationDialog("Discard logic changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard changes", role: .destructive) { dismiss() }; Button("Keep editing", role: .cancel) {} }
			.alert("Check this connection", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) { Button("OK") { failure = nil } } message: { Text(failure ?? "") }
		}
	}
	private var canvas: some View {
		ScrollViewReader { proxy in
			ScrollView([.horizontal, .vertical]) {
				ZStack(alignment: .topLeading) {
					Canvas { context, size in
						for edge in graph.connections {
							guard let from = graph.nodes.first(where: { $0.id == edge.from }), let to = graph.nodes.first(where: { $0.id == edge.to }) else { continue }
							let a = endpoint(from, edge.output, output: true), b = endpoint(to, edge.input, output: false)
							var path = Path(); path.move(to: a); let bend = max(60, abs(b.x - a.x) / 2)
							path.addCurve(to: b, control1: CGPoint(x: a.x + bend, y: a.y), control2: CGPoint(x: b.x - bend, y: b.y))
							context.stroke(path, with: .color(Theme.accent.opacity(0.65)), lineWidth: 2)
						}
					}.allowsHitTesting(false).accessibilityHidden(true)
					ForEach(graph.nodes) { node in card(node).frame(width: 248, height: node.height).offset(x: position(node).x, y: position(node).y).id(node.id) }
				}.frame(width: width, height: height, alignment: .topLeading)
					.scaleEffect(zoom, anchor: .topLeading).frame(width: width * zoom, height: height * zoom, alignment: .topLeading)
			}.background {
				Canvas { context, size in
					for x in stride(from: CGFloat(16), to: size.width, by: 24) { for y in stride(from: CGFloat(16), to: size.height, by: 24) { context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(Theme.border)) } }
				}.allowsHitTesting(false).accessibilityHidden(true)
			}.background(Theme.bg).accessibilityIdentifier("logic.canvas")
			.onChange(of: focus) { _, id in if let id { withAnimation { proxy.scrollTo(id, anchor: .center) }; focus = nil } }
		}
	}
	private func endpoint(_ node: LogicItem, _ name: String, output: Bool) -> CGPoint {
		let keys = (output ? node.outputs : node.inputs).keys.sorted()
		return CGPoint(x: position(node).x + (output ? 248 : 0), y: position(node).y + 66 + Double(keys.firstIndex(of: name) ?? 0) * 44 + 22)
	}
	private func card(_ node: LogicItem) -> some View {
		VStack(spacing: 0) {
			HStack(spacing: 8) {
				VStack(alignment: .leading, spacing: 3) { Text(LogicEditing.title(node.kind)).mono_caption(); Text(node.title).font(.system(size: 15, weight: .semibold)).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
					.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 8).onChanged { value in
						guard let index = graph.nodes.firstIndex(where: { $0.id == node.id }) else { return }
						if drag_start == nil { drag_start = CGPoint(x: graph.nodes[index].x, y: graph.nodes[index].y) }
						graph.nodes[index].x = max(0, min(15000, Double(drag_start!.x + value.translation.width / zoom)))
						graph.nodes[index].y = max(0, min(15000, Double(drag_start!.y + value.translation.height / zoom)))
					}.onEnded { _ in drag_start = nil })
				Button { inspector = LogicSelection(id: node.id) } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Edit \(node.title)").accessibilityIdentifier("logic.edit.\(node.id)")
			}.padding(.horizontal, 12).frame(height: 65)
			Hairline()
			HStack(alignment: .top, spacing: 0) {
				VStack(alignment: .leading, spacing: 0) { ForEach(node.inputs.keys.sorted(), id: \.self) { name in port_button(node, name, output: false) } }
				Spacer(minLength: 0)
				VStack(alignment: .trailing, spacing: 0) { ForEach(node.outputs.keys.sorted(), id: \.self) { name in port_button(node, name, output: true) } }
			}
			Spacer(minLength: 0)
		}.background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius_small)).overlay(RoundedRectangle(cornerRadius: Theme.radius_small).strokeBorder(Theme.border)).foregroundStyle(Theme.text)
	}
	private func port_button(_ node: LogicItem, _ name: String, output: Bool) -> some View {
		Button { port = LogicPortSelection(node: node.id, name: name, output: output) } label: {
			HStack(spacing: 5) {
				if !output { Circle().fill(Theme.accent).frame(width: 10, height: 10) }
				Text(name.replacingOccurrences(of: "_", with: " ")).font(.system(size: 12)).lineLimit(1)
				if output { Circle().fill(Theme.accent).frame(width: 10, height: 10) }
			}.padding(.horizontal, 5).frame(minHeight: 44)
		}.buttonStyle(.plain).accessibilityLabel("\(node.title), \(name), \(output ? "output" : "input")").accessibilityIdentifier("logic.port.\(node.id).\(name)")
	}
	private var block_library: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					ForEach(LogicEditing.sections, id: \.title) { section in
						let kinds = section.kinds.filter { search.isEmpty || LogicEditing.title($0).localizedCaseInsensitiveContains(search) || section.title.localizedCaseInsensitiveContains(search) }
						if !kinds.isEmpty { DisclosureGroup(isExpanded: Binding(get: { !search.isEmpty || expanded.contains(section.title) }, set: { if $0 { expanded.insert(section.title) } else { expanded.remove(section.title) } })) {
							ForEach(kinds, id: \.self) { kind in Button { add(kind) } label: { HStack { Text(LogicEditing.title(kind)); Spacer(); Image(systemName: "plus") }.frame(minHeight: 48).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("logic.add.\(kind)").disabled(BehaviorGraph.ports[kind] == nil && graph.nodes.contains { $0.kind == kind }) }
						} label: { Text(section.title).heading_font(17).padding(.vertical, 8) }; Hairline() }
					}
					if graph.nodes.contains(where: { $0.kind == "usage" || $0.kind == "allowance" }), !graph.nodes.contains(where: { $0.kind == "home" }) { Button("Add allowance location") { add("home") }.buttonStyle(QuietButtonStyle()) }
				}.padding(Theme.pad)
			}.paper_page().searchable(text: $search, prompt: "Find a block").navigationTitle("Add block").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { palette = false } } }
		}.presentationDetents([.large])
	}
	@State private var expanded = Set<String>()
	private func add(_ kind: String) {
		do { focus = try graph.add(kind); search = ""; palette = false } catch { palette = false; failure = error.localizedDescription }
	}
	private func connections(_ selected: LogicPortSelection) -> some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 12) {
					Text("\(graph.nodes.first { $0.id == selected.node }?.title ?? "Block") · \(selected.name)").heading_font(20)
					Text(selected.output ? "Choose an input to connect to." : "Choose the output that supplies this input.").supporting()
					ForEach(Array(graph.connections.enumerated()).filter { _, edge in selected.output ? edge.from == selected.node && edge.output == selected.name : edge.to == selected.node && edge.input == selected.name }, id: \.offset) { _, edge in
						HStack { Text(edge_label(edge)).supporting(); Spacer(); Button("Disconnect", role: .destructive) { graph.connections.removeAll { $0 == edge } }.frame(minHeight: 44) }
					}
					Hairline()
					let candidates = candidates(selected)
					if candidates.isEmpty { Text("No compatible free ports. Add a matching block or disconnect the occupied input.").supporting() }
					ForEach(candidates, id: \.self) { edge in
						Button { do { try graph.connect(edge); port = nil } catch { port = nil; failure = error.localizedDescription } } label: { HStack { Text(edge_label(edge)).multilineTextAlignment(.leading); Spacer(); Image(systemName: "link") }.frame(minHeight: 48).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("logic.connect.\(edge.from).\(edge.output).\(edge.to).\(edge.input)")
					}
				}.padding(Theme.pad)
			}.paper_page().navigationTitle("Connect blocks").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { port = nil } } }
		}.presentationDetents([.medium, .large])
	}
	private func candidates(_ selected: LogicPortSelection) -> [BehaviorEdge] {
		graph.nodes.flatMap { node in (selected.output ? node.inputs : node.outputs).keys.sorted().compactMap { name in
			let edge = selected.output ? BehaviorEdge(from: selected.node, output: selected.name, to: node.id, input: name) : BehaviorEdge(from: node.id, output: name, to: selected.node, input: selected.name)
			var test = graph
			do { try test.connect(edge); return edge } catch { return nil }
		} }
	}
	private func edge_label(_ edge: BehaviorEdge) -> String { "\(graph.nodes.first { $0.id == edge.from }?.title ?? "Block") · \(edge.output) → \(graph.nodes.first { $0.id == edge.to }?.title ?? "Block") · \(edge.input)" }
	private func settings(_ id: String) -> some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					if let node = graph.nodes.first(where: { $0.id == id }) {
						if node.kind == "schedule", graph.nodes.contains(where: { $0.kind == "allowance" }) { Text("Your time windows live in Daily allowance. The schedule keeps the allowance active throughout the day.").supporting() } else if let block = node.block { BlockEditorView(block: Binding(get: { graph.nodes.first { $0.id == id }?.block ?? block }, set: { value in update(id) { $0.block = value } }), groups: library.groups, embedded: true) }
						if let config = node.config { BehaviorSettings(kind: node.kind, config: Binding(get: { graph.nodes.first { $0.id == id }?.config ?? config }, set: { value in update(id) { $0.config = value } })) }
						if let policy = node.policy {
							Text("Daily allowances").heading_font(20)
							ForEach(Array(policy.rules.enumerated()), id: \.offset) { index, rule in
								ForEach(1...7, id: \.self) { day in Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { graph.nodes.first { $0.id == id }?.policy?.rules[index].days.contains(day) ?? false }, set: { on in update(id) { item in
									if on { item.policy?.rules[index].days.append(day); item.policy?.rules[index].days.sort() } else if (item.policy?.rules[index].days.count ?? 0) > 1 { item.policy?.rules[index].days.removeAll { $0 == day } }
								} })).tint(Theme.accent) }
								HomeRuleEditor(rule: Binding(get: { graph.nodes.first { $0.id == id }?.policy?.rules[index] ?? rule }, set: { value in update(id) { $0.policy?.rules[index] = value } }))
								if rule.windows.count < 2 { Button("Add time window") { update(id) { $0.policy?.rules[index].windows.append(HomeWindow(start: "21:00", end: "22:00")) } } }
								if rule.windows.count > 1 { Button("Remove second window", role: .destructive) { update(id) { $0.policy?.rules[index].windows.removeLast() } } }
								Button("Remove day group", role: .destructive) { update(id) { $0.policy?.rules.remove(at: index) } }.disabled(policy.rules.count == 1)
								Hairline()
							}
							Button("Add day group") { update(id) { $0.policy?.rules.append(HomeDayRule(days: [1], allowance_minutes: 30, windows: [HomeWindow(start: "06:30", end: "20:30")])) } }.disabled(policy.rules.count >= 7)
						}
						if ["home", "usage"].contains(node.kind) { Text("Uses the saved location and distraction selection on this phone. Usage away from that location does not count.").supporting() }
						SectionLabel(text: "Connections")
						ForEach(node.inputs.keys.sorted(), id: \.self) { name in Button("Input · \(name)") { inspector = nil; pending_port = LogicPortSelection(node: id, name: name, output: false) }.buttonStyle(QuietButtonStyle()).frame(minHeight: 44) }
						ForEach(node.outputs.keys.sorted(), id: \.self) { name in Button("Output · \(name)") { inspector = nil; pending_port = LogicPortSelection(node: id, name: name, output: true) }.buttonStyle(QuietButtonStyle()).frame(minHeight: 44) }
						Hairline()
						Button("Delete block", role: .destructive) { graph.remove(id); inspector = nil }.frame(minHeight: 44).accessibilityIdentifier("logic.delete")
					}
				}.padding(Theme.pad)
			}.paper_page().scrollDismissesKeyboard(.interactively).navigationTitle("Block settings").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { inspector = nil } } }
		}.presentationDetents([.large]).onDisappear { if let pending = pending_port { pending_port = nil; port = pending } }
	}
	@State private var pending_port: LogicPortSelection?
	private func update(_ id: String, _ edit: (inout LogicItem) -> Void) { if let index = graph.nodes.firstIndex(where: { $0.id == id }) { edit(&graph.nodes[index]) } }
	private func apply() {
		guard document == original else { failure = "The page changed while Logic was open. Go back and reopen Logic before applying."; return }
		do { document = try graph.compile(base: original); dismiss() } catch { failure = error.localizedDescription }
	}
}
private struct LogicSelection: Identifiable { var id: String }
private struct LogicPortSelection: Identifiable { var node: String; var name: String; var output: Bool; var id: String { "\(node).\(name).\(output)" } }

private struct BehaviorSettings: View {
	let kind: String
	@Binding var config: BehaviorConfig
	var body: some View {
		VStack(alignment: .leading, spacing: 20) {
			Field(label: "Name") { TextField("Block name", text: $config.label).accessibilityIdentifier("logic.label") }
			if ["variable", "count", "compare", "goal", "app_usage"].contains(kind) {
				Field(label: kind == "count" ? "Increase by" : kind == "variable" ? "Initial value" : "Target value") { TextField("Value", value: $config.value, format: .number).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("logic.value") }
			}
			if kind == "compare" { Picker("Comparison", selection: $config.operator) { Text("At least").tag("gte"); Text("More than").tag("gt"); Text("Equals").tag("eq"); Text("Less than").tag("lt"); Text("At most").tag("lte") } }
			if kind == "delay" { Field(label: "Minutes") { TextField("Minutes", value: $config.minutes, format: .number).keyboardType(.decimalPad) } }
			if kind == "clock" {
				Field(label: "Time · 24-hour") { TextField("18:00", text: $config.time).keyboardType(.numbersAndPunctuation) }
				ForEach(1...7, id: \.self) { day in Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { config.days.contains(day) }, set: { on in if on { config.days.append(day); config.days.sort() } else if config.days.count > 1 { config.days.removeAll { $0 == day } } })).tint(Theme.accent) }
			}
			if kind == "reminder" { Field(label: "Message") { TextField("Your reminder", text: $config.message, axis: .vertical).accessibilityIdentifier("logic.message") } }
			if ["location", "arrive", "leave"].contains(kind) { Text("Uses the location saved on this phone, shared with your home allowance.").supporting() }
			if kind == "app_usage" { Text("Reads distraction minutes counted by your home allowance. Away usage is excluded.").supporting() }
			Text("Behaviors run while this routine is open. Scheduled app restrictions continue in the background.").supporting()
		}
	}
}
