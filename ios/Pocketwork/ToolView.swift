import Combine
import FamilyControls
import SwiftUI

// One page: its routines on top (timers, schedules, app blocking) and its data below (checklists, counters, notes, history).
// Edit turns the same page into the block editor.
struct ToolView: View {
	let document_id: String
	var edit_on_open = false
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@EnvironmentObject private var home: HomeLocationController
	@Environment(\.scenePhase) private var scene_phase
	@StateObject private var editor = RoutinePageEditing()
	@State private var opened = false
	@State private var showing_behavior = false
	@State private var showing_picker = false
	@State private var draft_selection = FamilyActivitySelection()
	@State private var showing_groups = false
	@State private var showing_palette = false
	@State private var palette_kinds: Set<BlockKind>?
	@State private var palette_heading = "Add to this page"
	@State private var focus = SessionHistory()
	@State private var activating: PendingActivation?
	private static let routine_kinds: Set<BlockKind> = [.timer, .schedule, .screen_time]
	private static let data_kinds: Set<BlockKind> = [.checklist, .counter, .note]
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
						if editor.active {
							HStack(spacing: 8) {
								RoundedRectangle(cornerRadius: 3).fill(Theme.text).frame(width: 12, height: 12)
								TextField("Page name", text: Binding(get: { editor.draft?.name ?? "" }, set: { editor.draft?.name = $0 })).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text_dim).accessibilityIdentifier("page.name")
							}
							ForEach(document.blocks) { block in
								InlineRoutineBlock(block: editor.block(block), groups: library.groups)
									.contextMenu {
										Button("Move up", systemImage: "arrow.up") { editor.move(block.id, by: -1) }.disabled(document.blocks.first?.id == block.id)
										Button("Move down", systemImage: "arrow.down") { editor.move(block.id, by: 1) }.disabled(document.blocks.last?.id == block.id)
										Button("Remove block", systemImage: "trash", role: .destructive) { editor.draft = editor.draft?.removing_block(block.id) }.disabled(document.blocks.count == 1)
									}
							}
						} else {
							page_sections(document)
						}
					}
					.padding(Theme.pad)
					.padding(.bottom, 24).disabled(editor.saving)
					.readable()
				}
				.page()
				.navigationTitle(library.tool(document_id)?.name ?? document.name)
				.navigationBarBackButtonHidden(editor.active)
				.scrollDismissesKeyboard(.interactively)
				.navigationBarTitleDisplayMode(editor.active ? .inline : .large)
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
				.sheet(item: $activating) { pending in ActivationSheet(document: pending.document, verb: pending.verb, run: pending.run) }
				.sheet(isPresented: $showing_palette) { BlockPalette(can_add: { editor.draft?.can_add($0) == true }, add: { editor.add($0) }, kinds: palette_kinds, heading: palette_heading) }
				.fullScreenCover(isPresented: $showing_behavior) { if let draft = editor.draft { LogicEditorView(document: Binding(get: { editor.draft ?? draft }, set: { editor.draft = $0 })) } }
				.onAppear { focus = SessionHistory.load(from: .standard); if !opened { opened = true; if edit_on_open { editor.begin(document) } } }
				.onChange(of: sessions.session) { _, _ in focus = SessionHistory.load(from: .standard) }
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
					Text("This page was deleted").heading_font(17)
					Text("Go back to My pages to pick another.").supporting()
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
			Button { palette_kinds = nil; palette_heading = "Add to this page"; showing_palette = true } label: { Label("Add block", systemImage: "plus").frame(minHeight: 44).contentShape(Rectangle()) }.buttonStyle(TextButtonStyle()).accessibilityIdentifier("page.add-block")
		}.disabled(editor.saving)
	}

	// Not editing: description and headings, then Routines, then Data. Connected logic splits across both sections.
	@ViewBuilder private func page_sections(_ document: AppDocument) -> some View {
		if !document.description.isEmpty { Text(document.description).font(.system(size: 15)).foregroundStyle(Theme.text_dim) }
		ForEach(document.blocks.filter { $0.type == .heading }) { block in
			// The large navigation title already shows the page name; a heading that repeats it only adds its subtitle.
			let repeats_name = block.title.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(document.name.trimmingCharacters(in: .whitespaces)) == .orderedSame
			VStack(alignment: .leading, spacing: 4) {
				if !repeats_name { Text(block.title).heading_font(20).fixedSize(horizontal: false, vertical: true) }
				if let subtitle = block.subtitle, !subtitle.isEmpty { Text(subtitle).supporting() }
			}
			.contentShape(Rectangle())
			.onTapGesture { if can_edit(document) { begin_editing(document) } }
		}
		SectionLabel(text: "Routines").padding(.top, 4)
		ForEach(document.blocks.filter { Self.routine_kinds.contains($0.type) }) { block in routine_view(block, in: document) }
		if document.behaviors != nil {
			BehaviorPanel(document: document, after_routines: { add_button("Add routine", kinds: Self.routine_kinds, in: document) }, data_section: { data_section(document, adding: false) }, after_data: { add_button("Add data", kinds: Self.data_kinds, in: document) })
		} else {
			if !document.blocks.contains(where: { Self.routine_kinds.contains($0.type) }) { Text("No routines yet. Add a timer, a schedule, or app blocking.").supporting() }
			add_button("Add routine", kinds: Self.routine_kinds, in: document)
			data_section(document, adding: true)
		}
	}

	// With connected logic, Add data comes after the logic's own data instead (see BehaviorPanel's after_data).
	@ViewBuilder private func data_section(_ document: AppDocument, adding: Bool) -> some View {
		let blocks = document.blocks.filter { Self.data_kinds.contains($0.type) }
		SectionLabel(text: "Data").padding(.top, 8)
		ForEach(blocks) { block in
			if block.type == .note { block_view(block, in: document).contentShape(Rectangle()).onTapGesture { if can_edit(document) { begin_editing(document) } } }
			else { block_view(block, in: document) }
		}
		focus_history(document)
		if blocks.isEmpty && !document.has_timer && document.behaviors == nil { Text("Nothing tracked yet. Add a checklist, a counter, or a note.").supporting() }
		if adding { add_button("Add data", kinds: Self.data_kinds, in: document) }
	}

	@ViewBuilder private func focus_history(_ document: AppDocument) -> some View {
		if document.has_timer {
			let days = MinutesHistory.focus(focus, page: document.id)
			let total = days.reduce(0) { $0 + $1.minutes }
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text("Focus time").heading_font(15)
					Spacer()
					Text("\(total) min · 14 days").mono_caption()
				}
				if total > 0 { MinutesChart(days: days).accessibilityIdentifier("page.focus") }
				else { Text("Finish a session to see your focus time here.").supporting() }
			}
		}
	}

	private func add_button(_ title: String, kinds: Set<BlockKind>, in document: AppDocument) -> some View {
		Button {
			palette_kinds = kinds; palette_heading = title
			begin_editing(document)
			showing_palette = true
		} label: { Label(title, systemImage: "plus").frame(minHeight: 44).contentShape(Rectangle()) }
		.buttonStyle(TextButtonStyle()).disabled(!can_edit(document))
		.accessibilityIdentifier(kinds == Self.routine_kinds ? "page.add-routine" : "page.add-data")
	}

	// Routines are compact rows: what it is, its state, and the one control that runs it. Tapping the text edits the page.
	@ViewBuilder private func routine_view(_ block: BlockDocument, in document: AppDocument) -> some View {
		switch block.type {
		case .timer:
			let running = sessions.is_running(document)
			let other_running = sessions.session != nil && !running
			Card(tinted: true) {
				HStack(spacing: 12) {
					VStack(alignment: .leading, spacing: 4) {
						Text(block.title).heading_font(16)
						TimelineView(.periodic(from: .now, by: frozen ? 3600 : 1)) { timeline in
							if running, let session = sessions.session {
								let seconds = session.remaining(at: timeline.date)
								Text(String(format: "Running · %d:%02d left", seconds / 60, seconds % 60)).supporting()
							} else {
								Text("\(block.minutes ?? 25)-minute timer").supporting()
							}
						}
						if other_running { Text("Another page is running a session.").font(.system(size: 11)).foregroundStyle(Theme.text_faint) }
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.contentShape(Rectangle())
					.onTapGesture { if can_edit(document) { begin_editing(document) } }
					Button(sessions.is_busy ? "Wait" : running ? "Stop" : "Start") {
						if running { sessions.stop() } else { activate(document, verb: "Start") { Task { await sessions.start(document, groups: library.groups) } } }
					}
					.buttonStyle(QuietButtonStyle()).disabled(sessions.is_busy || other_running)
					.accessibilityLabel("\(running ? "Stop" : "Start") \(block.title)")
					.accessibilityIdentifier("tool.start")
				}
			}
		case .schedule:
			let enabled = document.enabled == true
			let needs_setup = enabled && !Activation.missing(for: document, in: Activation.context(for: document, library: library, sessions: sessions, home: home)).isEmpty
			Card(tinted: true) {
				HStack(spacing: 12) {
					VStack(alignment: .leading, spacing: 4) {
						Text(block.title).heading_font(16)
						Text(ScheduleWindow.describe(block)).supporting()
						TimelineView(.periodic(from: .now, by: frozen ? 3600 : 30)) { timeline in
							Text(ScheduleWindow.describe_status(block, enabled: enabled, at: timeline.date)).font(.system(size: 11)).foregroundStyle(Theme.text_faint)
						}
						if needs_setup {
							Button { activating = PendingActivation(document: document, verb: "Turn on") { set_standing(document, true) } } label: { Label("Needs setup", systemImage: "exclamationmark.triangle") }
								.buttonStyle(TextButtonStyle()).foregroundStyle(Theme.warning).accessibilityIdentifier("tool.finish-setup")
						}
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.contentShape(Rectangle())
					.onTapGesture { if can_edit(document) { begin_editing(document) } }
					Toggle(enabled ? "On" : "Off", isOn: Binding(get: { enabled }, set: { on in if on { activate(document, verb: "Turn on") { set_standing(document, true) } } else { set_standing(document, false) } }))
						.labelsHidden().tint(Theme.success).accessibilityLabel("Switch \(block.title) on or off").accessibilityIdentifier("tool.switch")
				}
			}
		default:
			block_view(block, in: document).contentShape(Rectangle()).onTapGesture { if can_edit(document) { begin_editing(document) } }
		}
	}

	// Runs the routine when everything it needs is in place; otherwise asks for exactly what is missing first.
	private func activate(_ document: AppDocument, verb: String, run: @escaping () -> Void) {
		if Activation.missing(for: document, in: Activation.context(for: document, library: library, sessions: sessions, home: home)).isEmpty { run() }
		else { activating = PendingActivation(document: document, verb: verb, run: run) }
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
					Text(running ? "Session in progress." : "Tap Start to begin.").supporting()
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
						Toggle(enabled ? "On" : "Off", isOn: Binding(get: { enabled }, set: { on in if on { activate(document, verb: "Turn on") { set_standing(document, true) } } else { set_standing(document, false) } }))
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
