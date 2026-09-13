import SwiftUI

// On-phone editing of a routine, drawn like the web inspector. Works on a draft; nothing is saved until Save passes the same validation as the web editor.
struct EditorView: View {
	@EnvironmentObject private var library: LibraryController
	@Environment(\.dismiss) private var dismiss
	@State private var draft: AppDocument
	@State private var validation_message: String?

	init(document: AppDocument) { _draft = State(initialValue: document) }

	struct KindOption: Identifiable { let kind: BlockKind; let label: String; let icon: String; var id: BlockKind { kind } }
	static let kinds: [KindOption] = [
		KindOption(kind: .heading, label: "Heading", icon: "textformat"), KindOption(kind: .timer, label: "Focus timer", icon: "timer"), KindOption(kind: .checklist, label: "Checklist", icon: "checklist"),
		KindOption(kind: .counter, label: "Counter", icon: "number"), KindOption(kind: .note, label: "Note", icon: "note.text"), KindOption(kind: .screen_time, label: "Screen Time", icon: "shield.lefthalf.filled"),
		KindOption(kind: .schedule, label: "Schedule", icon: "calendar.badge.clock"),
	]

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					VStack(alignment: .leading, spacing: 12) {
						SectionLabel(number: "01", text: "Routine")
						Field(label: "Name") { TextField("Routine name", text: $draft.name) }
						Field(label: "What it's for") { TextField("A line about this routine", text: $draft.description, axis: .vertical) }
					}
					Hairline()
					VStack(alignment: .leading, spacing: 12) {
						HStack { SectionLabel(number: "02", text: "On your screen"); Spacer(); Text("\(draft.blocks.count)/20").mono_caption() }
						VStack(spacing: 0) {
							ForEach(Array(draft.blocks.enumerated()), id: \.element.id) { index, block in
								block_row(index: index, block: block)
								if index < draft.blocks.count - 1 { Hairline() }
							}
						}
						.background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
						.overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
						Menu {
							ForEach(Self.kinds) { option in
								Button(option.label, systemImage: option.icon) { add_block(option.kind) }.disabled(!draft.can_add(option.kind))
							}
						} label: { Label("Add block", systemImage: "plus") }.buttonStyle(QuietButtonStyle())
						Text("A routine runs on a timer or a schedule, not both. One Screen Time block per routine.").supporting()
					}
					Hairline()
					VStack(alignment: .leading, spacing: 4) {
						SectionLabel(number: "03", text: draft.is_standing ? "What happens on schedule" : "What happens when you focus")
						ToggleRow(title: draft.is_standing ? "Block while active" : "Block during focus",
							description: draft.has_engine && draft.has_screen_time ? (draft.is_standing ? "Uses your schedule and Screen Time block" : "Uses your timer and Screen Time block") : "Add a timer or schedule, plus a Screen Time block first",
							is_on: $draft.rules.block_during_focus, disabled: !(draft.has_engine && draft.has_screen_time))
						Hairline()
						ToggleRow(title: "Notify on completion",
							description: draft.has_timer ? "A notification when the timer finishes" : draft.is_standing ? "Only for timer routines" : "Add a timer first",
							is_on: $draft.rules.notify_on_complete, disabled: !draft.has_timer)
					}
				}
				.padding(Theme.pad)
				.padding(.bottom, 24)
			}
			.page()
			.navigationTitle("Edit routine")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
				ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold) }
			}
			.alert("Not quite ready to save", isPresented: Binding(get: { validation_message != nil }, set: { if !$0 { validation_message = nil } })) {
				Button("OK") { validation_message = nil }
			} message: { Text(validation_message ?? "") }
		}
	}

	private func block_row(index: Int, block: BlockDocument) -> some View {
		HStack(spacing: 10) {
			NavigationLink {
				BlockEditorView(block: Binding(get: { draft.blocks[index] }, set: { draft.blocks[index] = $0 }), groups: library.groups)
			} label: {
				HStack(spacing: 12) {
					Image(systemName: Self.icon(for: block.type)).frame(width: 28, height: 28).background(Theme.surface_hi, in: RoundedRectangle(cornerRadius: Theme.radius_small)).foregroundStyle(Theme.text_dim)
					VStack(alignment: .leading, spacing: 2) {
						Text(block.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
						Text(Self.label(for: block.type)).font(.system(size: 11)).foregroundStyle(Theme.text_faint)
					}
					Spacer()
					Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.text_faint)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain).accessibilityIdentifier("block.\(block.type.rawValue)")
			VStack(spacing: 2) {
				Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0).accessibilityLabel("Move \(block.title) up")
				Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }.disabled(index == draft.blocks.count - 1).accessibilityLabel("Move \(block.title) down")
			}
			.font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text_faint).buttonStyle(.plain)
			Button { remove(block.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text_faint).disabled(draft.blocks.count == 1).accessibilityLabel("Remove \(block.title)")
		}
		.padding(.horizontal, 12).padding(.vertical, 10)
	}

	private func move(_ index: Int, by offset: Int) {
		let destination = index + offset
		guard draft.blocks.indices.contains(destination) else { return }
		draft.blocks.swapAt(index, destination)
	}

	private func remove(_ id: String) {
		guard draft.blocks.count > 1 else { return }
		draft = draft.removing_block(id)
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
	struct ModeOption: Identifiable { let mode: ShieldMode; let label: String; let hint: String; var id: ShieldMode { mode } }
	private static let modes = [ModeOption(mode: .block, label: "Block", hint: "Lock these groups"), ModeOption(mode: .allow_only, label: "Only these", hint: "Lock everything except these groups"), ModeOption(mode: .limit, label: "Limit", hint: "Lock after so many minutes")]

	var body: some View {
		ScrollView {
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
		.page()
		.navigationTitle(EditorView.label(for: block.type))
		.navigationBarTitleDisplayMode(.inline)
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
