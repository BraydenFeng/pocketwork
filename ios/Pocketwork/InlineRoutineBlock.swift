import SwiftUI

struct InlineRoutineBlock: View {
	@Binding var block: BlockDocument
	let groups: [AppGroup]
	var body: some View {
		Group {
			switch block.type {
			case .heading:
				VStack(alignment: .leading, spacing: 8) {
					Text("Your space, your pace").mono_caption().textCase(.uppercase)
					title.font(.system(size: 30, weight: .semibold)).tracking(-1)
					TextField("Add supporting text", text: string(\.subtitle), axis: .vertical).font(.system(size: 15)).foregroundStyle(Theme.text_faint)
				}.padding(.leading, 12).overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 2) }
			case .timer:
				Card(tinted: true) {
					VStack(alignment: .leading, spacing: 12) {
						title.font(.system(size: 13, weight: .medium))
						Text(String(format: "%02d:00", block.minutes ?? 25)).font(.system(size: 56, weight: .medium, design: .monospaced)).tracking(-2).foregroundStyle(Theme.text)
						Stepper("Minutes", value: number(\.minutes, fallback: 25), in: 15...120, step: 5).font(.system(size: 14)).accessibilityIdentifier("page.timer.minutes")
					}
				}
			case .checklist:
				VStack(alignment: .leading, spacing: 0) {
					title.heading_font(15).padding(.bottom, 8)
					ForEach(block.items ?? []) { item in
						HStack(alignment: .top, spacing: 12) {
							Image(systemName: "square").foregroundStyle(Theme.border_hi).padding(.top, 12)
							TextField("Task", text: task(item), axis: .vertical).font(.system(size: 15)).padding(.vertical, 10).accessibilityIdentifier("page.task." + item.id)
							Button { block.items?.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.buttonStyle(.plain).foregroundStyle(Theme.text_faint).disabled((block.items?.count ?? 0) <= 1).accessibilityLabel("Remove " + item.text)
						}
						Hairline()
					}
					Button { block.items = (block.items ?? []) + [TaskDocument(id: UUID().uuidString, text: "New task")] } label: { Label("Add task", systemImage: "plus") }.buttonStyle(TextButtonStyle()).frame(minHeight: 44).disabled((block.items?.count ?? 0) >= 20)
				}
			case .counter:
				Card {
					VStack(alignment: .leading, spacing: 10) {
						title.heading_font(15)
						HStack(alignment: .firstTextBaseline) { Text("Goal").supporting(); Text("\(block.target ?? 1)").font(.system(size: 32, weight: .semibold, design: .monospaced)); Spacer() }
						Stepper("Target", value: number(\.target, fallback: 5), in: 1...1000).font(.system(size: 14))
					}
				}
			case .note:
				VStack(alignment: .leading, spacing: 6) {
					title.heading_font(15)
					TextField("Write your note", text: string(\.text), axis: .vertical).font(.system(size: 15)).foregroundStyle(Theme.text_dim).accessibilityIdentifier("page.note." + block.id)
				}
			case .schedule:
				Card(tinted: true) {
					VStack(alignment: .leading, spacing: 12) {
						Label { title.font(.system(size: 13, weight: .medium)) } icon: { Image(systemName: "calendar.badge.clock") }
						Text(ScheduleWindow.describe(block)).heading_font(22)
						Menu("Choose days") {
							ForEach(ScheduleWindow.all_days, id: \.self) { day in
								Toggle(ScheduleWindow.day_labels[day - 1], isOn: Binding(get: { (block.days ?? []).contains(day) }, set: { on in
									var days = Set(block.days ?? [])
									if on { days.insert(day) } else if days.count > 1 { days.remove(day) }
									block.days = days.sorted()
								}))
							}
						}.buttonStyle(TextButtonStyle())
						DatePicker("From", selection: clock(\.start), displayedComponents: .hourAndMinute).font(.system(size: 14))
						DatePicker("Until", selection: clock(\.end), displayedComponents: .hourAndMinute).font(.system(size: 14))
					}
				}
			case .screen_time:
				Card {
					VStack(alignment: .leading, spacing: 10) {
						Label { title.heading_font(15) } icon: { Image(systemName: "shield").foregroundStyle(Theme.text_dim) }
						Picker("Action", selection: Binding(get: { block.shield_mode }, set: { block.mode = $0; block.limit_minutes = $0 == .limit ? (block.limit_minutes ?? 30) : nil })) {
							Text("Block").tag(ShieldMode.block); Text("Allow only").tag(ShieldMode.allow_only); Text("Limit").tag(ShieldMode.limit)
						}.pickerStyle(.menu)
						if block.shield_mode == .limit { Stepper("\(block.limit_minutes ?? 30) minutes", value: number(\.limit_minutes, fallback: 30), in: 1...180).font(.system(size: 14)) }
						Hairline()
						Menu { ForEach(Array(Set(groups.map(\.name) + block.group_names)).sorted(), id: \.self) { name in
							Toggle(name, isOn: Binding(get: { block.group_names.contains(name) }, set: { on in var names = block.group_names.filter { $0 != name }; if on { names.append(name) }; block.groups = names.isEmpty ? nil : names }))
						} } label: { Label(block.group_names.isEmpty ? "Choose app groups" : block.group_names.joined(separator: ", "), systemImage: "square.grid.2x2") }.buttonStyle(TextButtonStyle()).disabled(groups.isEmpty && block.group_names.isEmpty)
						Text(block.group_names.isEmpty ? "Apps can be selected on this page after saving. Create reusable groups from My routines." : block.shield_description).supporting()
					}
				}
			}
		}.foregroundStyle(Theme.text).textFieldStyle(.plain)
	}
	private var title: some View { TextField("Title", text: $block.title, axis: .vertical).accessibilityIdentifier("page.title." + block.id) }
	private func string(_ key: WritableKeyPath<BlockDocument, String?>) -> Binding<String> { Binding(get: { block[keyPath: key] ?? "" }, set: { block[keyPath: key] = $0 }) }
	private func number(_ key: WritableKeyPath<BlockDocument, Int?>, fallback: Int) -> Binding<Int> { Binding(get: { block[keyPath: key] ?? fallback }, set: { block[keyPath: key] = $0 }) }
	private func task(_ item: TaskDocument) -> Binding<String> { Binding(get: { block.items?.first { $0.id == item.id }?.text ?? item.text }, set: { value in if let index = block.items?.firstIndex(where: { $0.id == item.id }) { block.items?[index].text = value } }) }
	private func clock(_ key: WritableKeyPath<BlockDocument, String?>) -> Binding<Date> {
		Binding(get: { Calendar.current.date(byAdding: .minute, value: ScheduleWindow.minutes(block[keyPath: key] ?? "00:00") ?? 0, to: Calendar.current.startOfDay(for: .now)) ?? .now }, set: { value in let parts = Calendar.current.dateComponents([.hour, .minute], from: value); block[keyPath: key] = ScheduleWindow.clock((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) })
	}
}
