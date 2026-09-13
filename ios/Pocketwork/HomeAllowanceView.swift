import FamilyControls
import SwiftUI

struct HomeAllowanceView: View {
	let document: AppDocument
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@EnvironmentObject private var home: HomeLocationController
	@State private var showing_picker = false
	@State private var selection = FamilyActivitySelection()
	@State private var remaining: Int?
	private let days = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				Text(document.name).heading_font(26)
				Text("Only time at home counts. Your allowance is shared across all windows and resets at midnight in Los Angeles.").supporting()
				if let policy = document.home_allowance {
					ForEach(Array(policy.rules.enumerated()), id: \.offset) { _, rule in
						Card { VStack(alignment: .leading, spacing: 6) {
							Text(rule.days.map { days[$0] }.joined(separator: ", ") + " · \(rule.allowance_minutes) min total").heading_font(15)
							Text(rule.windows.map { "\($0.start)–\($0.end)" }.joined(separator: " and ")).supporting()
						} }
					}
				}
				Text(home.status).heading_font(15)
				if let remaining { Text("\(remaining) minutes left today").supporting() }
				Button(home.has_home ? "Update home to here" : "Set home here") { home.set_here() }.buttonStyle(QuietButtonStyle())
				if !home.always_allowed { Button("Allow background home detection") { home.allow_background() }.buttonStyle(QuietButtonStyle()) }
				Button("Choose Distractions") { Task { if await sessions.authorize_screen_time(), let group = library.groups.first(where: { $0.name == document.shield?.group_names.first }) { selection = sessions.group_selection(group); showing_picker = true } } }.buttonStyle(QuietButtonStyle())
				Toggle("Enable home allowance", isOn: Binding(get: { document.enabled == true }, set: { enabled in
					Task { if await sessions.set_routine(document, enabled: enabled, groups: library.groups) { library.set_enabled(document.id, enabled); refresh() } }
				})).disabled(sessions.is_busy || !home.has_home || !home.always_allowed).tint(Theme.success)
				if sessions.is_busy { ProgressView("Updating home allowance…") }
				Button("Refresh remaining time") { refresh() }.buttonStyle(TextButtonStyle())
				Text("Outside the windows, distractions are blocked at home. Away from home, they are unrestricted. Home uses a 150 m boundary. iOS may detect crossings late. Usage is saved in whole minutes; a final partial minute may not count when you leave.").supporting()
				if let error = home.error_message ?? sessions.error_message { Text(error).foregroundStyle(Theme.danger).font(.system(size: 13)) }
			}.padding(Theme.pad)
		}.page().navigationTitle("Home allowance").navigationBarTitleDisplayMode(.inline)
		.onAppear { home.restore(); refresh() }
		.sheet(isPresented: $showing_picker) { NavigationStack { FamilyActivityPicker(selection: $selection).navigationTitle("Distractions").toolbar {
			ToolbarItem(placement: .confirmationAction) { Button("Done") {
				if let group = library.groups.first(where: { $0.name == document.shield?.group_names.first }) { sessions.save_group_selection(selection, for: group); if document.enabled == true { Task { _ = await sessions.set_routine(document, enabled: true, groups: library.groups) } } }
				showing_picker = false
			} }
		} } }
	}
	private func refresh() { Task { do { let state = try await HomeWorker.run { try HomeEngine.snapshot() }; let used = state.ledger.day == document.home_allowance?.day_key(.now) ? state.ledger.used_minutes : 0; remaining = max(0, (document.home_allowance?.rule(at: .now)?.allowance_minutes ?? 0) - used) } catch { sessions.report(error) } } }
}
