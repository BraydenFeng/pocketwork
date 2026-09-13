import FamilyControls
import OSLog
import SwiftUI
import UniformTypeIdentifiers

// The front door, drawn like the web editor's My routines page: saved routines as cards, then app groups, then ready-made routines.
struct HomeView: View {
	@EnvironmentObject private var cloud: CloudController
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	private struct RoutineRoute: Hashable { let id: String; var editing = false }
	@State private var path: [RoutineRoute] = []
	@State private var showing_groups = false
	@State private var showing_import = false
	@State private var pending_delete: LibraryEntry?
	@State private var editing: RoutineDraft?
	@State private var picking_group: AppGroup?
	@State private var showing_account = false
	private let logger = Logger(subsystem: "Pocketwork", category: "FileImport")

	var body: some View {
		NavigationStack(path: $path) {
			ScrollView {
				VStack(alignment: .leading, spacing: 0) {
					intro
					if !cloud.signed_in { AccountView() }
					Hairline()
					section(number: "01", label: "My routines", heading: library.sorted_tools.isEmpty ? "Nothing here yet." : "Pick up where you left off.", supporting: library.sorted_tools.isEmpty ? "Create a routine here, or sign in to bring in the routines you made on your computer." : nil) {
						if library.storage_blocked { storage_warning }
						Button { editing = RoutineDraft(document: AppDocument.blank(), is_new: true) } label: { Label("New routine", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle(accent: true))
						ForEach(library.sorted_tools) { entry in routine_card(entry) }
					}
					Hairline()
					section(number: "02", label: "App groups", heading: "Your apps, grouped.", supporting: nil) {
						ForEach(library.groups) { group in
							Button { picking_group = group } label: {
								DocumentRow(icon: "square.grid.2x2") {
									HStack {
										VStack(alignment: .leading, spacing: 4) { Text(group.name).heading_font(15); Text("\(sessions.group_count(group)) selected · choose apps").supporting() }
										Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.text_faint)
									}
								}
							}.buttonStyle(.plain).accessibilityIdentifier("home.group.\(group.id)")
							Hairline()
						}
						Button { showing_groups = true } label: { Label(library.groups.isEmpty ? "Create an app group" : "Manage app groups", systemImage: "plus") }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("home.groups")
					}

					Hairline()
					footer
				}
			}
			.refreshable { await cloud.sync() }
			.page()
			.navigationTitle("My routines")
			.navigationBarTitleDisplayMode(.inline)
			.navigationDestination(for: RoutineRoute.self) { route in ToolView(document_id: route.id, edit_on_open: route.editing) }
			.navigationDestination(isPresented: $showing_groups) { GroupsView() }
			.toolbar {
				ToolbarItem(placement: .topBarLeading) { brand }
				ToolbarItem(placement: .topBarTrailing) {
					Menu {
						Button("Account & sync", systemImage: "person.crop.circle") { showing_account = true }
						Button("App groups", systemImage: "square.grid.2x2") { showing_groups = true }
						Button("Add from file", systemImage: "square.and.arrow.down") { showing_import = true }
						Button(role: .destructive) { Task { for id in await sessions.clear_everything() { library.set_enabled(id, false) } } } label: { Label("Clear all focus restrictions", systemImage: "lock.open") }.disabled(sessions.is_busy)
					} label: { Image(systemName: "ellipsis") }
				}
			}
			.sheet(item: $editing) { item in RoutineEditorSheet(item: item) }
			.sheet(item: $picking_group) { group in AppGroupSelectionSheet(group: group) }
			.sheet(isPresented: $showing_account) { NavigationStack { AccountView().navigationTitle("Account & sync").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showing_account = false } } } } }
			.fileImporter(isPresented: $showing_import, allowedContentTypes: [.json]) { result in import_file(result) }
			.confirmationDialog("Delete \"\(pending_delete?.document.name ?? "this routine")\"? This cannot be undone.", isPresented: Binding(get: { pending_delete != nil }, set: { if !$0 { pending_delete = nil } }), titleVisibility: .visible) {
				Button("Delete", role: .destructive) {
					if let entry = pending_delete { Task { await sessions.forget(entry.document.id); library.delete(entry.document.id) } }
					pending_delete = nil
				}
				Button("Cancel", role: .cancel) { pending_delete = nil }
			}
			.alert("Couldn’t complete that action", isPresented: Binding(get: { library.error_message != nil }, set: { if !$0 { library.error_message = nil } })) {
				Button("OK") { library.error_message = nil }
			} message: { Text(library.error_message ?? "") }
		}
	}

	private var brand: some View {
		HStack(spacing: 6) {
			Image(systemName: "square.stack.3d.up").font(.system(size: 15, weight: .medium))
			Text("pocketwork").font(.system(size: 17, weight: .semibold)).tracking(-0.3) + Text(".").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text_faint)
		}
		.foregroundStyle(Theme.text)
	}

	private var intro: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("My routines").heading_font(28)
			Text("Your own little tools.").supporting()
			HStack(spacing: 8) {
				Circle().fill(library.storage_blocked ? Theme.danger : Theme.success).frame(width: 6, height: 6)
				Text(library.storage_blocked ? "Saved routines need attention" : "\(library.sorted_tools.count) saved on this iPhone").font(.system(size: 13)).foregroundStyle(library.storage_blocked ? Theme.danger : Theme.text_faint)
			}.padding(.top, 4)
		}
		.padding(Theme.pad)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Theme.surface)
	}

	private var storage_warning: some View {
		Card(tinted: true) {
			VStack(alignment: .leading, spacing: 10) {
				Label("Your saved routines could not be opened. Nothing has been overwritten.", systemImage: "exclamationmark.triangle").font(.system(size: 13)).foregroundStyle(Theme.danger)
				Button("Replace unreadable data") { library.replace_unreadable() }.buttonStyle(QuietButtonStyle(danger: true))
			}
		}
	}

	private var footer: some View {
		HStack {
			HStack(spacing: 8) { Circle().fill(Theme.border_hi).frame(width: 6, height: 6); Text("Your own little tools.") }
			Spacer()
			Text("PERSONAL WORKSPACE")
		}
		.mono_caption()
		.padding(Theme.pad)
		.background(Theme.surface)
	}

	private func section<Content: View>(number: String, label: String, heading: String, supporting: String?, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: Theme.gap) {
			VStack(alignment: .leading, spacing: 6) {
				SectionLabel(number: number, text: label)
				Text(heading).heading_font(20)
				if let supporting { Text(supporting).supporting() }
			}
			content()
		}
		.padding(Theme.pad)
	}

	private func routine_card(_ entry: LibraryEntry) -> some View {
		let document = entry.document
		return Card {
			VStack(alignment: .leading, spacing: 8) {
				Button { path = [RoutineRoute(id: document.id)] } label: {
					VStack(alignment: .leading, spacing: 8) {
						HStack(spacing: 8) {
							Text(document.name).heading_font(17)
							if sessions.session?.document_id == document.id { Circle().fill(Theme.success).frame(width: 6, height: 6).accessibilityLabel("Session running") }
							Spacer()
							Image(systemName: "arrow.right").foregroundStyle(Theme.text_faint)
						}
						Text(ToolCopy.summary(document)).mono_caption().textCase(.uppercase)
						if !document.description.isEmpty { Text(document.description).supporting() }
						if document.home_allowance != nil {
							Text(document.enabled == true ? "Home allowance on" : "Home allowance off").supporting()
						} else if let schedule = document.schedule {
							Text(ScheduleWindow.describe_status(schedule, enabled: document.enabled == true, at: .now)).font(.system(size: 11)).foregroundStyle(Theme.text_faint)
						} else {
							Text(ToolCopy.edited(entry, now: .now)).font(.system(size: 11)).foregroundStyle(Theme.text_faint)
						}
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain).accessibilityLabel("Open \(document.name)").accessibilityIdentifier("tool.\(document.id)")
				Hairline()
				HStack(spacing: 16) {
					if document.is_standing && document.home_allowance == nil {
						Toggle("On", isOn: Binding(get: { document.enabled == true }, set: { enabled in
							if sessions.set_standing(document, enabled: enabled, groups: library.groups) { library.set_enabled(document.id, enabled) }
						})).labelsHidden().tint(Theme.success).accessibilityLabel("Switch \(document.name) on or off")
						Text(document.enabled == true ? "On" : "Off").font(.system(size: 13)).foregroundStyle(Theme.text_dim)
						Spacer()
					}
					Button { path = [RoutineRoute(id: document.id, editing: true)] } label: { Label("Edit", systemImage: "pencil") }.buttonStyle(TextButtonStyle()).accessibilityLabel("Edit \(document.name)").accessibilityIdentifier("home.edit.\(document.id)").disabled(sessions.is_busy || sessions.is_running(document))
					Spacer()
					Menu {
						Button("Duplicate", systemImage: "doc.on.doc") { _ = library.duplicate(document.id) }.disabled(document.home_allowance != nil)
						Button("Delete", systemImage: "trash", role: .destructive) { pending_delete = entry }
					} label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).foregroundStyle(Theme.text_faint) }.accessibilityLabel("More options for \(document.name)")
				}
			}
		}
	}

	private func import_file(_ result: Result<URL, Error>) {
		do {
			let url = try result.get()
			guard url.startAccessingSecurityScopedResource() else { throw DocumentError.invalid("Permission to read this file was not granted.") }
			defer { url.stopAccessingSecurityScopedResource() }
			let handle = try FileHandle(forReadingFrom: url)
			defer { do { try handle.close() } catch { logger.error("Could not close imported file: \(error.localizedDescription, privacy: .public)") } }
			let data = try handle.read(upToCount: 100_001) ?? Data()
			if let document = library.import_document(try AppDocument.decode(data)) { path = [RoutineRoute(id: document.id)] }
		} catch { library.report(error) }
	}
}
