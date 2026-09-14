import SwiftUI

struct EditorView: View {
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@Environment(\.dismiss) private var dismiss
	@State private var draft: AppDocument
	@State private var validation_message: String?
	@State private var showing_blocks = false
	@State private var showing_behavior = false
	@State private var saving = false
	let is_new: Bool
	private let original: AppDocument

	init(document: AppDocument, is_new: Bool = false) {
		var initial = document
		if is_new { initial.blocks[0].title = "Heading"; initial.blocks[0].subtitle = "" }
		_draft = State(initialValue: initial); self.is_new = is_new; original = document
	}
	struct KindOption: Identifiable { let kind: BlockKind; let label: String; let icon: String; var id: BlockKind { kind } }
	static let kinds: [KindOption] = [
		KindOption(kind: .heading, label: "Heading", icon: "textformat"), KindOption(kind: .timer, label: "Timer", icon: "timer"), KindOption(kind: .checklist, label: "Checklist", icon: "checklist"),
		KindOption(kind: .counter, label: "Counter", icon: "number"), KindOption(kind: .note, label: "Note", icon: "note.text"), KindOption(kind: .screen_time, label: "Screen Time", icon: "shield"), KindOption(kind: .schedule, label: "Schedule", icon: "calendar")
	]
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 24) {
					VStack(alignment: .leading, spacing: 12) {
						Image(systemName: "doc.text").font(.system(size: 28, weight: .light)).foregroundStyle(Theme.text_faint)
						TextField("Untitled routine", text: $draft.name, axis: .vertical).font(.system(size: 30, weight: .semibold)).tracking(-0.6).foregroundStyle(Theme.text).accessibilityIdentifier("editor.name")
						TextField("Add a description…", text: $draft.description, axis: .vertical).font(.system(size: 14)).foregroundStyle(Theme.text_dim).accessibilityIdentifier("editor.description")
					}
					Hairline()
					VStack(alignment: .leading, spacing: 0) {
						ForEach(Array(draft.blocks.enumerated()), id: \.element.id) { index, block in block_row(index: index, block: block) }
					}
					Button { showing_blocks = true } label: { Label("Add a block to this page", systemImage: "plus") }.buttonStyle(TextButtonStyle()).frame(minHeight: 44, alignment: .leading)
					if draft.blocks.count == 1 { Text("Tap a block to edit it. Add a timer, schedule, or anything else your routine needs.").supporting() }
				}
				.padding(24).padding(.bottom, 24)
			}.paper_page().scrollDismissesKeyboard(.interactively)
			.navigationTitle(is_new ? "New routine" : "Edit routine").navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
				ToolbarItem(placement: .topBarTrailing) { Menu { Button("Advanced logic…", systemImage: "point.3.connected.trianglepath.dotted") { showing_behavior = true }.accessibilityIdentifier("editor.logic") } label: { Image(systemName: "ellipsis") } }
				ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).foregroundStyle(Theme.accent).disabled(saving || sessions.is_busy) }
			}
			.safeAreaInset(edge: .bottom) {
				EditorBar {
					Button { showing_blocks = true } label: { Label("Add block", systemImage: "plus") }.buttonStyle(TextButtonStyle()).accessibilityIdentifier("editor.add-block")
					Spacer()
					if saving { ProgressView() }
				}
			}
			.sheet(isPresented: $showing_blocks) { BlockPalette(can_add: { draft.can_add($0) }, add: { add_block($0) }) }
			.fullScreenCover(isPresented: $showing_behavior) { LogicEditorView(document: $draft) }
			.interactiveDismissDisabled(saving)
			.alert("Couldn’t save this routine", isPresented: Binding(get: { validation_message != nil }, set: { if !$0 { validation_message = nil } })) { Button("OK") { validation_message = nil } } message: { Text(validation_message ?? "") }
		}
	}
	private func block_row(index: Int, block: BlockDocument) -> some View {
		HStack(alignment: .top, spacing: 8) {
			NavigationLink {
				BlockEditorView(block: Binding(get: { draft.blocks.first { $0.id == block.id } ?? block }, set: { value in if let position = draft.blocks.firstIndex(where: { $0.id == block.id }) { draft.blocks[position] = value } }), groups: library.groups)
			} label: {
				DocumentRow(icon: Self.icon(for: block.type)) {
					VStack(alignment: .leading, spacing: 6) {
						Text(block.title).heading_font(block.type == .heading ? 22 : 16)
						block_preview(block)
					}
				}
			}.buttonStyle(.plain).accessibilityIdentifier("block.\(block.type.rawValue)")
			Menu {
				Button("Move up", systemImage: "arrow.up") { move(index, by: -1) }.disabled(index == 0)
				Button("Move down", systemImage: "arrow.down") { move(index, by: 1) }.disabled(index == draft.blocks.count - 1)
				Button("Remove block", systemImage: "trash", role: .destructive) { draft = draft.removing_block(block.id) }.disabled(draft.blocks.count == 1)
			} label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).foregroundStyle(Theme.text_faint) }.accessibilityLabel("Options for \(block.title)")
		}
	}
	@ViewBuilder private func block_preview(_ block: BlockDocument) -> some View {
		switch block.type {
		case .heading: Text(block.subtitle?.isEmpty == false ? block.subtitle! : "Add supporting text").supporting()
		case .timer: Text("\(block.minutes ?? 25) minutes").font(.system(size: 28, weight: .light, design: .monospaced)).foregroundStyle(Theme.text_dim)
		case .checklist: ForEach(block.items ?? []) { item in Label(item.text, systemImage: "square").font(.system(size: 14)).foregroundStyle(Theme.text_dim) }
		case .note: Text(block.text?.isEmpty == false ? block.text! : "Write something to come back to.").supporting()
		case .counter: Text("Goal · \(block.target ?? 1)").supporting()
		case .screen_time: Text(block.shield_description).supporting()
		case .schedule: Text("\(block.start ?? "")–\(block.end ?? "") · \((block.days ?? []).count) days a week").supporting()
		}
	}
	private func move(_ index: Int, by offset: Int) { let destination = index + offset; if draft.blocks.indices.contains(destination) { draft.blocks.swapAt(index, destination) } }
	private func add_block(_ kind: BlockKind) {
		guard draft.can_add(kind) else { return }
		draft.blocks.append(BlockDocument.make(kind))
		if kind == .schedule { draft.enabled = false }
		if draft.has_engine && draft.has_screen_time { draft.rules.block_during_focus = true }
	}
	private func save() {
		var cleaned = draft
		cleaned.name = cleaned.name.trimmingCharacters(in: .whitespacesAndNewlines)
		cleaned.rules.block_during_focus = cleaned.rules.block_during_focus && cleaned.has_engine && cleaned.has_screen_time
		cleaned.rules.notify_on_complete = cleaned.rules.notify_on_complete && cleaned.has_timer
		if !cleaned.is_standing { cleaned.enabled = nil }
		do { try cleaned.validate() } catch { validation_message = error.localizedDescription; return }
		saving = true
		Task {
			defer { saving = false }
			if original.enabled == true && cleaned.enabled != true {
				guard await sessions.set_routine(original, enabled: false, groups: library.groups) else { validation_message = sessions.error_message; return }
				library.set_enabled(original.id, false)
			}
			guard library.save(cleaned) else { validation_message = library.error_message; return }
			if cleaned.enabled == true, !(await sessions.set_routine(cleaned, enabled: true, groups: library.groups)) { library.set_enabled(cleaned.id, false); draft.enabled = false; validation_message = sessions.error_message; return }
			dismiss()
		}
	}
	static func label(for kind: BlockKind) -> String { kinds.first(where: { $0.kind == kind })?.label ?? kind.rawValue }
	static func icon(for kind: BlockKind) -> String { kinds.first(where: { $0.kind == kind })?.icon ?? "square" }
}

struct BlockEditorView: View {
	@Binding var block: BlockDocument
	var groups: [AppGroup] = []
	var embedded = false
	@State private var new_group = ""
	private static let minute_options = [15, 20, 25, 30, 45, 60, 90, 120]
	private static let limit_options = [15, 30, 45, 60, 90, 120, 180]
	struct ModeOption: Identifiable { let mode: ShieldMode; let label: String; let hint: String; var id: ShieldMode { mode } }
	private static let modes = [ModeOption(mode: .block, label: "Block", hint: "Lock these groups"), ModeOption(mode: .allow_only, label: "Only these", hint: "Lock everything except these groups"), ModeOption(mode: .limit, label: "Limit", hint: "Lock after so many minutes")]

	var body: some View {
		Group {
			if embedded { fields } else { ScrollView { fields }.page().navigationTitle(EditorView.label(for: block.type)).navigationBarTitleDisplayMode(.inline) }
		}
	}
	private var fields: some View {
			VStack(alignment: .leading, spacing: 20) {
				HStack(spacing: 12) {
					Image(systemName: EditorView.icon(for: block.type)).frame(width: 36, height: 36).background(Theme.surface_hi, in: RoundedRectangle(cornerRadius: Theme.radius_small)).foregroundStyle(Theme.text_dim)
					VStack(alignment: .leading, spacing: 2) {
						Text(EditorView.label(for: block.type)).heading_font(17)
						Text("Changes appear in the routine when you save.").supporting()
					}
				}
				Field(label: "Title") { TextField("Title", text: $block.title) }
				switch block.type {
				case .heading:
					Field(label: "Supporting text") { TextField("A line under the title", text: Binding(get: { block.subtitle ?? "" }, set: { block.subtitle = $0 }), axis: .vertical) }
				case .timer:
					choice_row(label: "Session length", options: Self.minute_options, selected: block.minutes ?? 25, suffix: "min") { block.minutes = $0 }
					Text("15 to 120 minutes. Screen Time needs at least 15.").supporting()
				case .checklist:
					VStack(alignment: .leading, spacing: 10) {
						HStack { SectionLabel(text: "Tasks"); Spacer(); Text("\((block.items ?? []).count)/20").mono_caption() }
						ForEach(Array((block.items ?? []).enumerated()), id: \.element.id) { index, item in
							HStack(spacing: 8) {
								Field(label: "Task \(index + 1)") { TextField("Task", text: Binding(get: { block.items?[index].text ?? item.text }, set: { block.items?[index].text = $0 })) }
								Button { remove_task(item.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.text_faint).disabled((block.items ?? []).count == 1).accessibilityLabel("Remove task \(index + 1)").padding(.top, 18)
							}
						}
						Button { block.items = (block.items ?? []) + [TaskDocument(id: UUID().uuidString, text: "Another small step")] } label: { Label("Add task", systemImage: "plus") }.buttonStyle(QuietButtonStyle()).disabled((block.items ?? []).count >= 20)
					}
				case .counter:
					VStack(alignment: .leading, spacing: 6) {
						Text("Target").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text_dim)
						HStack(spacing: 12) {
							Button { block.target = max(1, (block.target ?? 1) - 1) } label: { Image(systemName: "minus") }.buttonStyle(QuietButtonStyle()).disabled((block.target ?? 1) <= 1)
							Text("\(block.target ?? 1)").font(.system(size: 22, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text).frame(minWidth: 48)
							Button { block.target = min(1000, (block.target ?? 1) + 1) } label: { Image(systemName: "plus") }.buttonStyle(QuietButtonStyle()).disabled((block.target ?? 1) >= 1000)
						}
					}
				case .note:
					Field(label: "Your note") { TextField("Something worth reading", text: Binding(get: { block.text ?? "" }, set: { block.text = $0 }), axis: .vertical) }
				case .screen_time:
					screen_time_editor
				case .schedule:
					schedule_editor
				}
			}
			.padding(Theme.pad)
			.padding(.bottom, 24)
	}

	// Horizontal chips, like the web's day picker, for picking one number from a short list.
	private func choice_row(label: String, options: [Int], selected: Int, suffix: String, choose: @escaping (Int) -> Void) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text_dim)
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 6) {
					ForEach(Array(Set(options + [selected])).sorted(), id: \.self) { value in
						chip("\(value) \(suffix)", on: value == selected) { choose(value) }
					}
				}
			}
		}
	}

	private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(text).font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).frame(minHeight: 36)
				.background(on ? Theme.text : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius_small))
				.overlay(RoundedRectangle(cornerRadius: Theme.radius_small).strokeBorder(on ? Theme.text : Theme.border))
				.foregroundStyle(on ? Theme.surface : Theme.text_dim)
		}
		.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
	}

	private var screen_time_editor: some View {
		VStack(alignment: .leading, spacing: 16) {
			VStack(alignment: .leading, spacing: 8) {
				SectionLabel(text: "What happens")
				ForEach(Self.modes) { option in
					let chosen = block.shield_mode == option.mode
					Button {
						block.mode = option.mode
						block.limit_minutes = option.mode == .limit ? (block.limit_minutes ?? 30) : nil
					} label: {
						VStack(alignment: .leading, spacing: 2) {
							Text(option.label).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
							Text(option.hint).font(.system(size: 12)).foregroundStyle(Theme.text_faint)
						}
						.padding(12).frame(maxWidth: .infinity, alignment: .leading)
						.background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius_small))
						.overlay(RoundedRectangle(cornerRadius: Theme.radius_small).strokeBorder(chosen ? Theme.text : Theme.border, lineWidth: chosen ? 2 : 1))
					}
					.buttonStyle(.plain).accessibilityLabel(option.label).accessibilityAddTraits(chosen ? .isSelected : [])
				}
				if block.shield_mode == .limit {
					choice_row(label: "Minutes before it locks", options: Self.limit_options, selected: block.limit_minutes ?? 30, suffix: "min") { block.limit_minutes = $0 }
				}
			}
			VStack(alignment: .leading, spacing: 4) {
				SectionLabel(text: "App groups")
				let names = Array(Set(groups.map(\.name) + block.group_names)).sorted { $0.lowercased() < $1.lowercased() }
				if names.isEmpty { Text("No groups yet. Name one below; you choose its apps under App groups.").supporting().padding(.vertical, 6) }
				ForEach(names, id: \.self) { name in
					ToggleRow(title: name, is_on: Binding(get: { block.group_names.contains { $0.lowercased() == name.lowercased() } }, set: { on in
						var current = block.group_names.filter { $0.lowercased() != name.lowercased() }
						if on { current.append(name) }
						block.groups = current.isEmpty ? nil : current
					}))
					Hairline()
				}
				HStack(spacing: 8) {
					Field(label: "New group") { TextField("e.g. Social", text: $new_group).onSubmit(add_group) }
					Button { add_group() } label: { Label("Add", systemImage: "plus") }.buttonStyle(QuietButtonStyle()).disabled(new_group.trimmingCharacters(in: .whitespaces).isEmpty).padding(.top, 18)
				}
				.padding(.top, 8)
				Text(block.group_names.isEmpty ? "With no groups, this routine asks you to choose its apps on the routine screen." : "\(block.shield_description). The apps in each group are chosen under App groups and stay on this iPhone.").supporting().padding(.top, 4)
			}
		}
	}

	private var schedule_editor: some View {
		VStack(alignment: .leading, spacing: 16) {
			VStack(alignment: .leading, spacing: 8) {
				SectionLabel(text: "Days")
				HStack(spacing: 6) {
					ForEach(ScheduleWindow.all_days, id: \.self) { day in
						let chosen = (block.days ?? []).contains(day)
						Button {
							var days = Set(block.days ?? [])
							if chosen { if days.count > 1 { days.remove(day) } } else { days.insert(day) }
							block.days = days.sorted()
						} label: {
							Text(String(ScheduleWindow.day_labels[day - 1].prefix(2))).font(.system(size: 13, weight: .medium)).lineLimit(1).frame(maxWidth: .infinity, minHeight: 36)
								.background(chosen ? Theme.text : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius_small))
								.overlay(RoundedRectangle(cornerRadius: Theme.radius_small).strokeBorder(chosen ? Theme.text : Theme.border))
								.foregroundStyle(chosen ? Theme.surface : Theme.text_dim)
						}
						.buttonStyle(.plain).accessibilityLabel(ScheduleWindow.day_labels[day - 1]).accessibilityAddTraits(chosen ? .isSelected : [])
					}
				}
				HStack(spacing: 16) {
					Button("Every day") { block.days = ScheduleWindow.all_days }.buttonStyle(TextButtonStyle())
					Button("Weekdays") { block.days = ScheduleWindow.weekdays }.buttonStyle(TextButtonStyle())
				}
			}
			HStack(spacing: 12) {
				Field(label: "Starts") { DatePicker("Starts", selection: clock_binding(\.start, fallback: "22:00"), displayedComponents: .hourAndMinute).labelsHidden() }
				Field(label: "Ends") { DatePicker("Ends", selection: clock_binding(\.end, fallback: "07:00"), displayedComponents: .hourAndMinute).labelsHidden() }
			}
			Text("An end time earlier than the start runs past midnight. Windows need at least 15 minutes.").supporting()
		}
	}

	private func remove_task(_ id: String) {
		var items = block.items ?? []
		guard items.count > 1 else { return }
		items.removeAll { $0.id == id }
		block.items = items
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
