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
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				VStack(alignment: .leading, spacing: 6) {
					SectionLabel(number: "02", text: "App groups")
					Text("Name the apps once. Every routine can use them.").heading_font(20)
					Text("Tap a group to choose its apps with Apple's private picker. Which apps are in a group stays on this iPhone. Routines can block a group, allow only a group, or limit it to so many minutes.").supporting()
				}
				if library.groups.isEmpty {
					Card(tinted: true, dashed: true) { Text("No groups yet. Name one below, then tap it to choose its apps.").supporting() }
				}
				ForEach(library.groups) { group in group_card(group) }
				Card(tinted: true) {
					VStack(alignment: .leading, spacing: 10) {
						Text("New group").heading_font(15)
						HStack(spacing: 8) {
							Field(label: "Name") { TextField("Social, Games, Work…", text: $new_name).accessibilityIdentifier("groups.new").onSubmit(add) }
							Button { add() } label: { Label("Add", systemImage: "plus") }.buttonStyle(QuietButtonStyle()).disabled(new_name.trimmingCharacters(in: .whitespaces).isEmpty).padding(.top, 18)
						}
						Text("Up to \(ToolLibrary.max_groups) groups. Routines that mention a new group create it here automatically.").supporting()
					}
				}
			}
			.padding(Theme.pad)
			.padding(.bottom, 24)
		}
		.page()
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

	private func group_card(_ group: AppGroup) -> some View {
		let count = sessions.group_count(group)
		let users = library.library.routines_using(group: group.name).count
		return Card {
			VStack(alignment: .leading, spacing: 8) {
				Button { choose_apps(for: group) } label: {
					HStack(spacing: 10) {
						Image(systemName: count == 0 ? "shield" : "checkmark.shield.fill").font(.system(size: 18)).foregroundStyle(count == 0 ? Theme.warning : Theme.success)
						VStack(alignment: .leading, spacing: 2) {
							Text(group.name).heading_font(17)
							Text(count == 0 ? "No apps yet · tap to choose" : "\(count) app\(count == 1 ? "" : "s"), categories, or sites").font(.system(size: 13)).foregroundStyle(count == 0 ? Theme.warning : Theme.text_dim)
							Text(users == 0 ? "Not used by a routine yet" : "Used by \(users) routine\(users == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(Theme.text_faint)
						}
						Spacer()
						Image(systemName: "arrow.right").foregroundStyle(Theme.text_faint)
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain).accessibilityIdentifier("group.\(group.id)")
				Hairline()
				HStack(spacing: 16) {
					Button { renaming = group; rename_text = group.name } label: { Label("Rename", systemImage: "pencil") }.buttonStyle(TextButtonStyle())
					Button { pending_delete = group } label: { Label("Delete", systemImage: "trash") }.buttonStyle(TextButtonStyle(danger: true))
				}
			}
		}
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
