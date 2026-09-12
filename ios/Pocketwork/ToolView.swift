import Combine
import FamilyControls
import SwiftUI

// Runs one tool: the same blocks the editor shows, with real timers, checklists, counters, and Screen Time.
struct ToolView: View {
	let document_id: String
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@Environment(\.scenePhase) private var scene_phase
	@State private var showing_editor = false
	@State private var showing_picker = false
	@State private var draft_selection = FamilyActivitySelection()
	private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

	var body: some View {
		Group {
			if let document = library.tool(document_id) {
				ScrollView {
					VStack(alignment: .leading, spacing: 24) {
						ForEach(document.blocks) { block in block_view(block, in: document) }
						Text("Runs on this iPhone · local data only").font(.caption).foregroundStyle(.secondary)
					}
					.padding(24)
				}
				.navigationTitle(document.name)
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .topBarTrailing) { Button("Edit") { showing_editor = true }.disabled(sessions.is_running(document)) }
					ToolbarItem(placement: .topBarTrailing) {
						Menu {
							Button("Reset checklist and counters", systemImage: "arrow.counterclockwise") { sessions.reset_progress(for: document) }
							Button(role: .destructive) { sessions.stop() } label: { Label("Clear all focus restrictions", systemImage: "lock.open") }.disabled(sessions.is_busy)
						} label: { Image(systemName: "ellipsis.circle") }
					}
				}
				.sheet(isPresented: $showing_editor) { EditorView(document: document) }
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
				ContentUnavailableView("This tool was deleted", systemImage: "square.stack.3d.up", description: Text("Go back to My tools to pick another."))
			}
		}
		.tint(.primary)
		.onReceive(clock) { _ in
			if let session = sessions.session, session.has_ended(at: .now) { sessions.refresh() }
		}
		.onChange(of: scene_phase) { _, phase in if phase == .active { sessions.refresh() } }
		.alert("Couldn’t complete that action", isPresented: Binding(get: { sessions.error_message != nil }, set: { if !$0 { sessions.error_message = nil } })) {
			Button("OK") { sessions.error_message = nil }
		} message: { Text(sessions.error_message ?? "") }
	}

	@ViewBuilder private func block_view(_ block: BlockDocument, in document: AppDocument) -> some View {
		switch block.type {
		case .heading:
			VStack(alignment: .leading, spacing: 12) {
				Text(block.title).font(.largeTitle.weight(.semibold))
				Text(block.subtitle ?? "").font(.subheadline).foregroundStyle(.secondary)
			}
		case .timer:
			let running = sessions.is_running(document)
			let other_running = sessions.session != nil && !running
			VStack(alignment: .leading, spacing: 12) {
				Text(block.title).font(.headline)
				TimelineView(.periodic(from: .now, by: 1)) { timeline in
					let seconds = running ? (sessions.session?.remaining(at: timeline.date) ?? 0) : (block.minutes ?? 25) * 60
					Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).font(.system(size: 56, weight: .medium, design: .rounded)).monospacedDigit()
				}
				Button {
					if running { sessions.stop() } else { Task { await sessions.start(document) } }
				} label: {
					Label(sessions.is_busy ? "Preparing…" : running ? "End session" : "Start focusing", systemImage: running ? "stop.fill" : "play.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
				}
				.buttonStyle(.borderedProminent).disabled(sessions.is_busy || other_running)
				Text(other_running ? "Another tool is running a session. End it first." : "You can end a session at any time.").font(.caption).foregroundStyle(.secondary)
			}
			.padding(20).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
		case .checklist:
			VStack(alignment: .leading, spacing: 12) {
				Text(block.title).font(.headline)
				ForEach(block.items ?? []) { item in
					let done = sessions.completed(item.id, in: document)
					Button { sessions.toggle_task(item.id, in: document) } label: {
						HStack(alignment: .top, spacing: 12) {
							Image(systemName: done ? "checkmark.square.fill" : "square")
							Text(item.text).strikethrough(done).multilineTextAlignment(.leading)
							Spacer(minLength: 0)
						}.padding(.vertical, 8).contentShape(Rectangle())
					}.buttonStyle(.plain).accessibilityValue(done ? "Complete" : "Incomplete")
					Divider()
				}
			}
		case .screen_time:
			let running = sessions.is_running(document)
			VStack(alignment: .leading, spacing: 12) {
				Label(block.title, systemImage: "shield.lefthalf.filled").font(.headline)
				Text(running && sessions.session?.blocks_apps == true ? "Focus restrictions are active." : "\(sessions.selected_count(for: document)) apps, categories, or websites selected for this tool.").font(.subheadline).foregroundStyle(.secondary)
				Button("Choose apps privately") {
					Task { if await sessions.authorize_screen_time() { draft_selection = sessions.selection(for: document); showing_picker = true } }
				}.buttonStyle(.bordered).disabled(running || sessions.is_busy)
			}
		case .counter:
			let value = sessions.count(block, in: document)
			VStack(alignment: .leading, spacing: 12) {
				Text(block.title).font(.headline)
				HStack {
					Text("\(value) / \(block.target ?? 1)").font(.title2).monospacedDigit()
					Spacer()
					Button("Add one", systemImage: "plus") { sessions.increment(block, in: document) }.buttonStyle(.bordered).disabled(value >= (block.target ?? 1))
				}
			}
		case .note:
			VStack(alignment: .leading, spacing: 8) { Text(block.title).font(.headline); Text(block.text ?? "").foregroundStyle(.secondary) }
		}
	}
}
