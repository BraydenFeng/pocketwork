import SwiftUI

// A block while the page is being edited: the same layout as when it runs, with its two or three real settings shown as visible choices.
struct InlineRoutineBlock: View {
	@Binding var block: BlockDocument
	let groups: [AppGroup]
	@State private var new_group = ""
	private static let minute_options = [15, 20, 25, 30, 45, 60, 90, 120]
	private static let limit_options = [15, 30, 45, 60, 90, 120, 180]

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
						ChipRow(label: "Length", options: Array(Set(Self.minute_options + [block.minutes ?? 25])).sorted(), selected: block.minutes ?? 25, text: { "\($0) min" }) { block.minutes = $0 }
					}
				}
			case .checklist:
				VStack(alignment: .leading, spacing: 0) {
					title.heading_font(15).padding(.bottom, 8)
					ForEach(block.items ?? []) { item in
						HStack(alignment: .top, spacing: 12) {
							Image(systemName: "square").foregroundStyle(Theme.border_hi).padding(.top, 12)
							TextField("Task", text: task(item), axis: .vertical).font(.system(size: 15)).padding(.vertical, 10).accessibilityIdentifier("page.task." + item.id)
							Button { block.items?.removeAll { $0.id == item.id } } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 44, height: 44) }.buttonStyle(.plain).foregroundStyle(Theme.text_faint).disabled((block.items?.count ?? 0) <= 1).accessibilityLabel("Remove task")
						}
						Hairline()
					}
					Button { block.items = (block.items ?? []) + [TaskDocument(id: UUID().uuidString, text: "New task")] } label: { Label("Add task", systemImage: "plus") }.buttonStyle(TextButtonStyle()).frame(minHeight: 44).disabled((block.items?.count ?? 0) >= 20)
				}
			case .counter:
				Card {
					VStack(alignment: .leading, spacing: 10) {
						title.heading_font(15)
						HStack(spacing: 12) {
							Text("Goal").supporting()
							Chip(text: "−", compact: true) { block.target = max(1, (block.target ?? 1) - 1) }
							Text("\(block.target ?? 1)").font(.system(size: 28, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text).frame(minWidth: 44)
							Chip(text: "+", compact: true) { block.target = min(1000, (block.target ?? 1) + 1) }
							Spacer()
						}
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
						VStack(alignment: .leading, spacing: 6) {
							Text("Days").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text_dim)
							HStack(spacing: 6) {
								ForEach(ScheduleWindow.all_days, id: \.self) { day in
									let on = (block.days ?? []).contains(day)
									Button {
										var days = Set(block.days ?? [])
										if on { if days.count > 1 { days.remove(day) } } else { days.insert(day) }
										block.days = days.sorted()
									} label: {
										Text(String(ScheduleWindow.day_labels[day - 1].prefix(2))).font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity, minHeight: 36)
											.background(on ? Theme.text : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius_small))
											.overlay(RoundedRectangle(cornerRadius: Theme.radius_small).strokeBorder(on ? Theme.text : Theme.border))
											.foregroundStyle(on ? Theme.surface : Theme.text_dim)
									}.buttonStyle(.plain).accessibilityLabel(ScheduleWindow.day_labels[day - 1]).accessibilityAddTraits(on ? .isSelected : [])
								}
							}
							HStack(spacing: 16) {
								Button("Every day") { block.days = ScheduleWindow.all_days }.buttonStyle(TextButtonStyle())
								Button("Weekdays") { block.days = ScheduleWindow.weekdays }.buttonStyle(TextButtonStyle())
								Button("Weekends") { block.days = [1, 7] }.buttonStyle(TextButtonStyle())
							}
						}
						HStack(spacing: 12) {
							VStack(alignment: .leading, spacing: 4) { Text("From").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text_dim); DatePicker("From", selection: clock(\.start), displayedComponents: .hourAndMinute).labelsHidden() }
							VStack(alignment: .leading, spacing: 4) { Text("Until").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text_dim); DatePicker("Until", selection: clock(\.end), displayedComponents: .hourAndMinute).labelsHidden() }
							Spacer()
						}
						Text("Ends before it starts? It runs past midnight.").font(.system(size: 11)).foregroundStyle(Theme.text_faint)
					}
				}
			case .screen_time:
				Card {
					VStack(alignment: .leading, spacing: 12) {
						Label { title.heading_font(15) } icon: { Image(systemName: "shield").foregroundStyle(Theme.text_dim) }
						VStack(alignment: .leading, spacing: 6) {
							Text("What happens").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text_dim)
							HStack(spacing: 6) {
								Chip(text: "Block", on: block.shield_mode == .block) { set_mode(.block) }
								Chip(text: "Only these", on: block.shield_mode == .allow_only) { set_mode(.allow_only) }
								Chip(text: "Limit", on: block.shield_mode == .limit) { set_mode(.limit) }
							}
							Text(block.shield_mode == .block ? "These groups lock while the routine runs." : block.shield_mode == .allow_only ? "Everything except these groups locks while the routine runs." : "These groups lock once you have used them this long inside the routine.").supporting()
						}
						if block.shield_mode == .limit {
							ChipRow(label: "Minutes before it locks", options: Array(Set(Self.limit_options + [block.limit_minutes ?? 30])).sorted(), selected: block.limit_minutes ?? 30, text: { "\($0) min" }) { block.limit_minutes = $0 }
						}
						VStack(alignment: .leading, spacing: 6) {
							Text("App groups").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text_dim)
							let names = Array(Set(groups.map(\.name) + block.group_names)).sorted { $0.lowercased() < $1.lowercased() }
							if names.isEmpty { Text("No groups yet. Name one below; you choose its apps under App groups.").supporting() }
							FlowChips(names: names, selected: block.group_names) { name in
								var current = block.group_names.filter { $0.lowercased() != name.lowercased() }
								if !block.group_names.contains(where: { $0.lowercased() == name.lowercased() }) { current.append(name) }
								block.groups = current.isEmpty ? nil : current
							}
							HStack(spacing: 8) {
								TextField("New group, e.g. Social", text: $new_group).font(.system(size: 14)).padding(.horizontal, 12).frame(minHeight: 36)
									.background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius_small)).overlay(RoundedRectangle(cornerRadius: Theme.radius_small).strokeBorder(Theme.border)).onSubmit(add_group)
								Chip(text: "Add", compact: true) { add_group() }.disabled(new_group.trimmingCharacters(in: .whitespaces).isEmpty)
							}
						}
						Text(block.group_names.isEmpty ? "With no groups, you choose this routine's apps on the page after saving." : "\(block.shield_description). The apps in each group are chosen under App groups.").supporting()
					}
				}
			}
		}.foregroundStyle(Theme.text).textFieldStyle(.plain)
	}

	private var title: some View { TextField("Title", text: $block.title, axis: .vertical).accessibilityIdentifier("page.title." + block.id) }
	private func set_mode(_ mode: ShieldMode) { block.mode = mode; block.limit_minutes = mode == .limit ? (block.limit_minutes ?? 30) : nil }
	private func add_group() {
		let name = new_group.trimmingCharacters(in: .whitespaces)
		guard !name.isEmpty, name.utf16.count <= 40, !block.group_names.contains(where: { $0.lowercased() == name.lowercased() }) else { new_group = ""; return }
		block.groups = block.group_names + [name]; new_group = ""
	}
	private func string(_ key: WritableKeyPath<BlockDocument, String?>) -> Binding<String> { Binding(get: { block[keyPath: key] ?? "" }, set: { block[keyPath: key] = $0 }) }
	private func task(_ item: TaskDocument) -> Binding<String> { Binding(get: { block.items?.first { $0.id == item.id }?.text ?? item.text }, set: { value in if let index = block.items?.firstIndex(where: { $0.id == item.id }) { block.items?[index].text = value } }) }
	private func clock(_ key: WritableKeyPath<BlockDocument, String?>) -> Binding<Date> {
		Binding(get: { Calendar.current.date(byAdding: .minute, value: ScheduleWindow.minutes(block[keyPath: key] ?? "00:00") ?? 0, to: Calendar.current.startOfDay(for: .now)) ?? .now }, set: { value in let parts = Calendar.current.dateComponents([.hour, .minute], from: value); block[keyPath: key] = ScheduleWindow.clock((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) })
	}
}

// Group chips that wrap onto as many lines as they need.
struct FlowChips: View {
	let names: [String]
	let selected: [String]
	let toggle: (String) -> Void
	var body: some View {
		let rows = Self.rows(names, per_row: 3)
		VStack(alignment: .leading, spacing: 6) {
			ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
				HStack(spacing: 6) {
					ForEach(row, id: \.self) { name in Chip(text: name, on: selected.contains { $0.lowercased() == name.lowercased() }) { toggle(name) } }
				}
			}
		}
	}
	private static func rows(_ names: [String], per_row: Int) -> [[String]] {
		stride(from: 0, to: names.count, by: per_row).map { Array(names[$0..<min($0 + per_row, names.count)]) }
	}
}
