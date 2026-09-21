import FamilyControls
import SwiftUI

struct HomeAllowanceView: View {
	let document: AppDocument
	var edit_on_open = false
	private var shown: AppDocument { editor.draft ?? document }
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@EnvironmentObject private var home: HomeLocationController
	@State private var picking_group: AppGroup?
	@StateObject private var editor = RoutinePageEditing()
	@State private var opened = false
	@State private var showing_logic = false
	@State private var remaining: Int?
	private let ui_testing = CommandLine.arguments.contains("--ui-testing")
	private let days = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				if editor.active { TextField("Page name", text: Binding(get: { editor.draft?.name ?? "" }, set: { editor.draft?.name = $0 }), axis: .vertical).heading_font(26).accessibilityIdentifier("page.name") }
				else { Text(document.name).heading_font(26) }
				Text("Inside your windows, at home, you get these minutes and then the apps lock until the next window. Outside a window, or away from home, nothing is blocked. Resets at midnight in Los Angeles.").supporting()
				if let policy = shown.home_allowance {
					ForEach(Array(policy.rules.enumerated()), id: \.offset) { index, rule in
						Card { if editor.active {
							HomeRuleEditor(rule: Binding(get: { editor.draft?.home_allowance?.rules[index] ?? rule }, set: { editor.draft?.home_allowance?.rules[index] = $0 }))
						} else { Button { editor.begin(document) } label: { HStack {
							VStack(alignment: .leading, spacing: 6) {
								Text(rule.days.map { days[$0] }.joined(separator: ", ") + " · \(rule.allowance_minutes) min total").heading_font(15)
								Text(rule.windows.map { "\($0.start)–\($0.end)" }.joined(separator: " and ")).supporting()
								Text("Tap to change the minutes or windows").font(.system(size: 11)).foregroundStyle(Theme.text_faint)
							}
							Spacer()
							Image(systemName: "pencil").foregroundStyle(Theme.text_faint)
						}.contentShape(Rectangle()) }.buttonStyle(.plain).disabled(sessions.is_busy) } }
					}
				}
				Group {
				if !editor.active, document.behaviors != nil { BehaviorPanel(document: document) }
				Text(home.status).heading_font(15)
				if let remaining { Text("\(remaining) minutes left today").supporting() }
				Button(home.has_home ? "Update home to here" : "Set home here") { home.set_here() }.buttonStyle(QuietButtonStyle())
				if !home.always_allowed { Button("Allow background home detection") { home.allow_background() }.buttonStyle(QuietButtonStyle()) }
				Button("Choose Distractions") { picking_group = library.groups.first { $0.name == document.shield?.group_names.first } }.buttonStyle(QuietButtonStyle())
				Toggle("Enable home allowance", isOn: Binding(get: { document.enabled == true }, set: { enabled in
					Task { if await sessions.set_routine(document, enabled: enabled, groups: library.groups) { library.set_enabled(document.id, enabled); refresh() } }
				})).disabled(sessions.is_busy || !home.has_home || !home.always_allowed).tint(Theme.success)
				if sessions.is_busy { ProgressView("Updating home allowance…") }
				Button("Refresh remaining time") { refresh() }.buttonStyle(TextButtonStyle())
				Text("Outside the windows and away from home, nothing is blocked. Home uses a 150 m boundary. iOS may detect crossings late. Usage is saved in whole minutes; a final partial minute may not count when you leave.").supporting()
				}.disabled(editor.active)
				if let error = home.error_message ?? sessions.error_message { Text(error).foregroundStyle(Theme.danger).font(.system(size: 13)) }
			}.padding(Theme.pad).disabled(editor.saving)
		}.page().navigationTitle("Home allowance").navigationBarTitleDisplayMode(.inline)
		.onAppear { if !ui_testing { home.restore(); refresh() }; if !opened { opened = true; if edit_on_open { editor.begin(document) } } }
		.navigationBarBackButtonHidden(editor.active)
		.scrollDismissesKeyboard(.interactively)
		.toolbar { ToolbarItem(placement: .topBarTrailing) {
			if editor.active { Button("Save") { Task { await editor.save(library: library, sessions: sessions); refresh() } }.fontWeight(.semibold).foregroundStyle(Theme.accent).disabled(editor.saving || sessions.is_busy) }
			else { Button("Edit") { editor.begin(document) }.disabled(sessions.is_busy).accessibilityIdentifier("tool.edit") }
		} }
		.safeAreaInset(edge: .bottom) { if editor.active { EditorBar { Button("Cancel") { editor.cancel() }.buttonStyle(TextButtonStyle()); Spacer(); Button { showing_logic = true } label: { Label("Logic", systemImage: "point.3.connected.trianglepath.dotted") }.buttonStyle(TextButtonStyle()).frame(minHeight: 44).accessibilityIdentifier("editor.logic"); if editor.saving { ProgressView() } }.disabled(editor.saving) } }
		.alert("Couldn’t save changes", isPresented: Binding(get: { editor.failure != nil }, set: { if !$0 { editor.failure = nil } })) { Button("OK") { editor.failure = nil } } message: { Text(editor.failure ?? "") }
		.fullScreenCover(isPresented: $showing_logic) { if let draft = editor.draft { LogicEditorView(document: Binding(get: { editor.draft ?? draft }, set: { editor.draft = $0 })) } }
		.sheet(item: $picking_group) { group in AppGroupSelectionSheet(group: group) }
	}

	private func refresh() { guard !ui_testing else { return }; Task { do { let state = try await HomeWorker.run { try HomeEngine.snapshot() }; let used = state.ledger.day == document.home_allowance?.day_key(.now) ? state.ledger.used_minutes : 0; let base = document.home_allowance?.rule(at: .now)?.allowance_minutes ?? 0; let budget = state.ledger.day == document.home_allowance?.day_key(.now) ? state.ledger.budget(base) : base; remaining = max(0, budget - used) } catch { sessions.report(error) } } }
}
