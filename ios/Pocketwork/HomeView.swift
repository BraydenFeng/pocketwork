import OSLog
import SwiftUI
import UniformTypeIdentifiers

// The front door: saved tools first, then routines that already work. The editor only appears after a choice.
struct HomeView: View {
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@State private var path: [String] = []
	@State private var showing_import = false
	@State private var pending_delete: LibraryEntry?
	private let logger = Logger(subsystem: "Pocketwork", category: "FileImport")

	var body: some View {
		NavigationStack(path: $path) {
			List {
				if library.storage_blocked {
					Section {
						Label("Your saved tools could not be opened. Nothing has been overwritten.", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
						Button("Replace unreadable data", role: .destructive) { library.replace_unreadable() }
					}
				}
				Section {
					if library.sorted_tools.isEmpty {
						Text("Nothing here yet. Choose a routine below and it becomes your first one. You can change every part of it afterwards.").foregroundStyle(.secondary)
					}
					ForEach(library.sorted_tools) { entry in
						NavigationLink(value: entry.document.id) { tool_row(entry) }
							.accessibilityIdentifier("tool.\(entry.document.id)")
							.swipeActions(edge: .trailing) {
								Button(role: .destructive) { pending_delete = entry } label: { Label("Delete", systemImage: "trash") }
								Button { duplicate(entry.document.id) } label: { Label("Duplicate", systemImage: "doc.on.doc") }.tint(.secondary)
							}
							.contextMenu {
								Button("Duplicate", systemImage: "doc.on.doc") { duplicate(entry.document.id) }
								Button("Delete", systemImage: "trash", role: .destructive) { pending_delete = entry }
							}
					}
				} header: { Text("My routines") } footer: {
					if !library.sorted_tools.isEmpty { Text("Swipe a routine to duplicate or delete it. Scheduled routines have a switch.") }
				}
				Section {
					ForEach(library.routines) { routine in
						Button { if let document = library.create(from: routine) { path = [document.id] } } label: { routine_row(routine) }
							.accessibilityIdentifier("routine.\(routine.template_id)")
					}
					Button { if let document = library.create_blank() { path = [document.id] } } label: {
						VStack(alignment: .leading, spacing: 4) {
							Label("Blank routine", systemImage: "plus").font(.headline)
							Text("Start from nothing and add the blocks you want.").font(.subheadline).foregroundStyle(.secondary)
						}
					}
				} header: { Text("Ready-made routines") } footer: {
					Text("Some run when you start them. Some switch themselves on at set times. All keep the apps you choose out of the way.")
				}
			}
			.navigationTitle("My routines")
			.navigationDestination(for: String.self) { id in ToolView(document_id: id) }
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Menu {
						Button("Add from file", systemImage: "square.and.arrow.down") { showing_import = true }
						Button(role: .destructive) { for id in sessions.clear_everything() { library.set_enabled(id, false) } } label: { Label("Clear all focus restrictions", systemImage: "lock.open") }.disabled(sessions.is_busy)
					} label: { Image(systemName: "ellipsis.circle") }
				}
			}
			.fileImporter(isPresented: $showing_import, allowedContentTypes: [.json]) { result in import_file(result) }
			.confirmationDialog("Delete \"\(pending_delete?.document.name ?? "this routine")\"? This cannot be undone.", isPresented: Binding(get: { pending_delete != nil }, set: { if !$0 { pending_delete = nil } }), titleVisibility: .visible) {
				Button("Delete", role: .destructive) {
					if let entry = pending_delete { sessions.forget(entry.document.id); library.delete(entry.document.id) }
					pending_delete = nil
				}
				Button("Cancel", role: .cancel) { pending_delete = nil }
			}
			.alert("Couldn’t complete that action", isPresented: Binding(get: { library.error_message != nil }, set: { if !$0 { library.error_message = nil } })) {
				Button("OK") { library.error_message = nil }
			} message: { Text(library.error_message ?? "") }
		}
		.tint(.primary)
	}

	private func tool_row(_ entry: LibraryEntry) -> some View {
		HStack(alignment: .center, spacing: 12) {
			VStack(alignment: .leading, spacing: 4) {
				HStack {
					Text(entry.document.name).font(.headline)
					if sessions.session?.document_id == entry.document.id { Image(systemName: "circle.fill").font(.caption2).foregroundStyle(.green).accessibilityLabel("Session running") }
				}
				Text(ToolCopy.summary(entry.document).uppercased()).font(.caption2.monospaced()).foregroundStyle(.secondary)
				if !entry.document.description.isEmpty { Text(entry.document.description).font(.subheadline).foregroundStyle(.secondary) }
				if let schedule = entry.document.schedule {
					Text(ScheduleWindow.describe_status(schedule, enabled: entry.document.enabled == true, at: .now)).font(.caption).foregroundStyle(.tertiary)
				} else {
					Text(ToolCopy.edited(entry, now: .now)).font(.caption).foregroundStyle(.tertiary)
				}
			}
			if entry.document.is_standing {
				Spacer()
				Toggle("On", isOn: Binding(get: { entry.document.enabled == true }, set: { enabled in
					if sessions.set_standing(entry.document, enabled: enabled) { library.set_enabled(entry.document.id, enabled) }
				})).labelsHidden().accessibilityLabel("Switch \(entry.document.name) on or off")
			}
		}
		.padding(.vertical, 4)
	}

	private func routine_row(_ routine: Routine) -> some View {
		HStack {
			VStack(alignment: .leading, spacing: 4) {
				Text(routine.name).font(.headline)
				Text(routine.tagline).font(.subheadline).foregroundStyle(.secondary)
			}
			Spacer()
			Image(systemName: "arrow.right").foregroundStyle(.secondary)
		}
		.contentShape(Rectangle())
	}

	private func duplicate(_ id: String) { _ = library.duplicate(id) }

	private func import_file(_ result: Result<URL, Error>) {
		do {
			let url = try result.get()
			guard url.startAccessingSecurityScopedResource() else { throw DocumentError.invalid("Permission to read this file was not granted.") }
			defer { url.stopAccessingSecurityScopedResource() }
			let handle = try FileHandle(forReadingFrom: url)
			defer { do { try handle.close() } catch { logger.error("Could not close imported file: \(error.localizedDescription, privacy: .public)") } }
			let data = try handle.read(upToCount: 100_001) ?? Data()
			if let document = library.import_document(try AppDocument.decode(data)) { path = [document.id] }
		} catch { library.report(error) }
	}
}
