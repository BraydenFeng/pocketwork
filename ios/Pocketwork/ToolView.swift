import Combine
import FamilyControls
import SwiftUI

// Runs one routine, drawn like the phone preview in the web editor: the same blocks, with real timers, checklists, counters, and Screen Time.
struct ToolView: View {
	let document_id: String
	var edit_on_open = false
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@Environment(\.scenePhase) private var scene_phase
	@StateObject private var editor = RoutinePageEditing()
	@State private var opened = false
	@State private var showing_behavior = false
	@State private var showing_picker = false
	@State private var draft_selection = FamilyActivitySelection()
	@State private var showing_groups = false
	@State private var showing_palette = false
	// UI tests freeze the clock; a view that redraws every second never lets XCUITest see the app as idle.
	private static let frozen = CommandLine.arguments.contains("--ui-testing")
	private let frozen = ToolView.frozen
	private let clock = Timer.publish(every: ToolView.frozen ? 3600 : 1, on: .main, in: .common).autoconnect()

	var body: some View {
		Group {
			if let document = library.tool(document_id), document.home_allowance != nil { HomeAllowanceView(document: document, edit_on_open: edit_on_open) }
			else if let document = editor.draft ?? library.tool(document_id) {
				ScrollView {
					VStack(alignment: .leading, spacing: 20) {
						HStack(spacing: 8) {
							RoundedRectangle(cornerRadius: 3).fill(Theme.text).frame(width: 12, height: 12)
							if editor.active {
								TextField("Routine name", text: Binding(get: { editor.draft?.name ?? "" }, set: { editor.draft?.name = $0 })).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text_dim).accessibilityIdentifier("page.name")
							} else {
								Button { begin_editing(document) } label: { HStack(spacing: 6) { Text(document.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text_dim); Image(systemName: "pencil").font(.system(size: 11)).foregroundStyle(Theme.text_faint) } }
									.buttonStyle(.plain).disabled(!can_edit(document)).accessibilityLabel("Edit \(document.name)")
							}
						}
						ForEach(document.blocks) { block in
							if editor.active {
								InlineRoutineBlock(block: editor.block(block), groups: library.groups)
									.contextMenu {
										Button("Move up", systemImage: "arrow.up") { editor.move(block.id, by: -1) }.disabled(document.blocks.first?.id == block.id)
										Button("Move down", systemImage: "arrow.down") { editor.move(block.id, by: 1) }.disabled(document.blocks.last?.id == block.id)
										Button("Remove block", systemImage: "trash", role: .destructive) { editor.draft = editor.draft?.removing_block(block.id) }.disabled(document.blocks.count == 1)
									}
							} else if [.heading, .note, .schedule, .screen_time].contains(block.type) {
								// Tapping a settings-only block opens the page for editing, like clicking into a Notion block.
								block_view(block, in: document).contentShape(Rectangle()).onTapGesture { if can_edit(document) { begin_editing(document) } }
							} else { block_view(block, in: document) }
						}
						if !editor.active, document.behaviors != nil { BehaviorPanel(document: document) }
						if !editor.active, can_edit(document) {
							Button { begin_editing(document) } label: { Label("Edit this page", systemImage: "pencil") }.buttonStyle(TextButtonStyle()).frame(minHeight: 44)
						}
						Text("Made for you. By you.").mono_caption().padding(.top, 8)
					}
					.padding(Theme.pad)
					.padding(.bottom, 24).disabled(editor.saving)
				}
				.page()
				.navigationTitle(library.tool(document_id)?.name ?? document.name)
				.navigationBarBackButtonHidden(editor.active)
				.scrollDismissesKeyboard(.interactively)
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .topBarTrailing) {
						if editor.active { Button("Save") { Task { await editor.save(library: library, sessions: sessions) } }.fontWeight(.semibold).foregroundStyle(Theme.accent).disabled(editor.saving || sessions.is_busy) }
						else { Button("Edit") { begin_editing(document) }.disabled(!can_edit(document)).accessibilityIdentifier("tool.edit") }
					}
					ToolbarItem(placement: .topBarTrailing) {
						Menu {
							Button("Reset checklist and counters", systemImage: "arrow.counterclockwise") { sessions.reset_progress(for: document) }
							// The node canvas is for people who want it; the page itself is the editor.
							Button("Advanced logic…", systemImage: "point.3.connected.trianglepath.dotted") { if !editor.active { begin_editing(document) }; showing_behavior = true }.disabled(!can_edit(document) && !editor.active).accessibilityIdentifier("editor.logic")
							Button(role: .destructive) { clear_everything() } label: { Label("Clear all focus restrictions", systemImage: "lock.open") }.disabled(sessions.is_busy)
						} label: { Image(systemName: "ellipsis") }
					}
				}
				.safeAreaInset(edge: .bottom) { if editor.active { editing_bar } }
				.sheet(isPresented: $showing_palette) { BlockPalette(can_add: { editor.draft?.can_add($0) == true }, add: { editor.add($0) }) }
				.fullScreenCover(isPresented: $showing_behavior) { if let draft = editor.draft { LogicEditorView(document: Binding(get: { editor.draft ?? draft }, set: { editor.draft = $0 })) } }
				.onAppear { if !opened { opened = true; if edit_on_open { editor.begin(document) } } }
				.alert("Couldn’t save changes", isPresented: Binding(get: { editor.failure != nil }, set: { if !$0 { editor.failure = nil } })) { Button("OK") { editor.failure = nil } } message: { Text(editor.failure ?? "") }
				.navigationDestination(isPresented: $showing_groups) { GroupsView() }
				.sheet(isPresented: $showing_picker) {
					NavigationStack {
						FamilyActivityPicker(selection: $draft_selection)
							.navigationTitle("Choose distractions")
							.toolbar {
								ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showing_picker = false } }
								ToolbarItem(placement: .confirmationAction) { Button("Done") { sessions.save_selection(draft_selection, for: document); showing_picker = false } }
							}
					}
				}
			} else {
				VStack(spacing: 12) {
					Image(systemName: "square.stack.3d.up").font(.system(size: 28)).foregroundStyle(Theme.text_faint)
					Text("This routine was deleted").heading_font(17)
					Text("Go back to My routines to pick another.").supporting()
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.page()
			}
		}
		.onReceive(clock) { _ in
			if !frozen, let session = sessions.session, session.has_ended(at: .now) { sessions.refresh() }
		}
		.onChange(of: scene_phase) { _, phase in if phase == .active { sessions.refresh() } }
		.alert("Couldn’t complete that action", isPresented: Binding(get: { sessions.error_message != nil }, set: { if !$0 { sessions.error_message = nil } })) {
			Button("OK") { sessions.error_message = nil }
		} message: { Text(sessions.error_message ?? "") }
	}

	private var editing_bar: some View {
		EditorBar {
			Button("Cancel") { editor.cancel() }.buttonStyle(TextButtonStyle()).frame(minHeight: 44)
			Spacer()
			if editor.saving { ProgressView() }
			Button { showing_palette = true } label: { Label("Add block", systemImage: "plus").frame(minHeight: 44).contentShape(Rectangle()) }.buttonStyle(TextButtonStyle()).accessibilityIdentifier("page.add-block")
		}.disabled(editor.saving)
	}

	private func can_edit(_ document: AppDocument) -> Bool { !sessions.is_running(document) && !sessions.is_busy }
	private func begin_editing(_ document: AppDocument) { editor.begin(document) }

	private func clear_everything() {
		Task { for id in await sessions.clear_everything() { library.set_enabled(id, false) } }
	}

	private func set_standing(_ document: AppDocument, _ enabled: Bool) {
		if sessions.set_standing(document, enabled: enabled, groups: library.groups) { library.set_enabled(document.id, enabled) }
	}

	@ViewBuilder private func block_view(_ block: BlockDocument, in document: AppDocument) -> some View {
		switch block.type {
		case .heading:
			VStack(alignment: .leading, spacing: 8) {
				Text("Your space, your pace").mono_caption().textCase(.uppercase)
				Text(block.title).font(.system(size: 30, weight: .semibold)).tracking(-1).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
				Text(block.subtitle ?? "").font(.system(size: 15)).foregroundStyle(Theme.text_faint)
			}
			.padding(.leading, 12)
			.overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 2) }
		case .timer:
			let running = sessions.is_running(document)
			let other_running = sessions.session != nil && !running
			Card(tinted: true) {
				VStack(alignment: .leading, spacing: 12) {
					Text(block.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text_dim)
					TimelineView(.periodic(from: .now, by: frozen ? 3600 : 1)) { timeline in
						let seconds = running ? (sessions.session?.remaining(at: timeline.date) ?? 0) : (block.minutes ?? 25) * 60
						Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).font(.system(size: 56, weight: .medium, design: .monospaced)).tracking(-2).foregroundStyle(Theme.text)
					}
					Text(running ? "One thing at a time." : "A fresh start is one tap away.").supporting()
					Button {
						if running { sessions.stop() } else { Task { await sessions.start(document, groups: library.groups) } }
					} label: {
						Label(sessions.is_busy ? "Preparing…" : running ? "End session" : "Start focusing", systemImage: running ? "pause.fill" : "play.fill")
					}
					.buttonStyle(PrimaryButtonStyle()).disabled(sessions.is_busy || other_running)
					if other_running { Text("Another routine is running a session. End it first.").supporting() }
				}
			}
		case .schedule:
			let enabled = document.enabled == true
			Card(tinted: true) {
				VStack(alignment: .leading, spacing: 10) {
					HStack {
						Label(block.title, systemImage: "calendar.badge.clock").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text_dim)
						Spacer()
						Text(enabled ? "On" : "Off").font(.system(size: 13)).foregroundStyle(Theme.text_dim)
						Toggle(enabled ? "On" : "Off", isOn: Binding(get: { enabled }, set: { set_standing(document, $0) }))
							.labelsHidden().tint(Theme.success).accessibilityLabel("Switch \(block.title) on or off").accessibilityIdentifier("tool.switch")
					}
					Text(ScheduleWindow.describe(block)).heading_font(22)
					TimelineView(.periodic(from: .now, by: frozen ? 3600 : 30)) { timeline in
						Text(ScheduleWindow.describe_status(block, enabled: enabled, at: timeline.date)).supporting()
					}
					Text("Runs by itself once it is on, even with the app closed.").font(.system(size: 11)).foregroundStyle(Theme.text_faint)
				}
			}
		case .checklist:
			let items = block.items ?? []
			let done_count = items.filter { sessions.completed($0.id, in: document) }.count
			VStack(alignment: .leading, spacing: 0) {
				HStack {
					Text(block.title).heading_font(15)
					Spacer()
					Text("\(done_count)/\(items.count)").mono_caption()
				}
				.padding(.bottom, 8)
				ForEach(items) { item in
					let done = sessions.completed(item.id, in: document)
					Button { sessions.toggle_task(item.id, in: document) } label: {
						HStack(alignment: .top, spacing: 12) {
							Image(systemName: done ? "checkmark.square.fill" : "square").foregroundStyle(done ? Theme.text : Theme.border_hi)
							Text(item.text).font(.system(size: 15)).foregroundStyle(done ? Theme.text_faint : Theme.text).strikethrough(done).multilineTextAlignment(.leading)
							Spacer(minLength: 0)
						}
						.padding(.vertical, 10).contentShape(Rectangle())
					}
					.buttonStyle(.plain).accessibilityValue(done ? "Complete" : "Incomplete")
					Hairline()
				}
			}
		case .screen_time:
			let running = sessions.is_running(document)
			let standing_active = document.enabled == true && document.schedule.map { ScheduleWindow.status($0, at: .now).active } == true
			let active = (running && sessions.session?.blocks_apps == true) || standing_active
			Card {
				VStack(alignment: .leading, spacing: 10) {
					HStack(spacing: 10) {
						Image(systemName: active ? "checkmark.shield.fill" : "shield").font(.system(size: 18)).foregroundStyle(active ? Theme.success : Theme.text_dim)
						VStack(alignment: .leading, spacing: 2) {
							Text(block.title).heading_font(15)
							Text(block.shield_description).supporting()
						}
					}
					if block.group_names.isEmpty {
						Text(active ? "Focus restrictions are active." : "\(sessions.selected_count(for: document)) apps, categories, or websites selected for this routine.").supporting()
						Button("Choose apps privately") {
							Task { if await sessions.authorize_screen_time() { draft_selection = sessions.selection(for: document); showing_picker = true } }
						}.buttonStyle(QuietButtonStyle()).disabled(running || sessions.is_busy || document.enabled == true)
					} else {
						Hairline()
						ForEach(block.group_names, id: \.self) { name in
							let group = library.groups.first { $0.name.lowercased() == name.lowercased() }
							let count = group.map { sessions.group_count($0) } ?? 0
							HStack {
								Text(name).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text)
								Spacer()
								Text(group == nil ? "not created yet" : count == 0 ? "no apps yet" : "\(count) selected").font(.system(size: 12)).foregroundStyle(group == nil || count == 0 ? Theme.warning : Theme.text_faint)
							}
						}
						Text(active ? "Focus restrictions are active." : block.shield_mode == .limit ? "Locks after \(block.limit_minutes ?? 0) minutes of use inside this routine." : block.shield_mode == .allow_only ? "Everything except these groups is locked while this runs." : "These groups are locked while this runs.").font(.system(size: 11)).foregroundStyle(Theme.text_faint)
						Button { showing_groups = true } label: { Label("Set up app groups", systemImage: "square.grid.2x2") }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("tool.groups")
					}
				}
			}
		case .counter:
			let value = sessions.count(block, in: document)
			let target = block.target ?? 1
			Card {
				VStack(alignment: .leading, spacing: 10) {
					Text(block.title).heading_font(15)
					HStack(alignment: .firstTextBaseline) {
						Text("\(value)").font(.system(size: 32, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
						Text("/ \(target)").font(.system(size: 14)).foregroundStyle(Theme.text_faint)
						Spacer()
						Button { sessions.increment(block, in: document) } label: { Label(value >= target ? "Done" : "Add one", systemImage: value >= target ? "checkmark" : "plus") }.buttonStyle(QuietButtonStyle()).disabled(value >= target)
					}
				}
			}
		case .note:
			VStack(alignment: .leading, spacing: 6) {
				Text(block.title).heading_font(15)
				Text(block.text ?? "").font(.system(size: 15)).foregroundStyle(Theme.text_dim)
			}
		}
	}
}
