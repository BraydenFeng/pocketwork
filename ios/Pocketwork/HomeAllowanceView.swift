import Combine
import FamilyControls
import SwiftUI

struct HomeAllowanceView: View {
	let document: AppDocument
	var edit_on_open = false
	private var shown: AppDocument { editor.draft ?? document }
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@EnvironmentObject private var home: HomeLocationController
	@Environment(\.scenePhase) private var scene_phase
	@State private var picking_group: AppGroup?
	@StateObject private var editor = RoutinePageEditing()
	@StateObject private var allowance = HomeAllowanceDisplay()
	@State private var opened = false
	@State private var visible = false
	@State private var showing_logic = false
	@State private var activating: PendingActivation?
	private let ui_testing = CommandLine.arguments.contains("--ui-testing")
	private let refresh_clock = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
	private let days = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				if editor.active { TextField("Page name", text: Binding(get: { editor.draft?.name ?? "" }, set: { editor.draft?.name = $0 }), axis: .vertical).heading_font(26).accessibilityIdentifier("page.name") }
				else { Text(document.name).heading_font(26) }
				if !editor.active, !document.description.isEmpty { Text(document.description).font(.system(size: 15)).foregroundStyle(Theme.text_dim) }
				SectionLabel(text: "Routines").padding(.top, 4)
				Card(tinted: true) {
					VStack(alignment: .leading, spacing: 8) {
						HStack(spacing: 12) {
							VStack(alignment: .leading, spacing: 4) {
								Text("Home allowance").heading_font(16)
								Text(home.status).supporting()
							}
							.frame(maxWidth: .infinity, alignment: .leading)
							Toggle("Enable home allowance", isOn: Binding(get: { document.enabled == true }, set: { enabled in
								if enabled { activate() } else { switch_allowance(false) }
							})).labelsHidden().disabled(sessions.is_busy).tint(Theme.success).accessibilityLabel("Enable home allowance")
						}
						if document.enabled == true && !Activation.missing(for: document, in: Activation.context(for: document, library: library, sessions: sessions, home: home)).isEmpty {
							Button { activating = PendingActivation(document: document, verb: "Turn on") { switch_allowance(true) } } label: { Label("Needs setup", systemImage: "exclamationmark.triangle") }
								.buttonStyle(TextButtonStyle()).foregroundStyle(Theme.warning).accessibilityIdentifier("allowance.finish-setup")
						}
						if sessions.is_busy { ProgressView("Updating home allowance…") }
						Text("Inside your windows, at home, you get these minutes and then the apps lock until the next window. Outside a window, or away from home, nothing is blocked. Resets at midnight in Los Angeles.").font(.system(size: 12)).foregroundStyle(Theme.text_faint)
					}
				}.disabled(editor.active)
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
					Button(home.has_home ? "Update home to here" : "Set home here") { home.set_here() }.buttonStyle(QuietButtonStyle())
					Button("Choose Distractions") { picking_group = library.groups.first { $0.name == document.shield?.group_names.first } }.buttonStyle(QuietButtonStyle())
					if !editor.active, document.behaviors != nil, !document.behaviors_are_compiled_allowance { BehaviorPanel(document: document) }
				}.disabled(editor.active)
				SectionLabel(text: "Data").padding(.top, 8)
				Group {
					if let policy = document.home_allowance {
						let usage = MinutesHistory.allowance(allowance.state, policy: policy)
						let budget = usage.last?.budget ?? policy.rule(at: .now)?.allowance_minutes ?? 0
						VStack(alignment: .leading, spacing: 8) {
							Text("\(usage.last?.minutes ?? 0) of \(budget) min used today").heading_font(17)
							MinutesChart(days: usage).accessibilityIdentifier("allowance.chart")
						}
					}
					Button("Refresh remaining time") { refresh() }.buttonStyle(TextButtonStyle())
					if let state = allowance.state, let policy = document.home_allowance { diagnostics(state, policy: policy) }
					Text("Home uses a 150 m boundary. iOS may detect crossings late. iOS reports usage every 5 minutes and again at your limit, so minutes used can trail Screen Time by a few minutes.").supporting()
				}.disabled(editor.active)
				if let error = home.error_message ?? sessions.error_message { Text(error).foregroundStyle(Theme.danger).font(.system(size: 13)) }
			}.padding(Theme.pad).disabled(editor.saving).readable()
		}.page().navigationTitle("Home allowance").navigationBarTitleDisplayMode(.inline)
		.onAppear { visible = true; if !ui_testing { home.restore() }; refresh(); if !opened { opened = true; if edit_on_open { editor.begin(document) } } }
		.onDisappear { visible = false }
		.onReceive(refresh_clock) { _ in refresh_if_active() }
		.onChange(of: scene_phase) { _, _ in refresh_if_active() }
		.onChange(of: document.home_allowance) { _, _ in refresh_if_active() }
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
		.sheet(item: $activating) { pending in ActivationSheet(document: pending.document, verb: pending.verb, run: pending.run) }
	}

	private func diagnostics(_ state: HomeState, policy: HomePolicy) -> some View {
		DisclosureGroup("Diagnostics") {
			VStack(alignment: .leading, spacing: 6) {
				Text("Switched on: \(state.enabled ? "yes" : "no") · At home: \(state.at_home ? "yes" : "no") · In a window: \(policy.allows(at: .now) ? "yes" : "no")")
				Text("Used today: \(state.ledger.used_minutes) min · Counting now: \(state.ledger.generation == nil ? "no" : "yes")")
				ForEach(Array((state.log ?? []).reversed().enumerated()), id: \.offset) { _, entry in
					Text("\(Date(timeIntervalSince1970: entry.at).formatted(date: .omitted, time: .shortened))  \(entry.text)")
				}
				if (state.log ?? []).isEmpty { Text("No events recorded yet.") }
			}
			.font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text_dim).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
		}
		.font(.system(size: 13, weight: .medium)).tint(Theme.text_dim)
	}

	// Switching on asks for whatever is still missing (Screen Time, apps, home, Always location) before the engine starts.
	private func activate() {
		if Activation.missing(for: document, in: Activation.context(for: document, library: library, sessions: sessions, home: home)).isEmpty { switch_allowance(true) }
		else { activating = PendingActivation(document: document, verb: "Turn on") { switch_allowance(true) } }
	}

	private func switch_allowance(_ enabled: Bool) {
		Task { if await sessions.set_routine(document, enabled: enabled, groups: library.groups) { library.set_enabled(document.id, enabled); refresh() } }
	}

	private func refresh_if_active() {
		guard visible, scene_phase == .active else { return }
		refresh()
	}
	private func refresh() {
		guard !ui_testing else {
			// Screenshot runs pass a sample ledger; the real engine is never touched under UI tests.
			if let sample = ProcessInfo.processInfo.environment["POCKETWORK_UI_HOME_STATE"] {
				do { allowance.show(try JSONDecoder().decode(HomeState.self, from: Data(sample.utf8)), policy: document.home_allowance) }
				catch { sessions.report(error) }
			}
			return
		}
		Task {
			do { try await allowance.refresh(policy: document.home_allowance) }
			catch { sessions.report(error) }
		}
	}
}
