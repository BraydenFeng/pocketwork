import FamilyControls
import SwiftUI

struct AppGroupSelectionSheet: View {
	let group: AppGroup
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@Environment(\.dismiss) private var dismiss
	@State private var selection = FamilyActivitySelection()
	@State private var authorized = false
	@State private var saving = false
	@State private var failure: String?
	var body: some View {
		NavigationStack {
			Group {
				if authorized { FamilyActivityPicker(selection: $selection) }
				else {
					VStack(alignment: .leading, spacing: 24) {
						DocumentHeading(title: "Apps in \(group.name)", subtitle: "Allow Screen Time access to choose apps, websites, and categories. Your selection stays on this iPhone.", icon: "square.grid.2x2")
						Button("Choose apps") { Task { authorized = await sessions.authorize_screen_time(); if !authorized { failure = sessions.error_message } } }.buttonStyle(PrimaryButtonStyle())
						Spacer()
					}.padding(24)
				}
			}.paper_page().navigationTitle(group.name).navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
				ToolbarItem(placement: .confirmationAction) { Button("Done") { save() }.disabled(!authorized || saving) }
			}
			.overlay { if saving { ProgressView("Updating routines…").padding().background(Theme.surface) } }
			.interactiveDismissDisabled(saving)
			.onAppear { selection = sessions.group_selection(group); authorized = AuthorizationCenter.shared.authorizationStatus == .approved }
			.alert("Couldn’t update apps", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) { Button("OK") { failure = nil } } message: { Text(failure ?? "") }
		}
	}
	private func save() {
		saving = true
		Task {
			defer { saving = false }
			do { try SharedStore().save_group_selection(selection, for: group.id) } catch { failure = error.localizedDescription; return }
			sessions.objectWillChange.send()
			for document in library.library.routines_using(group: group.name) where document.enabled == true {
				if !(await sessions.set_routine(document, enabled: true, groups: library.groups)) { library.set_enabled(document.id, false); failure = sessions.error_message; return }
			}
			dismiss()
		}
	}
}
