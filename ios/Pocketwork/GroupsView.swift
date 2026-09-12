import FamilyControls
import SwiftUI

// App groups: named once, shared by every routine, filled with real apps here through Apple's private picker.
struct GroupsView: View {
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@State private var new_name = ""
	@State private var picking: AppGroup?
	@State private var draft_selection = FamilyActivitySelection()
	@State private var renaming: AppGroup?
	@State private var rename_text = ""
	@State private var pending_delete: AppGroup?

	var body: some View {
		List {
			Section {
				if library.groups.isEmpty {
					Text("Name a group like Social or Work, then choose which apps belong in it. Routines can block a group, allow only a group, or limit it to so many minutes.").foregroundStyle(.secondary)
				}
				ForEach(library.groups) { group in
					Button { choose_apps(for: group) } label: { group_row(group) }
						.accessibilityIdentifier("group.\(group.id)")
						.swipeActions(edge: .trailing) {
							Button(role: .destructive) { pending_delete = group } label: { Label("Delete", systemImage: "trash") }
							Button { renaming = group; rename_text = group.name } label: { Label("Rename", systemImage: "pencil") }.tint(.secondary)
						}
						.contextMenu {
							Button("Choose apps", systemImage: "checklist") { choose_apps(for: group) }
							Button("Rename", systemImage: "pencil") { renaming = group; rename_text = group.name }
							Button("Delete", systemImage: "trash", role: .destructive) { pending_delete = group }
						}
				}
			} header: { Text("Your groups") } footer: {
				if !library.groups.isEmpty { Text("Tap a group to choose its apps. Which apps are in a group stays on this iPhone.") }
			}
			Section {
				HStack {
					TextField("New group, e.g. Social", text: $new_name).accessibilityIdentifier("groups.new").onSubmit(add)
					Button("Add") { add() }.disabled(new_name.trimmingCharacters(in: .whitespaces).isEmpty)
				}
			} footer: { Text("Up to \(ToolLibrary.max_groups) groups. Routines that mention a new group create it here automatically.") }
		}
		.navigationTitle("App groups")
		.navigationBarTitleDisplayMode(.inline)
		.sheet(item: $picking) { group in
			NavigationStack {
				FamilyActivityPicker(selection: $draft_selection)
					.navigationTitle(group.name)
					.toolbar {
						ToolbarItem(placement: .cancellationAction) { Button("Cancel") { picking = nil } }
						ToolbarItem(placement: .confirmationAction) { Button("Done") { sessions.save_group_selection(draft_selection, for: group); picking = nil } }
					}
			}
		}
		.alert("Rename group", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
			TextField("Name", text: $rename_text)
			Button("Save") { if let group = renaming { library.rename_group(group.id, to: rename_text) }; renaming = nil }
			Button("Cancel", role: .cancel) { renaming = nil }
		} message: { Text("Every routine that uses this group follows the new name.") }
		.confirmationDialog("Delete \"\(pending_delete?.name ?? "this group")\"? The apps chosen for it are forgotten too.", isPresented: Binding(get: { pending_delete != nil }, set: { if !$0 { pending_delete = nil } }), titleVisibility: .visible) {
			Button("Delete", role: .destructive) {
				if let group = pending_delete, library.remove_group(group.id) { sessions.forget_group(group.id) }
				pending_delete = nil
			}
			Button("Cancel", role: .cancel) { pending_delete = nil }
		}
		.alert("Couldn’t complete that action", isPresented: Binding(get: { library.error_message != nil }, set: { if !$0 { library.error_message = nil } })) {
			Button("OK") { library.error_message = nil }
		} message: { Text(library.error_message ?? "") }
	}

	private func group_row(_ group: AppGroup) -> some View {
		let count = sessions.group_count(group)
		let users = library.library.routines_using(group: group.name).count
		return HStack {
			VStack(alignment: .leading, spacing: 4) {
				Text(group.name).font(.headline)
				Text(count == 0 ? "No apps yet · tap to choose" : "\(count) app\(count == 1 ? "" : "s"), categories, or sites").font(.subheadline).foregroundStyle(count == 0 ? .orange : .secondary)
				Text(users == 0 ? "Not used by a routine yet" : "Used by \(users) routine\(users == 1 ? "" : "s")").font(.caption).foregroundStyle(.tertiary)
			}
			Spacer()
			Image(systemName: "chevron.right").foregroundStyle(.tertiary)
		}
		.contentShape(Rectangle())
	}

	private func add() {
		let name = new_name.trimmingCharacters(in: .whitespaces)
		guard !name.isEmpty else { return }
		if library.add_group(name) != nil { new_name = "" }
	}

	private func choose_apps(for group: AppGroup) {
		Task {
			if await sessions.authorize_screen_time() { draft_selection = sessions.group_selection(group); picking = group }
		}
	}
}
