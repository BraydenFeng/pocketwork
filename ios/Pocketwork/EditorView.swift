import SwiftUI

// On-phone editing of a tool. Works on a draft; nothing is saved until Save passes the same validation as the web editor.
struct EditorView: View {
	@EnvironmentObject private var library: LibraryController
	@Environment(\.dismiss) private var dismiss
	@State private var draft: AppDocument
	@State private var validation_message: String?
	@State private var edit_mode: EditMode = .inactive

	init(document: AppDocument) { _draft = State(initialValue: document) }

	struct KindOption: Identifiable { let kind: BlockKind; let label: String; let icon: String; var id: BlockKind { kind } }
	private static let kinds: [KindOption] = [
		KindOption(kind: .heading, label: "Heading", icon: "textformat"), KindOption(kind: .timer, label: "Focus timer", icon: "timer"), KindOption(kind: .checklist, label: "Checklist", icon: "checklist"),
		KindOption(kind: .counter, label: "Counter", icon: "number"), KindOption(kind: .note, label: "Note", icon: "note.text"), KindOption(kind: .screen_time, label: "Screen Time", icon: "shield.lefthalf.filled"),
		KindOption(kind: .schedule, label: "Schedule", icon: "calendar.badge.clock"),
	]

	var body: some View {
		NavigationStack {
			Form {
				Section("Name") {
					TextField("Routine name", text: $draft.name)
					TextField("What it's for", text: $draft.description, axis: .vertical)
				}
				Section {
					ForEach($draft.blocks) { $block in
						NavigationLink { BlockEditorView(block: $block, groups: library.groups) } label: {
							Label {
								VStack(alignment: .leading) {
									Text(block.title)
									Text(Self.label(for: block.type)).font(.caption).foregroundStyle(.secondary)
								}
							} icon: { Image(systemName: Self.icon(for: block.type)) }
						}
						.accessibilityIdentifier("block.\(block.type.rawValue)")
					}
					.onDelete { offsets in
						for index in offsets.sorted(by: >) where draft.blocks.count > 1 { draft = draft.removing_block(draft.blocks[index].id) }
					}
					.onMove { offsets, destination in draft.blocks.move(fromOffsets: offsets, toOffset: destination) }
					Menu {
						ForEach(Self.kinds) { option in
							Button(option.label, systemImage: option.icon) { add_block(option.kind) }.disabled(!draft.can_add(option.kind))
						}
					} label: { Label("Add block", systemImage: "plus") }
				} header: { Text("On your screen · \(draft.blocks.count)/20") } footer: {
					Text("Swipe to remove a block. Reorder to drag them. A routine runs on a timer or a schedule, not both.")
				}
				Section {
					Toggle(isOn: $draft.rules.block_during_focus) {
						Text(draft.is_standing ? "Block while active" : "Block during focus")
						Text(draft.has_engine && draft.has_screen_time ? (draft.is_standing ? "Uses your schedule and Screen Time block" : "Uses your timer and Screen Time block") : "Add a timer or schedule, plus a Screen Time block first")
					}.disabled(!(draft.has_engine && draft.has_screen_time))
					Toggle(isOn: $draft.rules.notify_on_complete) {
						Text("Notify on completion")
						Text(draft.has_timer ? "A notification when the timer finishes" : draft.is_standing ? "Only for timer routines" : "Add a timer first")
					}.disabled(!draft.has_timer)
				} header: { Text(draft.is_standing ? "What happens on schedule" : "What happens when you focus") }
			}
			.navigationTitle("Edit routine")
			.navigationBarTitleDisplayMode(.inline)
			.environment(\.editMode, $edit_mode)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
				ToolbarItem(placement: .primaryAction) { Button(edit_mode == .active ? "Done" : "Reorder") { withAnimation { edit_mode = edit_mode == .active ? .inactive : .active } } }
				ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
			}
			.alert("Not quite ready to save", isPresented: Binding(get: { validation_message != nil }, set: { if !$0 { validation_message = nil } })) {
				Button("OK") { validation_message = nil }
			} message: { Text(validation_message ?? "") }
		}
	}

	private func add_block(_ kind: BlockKind) {
		if (kind == .schedule && draft.has_timer) || (kind == .timer && draft.is_standing) {
			validation_message = "A routine runs on a timer or on a schedule, not both. Remove the other one first."
			return
		}
		draft.blocks.append(BlockDocument.make(kind))
		// A schedule only means something if it locks apps, so switch that rule on when the pieces are there.
		if kind == .schedule { draft.enabled = false; if draft.has_screen_time { draft.rules.block_during_focus = true } }
	}

	private func save() {
		var cleaned = draft
		cleaned.name = cleaned.name.trimmingCharacters(in: .whitespacesAndNewlines)
		cleaned.rules.block_during_focus = cleaned.rules.block_during_focus && cleaned.has_engine && cleaned.has_screen_time
		cleaned.rules.notify_on_complete = cleaned.rules.notify_on_complete && cleaned.has_timer
		if !cleaned.is_standing { cleaned.enabled = nil }
		do { try cleaned.validate() } catch { validation_message = error.localizedDescription; return }
		if library.save(cleaned) { dismiss() }
	}

	static func label(for kind: BlockKind) -> String { kinds.first(where: { $0.kind == kind })?.label ?? kind.rawValue }
	static func icon(for kind: BlockKind) -> String { kinds.first(where: { $0.kind == kind })?.icon ?? "square" }
}

struct BlockEditorView: View {
	@Binding var block: BlockDocument
	var groups: [AppGroup] = []
	@State private var new_group = ""
	private static let minute_options = [15, 20, 25, 30, 45, 60, 90, 120]
	private static let limit_options = [15, 30, 45, 60, 90, 120, 180]

	var body: some View {
		Form {
			Section("Title") { TextField("Title", text: $block.title) }
			switch block.type {
			case .heading:
				Section("Supporting text") {
					TextField("A line under the title", text: Binding(get: { block.subtitle ?? "" }, set: { block.subtitle = $0 }), axis: .vertical)
				}
			case .timer:
				Section {
					Picker("Session length", selection: Binding(get: { block.minutes ?? 25 }, set: { block.minutes = $0 })) {
						ForEach(Array(Set(Self.minute_options + [block.minutes ?? 25])).sorted(), id: \.self) { minutes in Text("\(minutes) minutes").tag(minutes) }
					}
				} footer: { Text("15 to 120 minutes. Screen Time needs at least 15.") }
			case .checklist:
				Section {
					ForEach(Binding(get: { block.items ?? [] }, set: { block.items = $0 })) { $item in
						TextField("Task", text: $item.text)
					}
					.onDelete { offsets in
						var items = block.items ?? []
						guard items.count > 1 else { return }
						items.remove(atOffsets: offsets)
						block.items = items
					}
					Button("Add task", systemImage: "plus") { block.items = (block.items ?? []) + [TaskDocument(id: UUID().uuidString, text: "Another small step")] }
						.disabled((block.items ?? []).count >= 20)
				} header: { Text("Tasks · \((block.items ?? []).count)/20") } footer: { Text("Swipe a task to remove it.") }
			case .counter:
				Section("Target") {
					Stepper("\(block.target ?? 1)", value: Binding(get: { block.target ?? 1 }, set: { block.target = $0 }), in: 1...1000)
				}
			case .note:
				Section("Your note") {
					TextField("Something worth reading", text: Binding(get: { block.text ?? "" }, set: { block.text = $0 }), axis: .vertical)
				}
			case .schedule:
				Section("Days") {
					HStack(spacing: 6) {
						ForEach(ScheduleWindow.all_days, id: \.self) { day in
							let chosen = (block.days ?? []).contains(day)
							Button {
								var days = Set(block.days ?? [])
								if chosen { if days.count > 1 { days.remove(day) } } else { days.insert(day) }
								block.days = days.sorted()
							} label: {
								Text(String(ScheduleWindow.day_labels[day - 1].prefix(2))).font(.subheadline.weight(.medium)).lineLimit(1).frame(maxWidth: .infinity)
							}
							.buttonStyle(.bordered).controlSize(.small).tint(chosen ? Color.primary : Color.secondary)
							.accessibilityLabel(ScheduleWindow.day_labels[day - 1]).accessibilityAddTraits(chosen ? .isSelected : [])
						}
					}
					HStack {
						Button("Every day") { block.days = ScheduleWindow.all_days }
						Spacer()
						Button("Weekdays") { block.days = ScheduleWindow.weekdays }
					}.font(.subheadline)
				}
				Section {
					DatePicker("Starts", selection: clock_binding(\.start, fallback: "22:00"), displayedComponents: .hourAndMinute)
					DatePicker("Ends", selection: clock_binding(\.end, fallback: "07:00"), displayedComponents: .hourAndMinute)
				} footer: { Text("An end time earlier than the start runs past midnight. Windows need at least 15 minutes.") }
			case .screen_time:
				Section {
					Picker("What happens", selection: Binding(get: { block.shield_mode }, set: { mode in
						block.mode = mode
						block.limit_minutes = mode == .limit ? (block.limit_minutes ?? 30) : nil
					})) {
						Text("Block").tag(ShieldMode.block)
						Text("Only these").tag(ShieldMode.allow_only)
						Text("Limit").tag(ShieldMode.limit)
					}.pickerStyle(.segmented)
					if block.shield_mode == .limit {
						Picker("Minutes before it locks", selection: Binding(get: { block.limit_minutes ?? 30 }, set: { block.limit_minutes = $0 })) {
							ForEach(Array(Set(Self.limit_options + [block.limit_minutes ?? 30])).sorted(), id: \.self) { minutes in Text("\(minutes) minutes").tag(minutes) }
						}
					}
				} footer: {
					Text(block.shield_mode == .block ? "The groups below are locked while the routine runs." : block.shield_mode == .allow_only ? "Everything except the groups below is locked while the routine runs." : "The groups below lock once they have been used this long inside the routine.")
				}
				Section {
					let names = Array(Set(groups.map(\.name) + block.group_names)).sorted { $0.lowercased() < $1.lowercased() }
					if names.isEmpty { Text("No groups yet. Name one below; you choose its apps under App groups.").foregroundStyle(.secondary) }
					ForEach(names, id: \.self) { name in
						Toggle(name, isOn: Binding(get: { block.group_names.contains { $0.lowercased() == name.lowercased() } }, set: { on in
							var current = block.group_names.filter { $0.lowercased() != name.lowercased() }
							if on { current.append(name) }
							block.groups = current.isEmpty ? nil : current
						}))
					}
					HStack {
						TextField("New group, e.g. Social", text: $new_group).onSubmit(add_group)
						Button("Add") { add_group() }.disabled(new_group.trimmingCharacters(in: .whitespaces).isEmpty)
					}
				} header: { Text("App groups") } footer: {
					Text(block.group_names.isEmpty ? "With no groups, this routine asks you to choose its apps on the routine screen." : "\(block.shield_description). The apps in each group are chosen under App groups and stay on this iPhone.")
				}
			}
		}
		.navigationTitle(EditorView.label(for: block.type))
		.navigationBarTitleDisplayMode(.inline)
	}

	private func add_group() {
		let name = new_group.trimmingCharacters(in: .whitespaces)
		guard !name.isEmpty, name.utf16.count <= 40, !block.group_names.contains(where: { $0.lowercased() == name.lowercased() }) else { new_group = ""; return }
		block.groups = block.group_names + [name]
		new_group = ""
	}

	// "HH:MM" in the document ↔ a Date on today's calendar for the picker.
	private func clock_binding(_ key: WritableKeyPath<BlockDocument, String?>, fallback: String) -> Binding<Date> {
		Binding(get: {
			let minutes = ScheduleWindow.minutes(block[keyPath: key] ?? fallback) ?? 0
			return Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: .now)) ?? .now
		}, set: { date in
			let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
			block[keyPath: key] = ScheduleWindow.clock((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
		})
	}
}
