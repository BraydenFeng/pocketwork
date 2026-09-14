import SwiftUI

struct HomePolicyEditorView: View {
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@Environment(\.dismiss) private var dismiss
	@State private var draft: AppDocument
	@State private var saving = false
	@State private var failure: String?
	init(document: AppDocument) { _draft = State(initialValue: document) }
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 24) {
					Image(systemName: "house").font(.system(size: 28, weight: .light)).foregroundStyle(Theme.text_faint)
					TextField("Routine name", text: $draft.name, axis: .vertical).font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.text).accessibilityIdentifier("editor.name")
					Text("A daily allowance, shared across your windows. Only usage at home counts.").supporting()
					Hairline()
					ForEach(Array((draft.home_allowance?.rules ?? []).indices), id: \.self) { index in
						HomeRuleEditor(rule: Binding(get: { draft.home_allowance!.rules[index] }, set: { draft.home_allowance?.rules[index] = $0 }))
						Hairline()
					}
					Text("The minutes count only inside these windows, at home; once they are spent the apps lock until the next window. Outside a window nothing is blocked. Each day's allowance resets at midnight in Los Angeles.").supporting()
				}.padding(24)
			}.paper_page().navigationTitle("Edit home allowance").navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
				ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).foregroundStyle(Theme.accent).disabled(saving || sessions.is_busy) }
			}
			.interactiveDismissDisabled(saving)
			.safeAreaInset(edge: .bottom) { if saving { EditorBar { ProgressView("Applying your changes…"); Spacer() } } }
			.alert("Couldn’t save changes", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) { Button("OK") { failure = nil } } message: { Text(failure ?? "") }
		}
	}
	private func save() {
		draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
		do { try draft.validate() } catch { failure = error.localizedDescription; return }
		saving = true
		Task {
			defer { saving = false }
			guard library.save(draft) else { failure = library.error_message; return }
			if draft.enabled == true, !(await sessions.set_routine(draft, enabled: true, groups: library.groups)) { library.set_enabled(draft.id, false); draft.enabled = false; failure = sessions.error_message; return }
			dismiss()
		}
	}
}

struct HomeRuleEditor: View {
	@Binding var rule: HomeDayRule
	private let days = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	private static let minute_options = [15, 30, 45, 60, 90, 120, 180]
	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			// Reads as one sentence: on these days, at home, during these hours, this many minutes, then locked.
			VStack(alignment: .leading, spacing: 4) {
				Text(rule.days.map { days[$0] }.joined(separator: ", ")).heading_font(20)
				Text("At home, during the hours below, you get \(rule.allowance_minutes) minutes. Then the apps lock until the next window.").supporting()
			}
			ChipRow(label: "Minutes per day", options: Array(Set(Self.minute_options + [rule.allowance_minutes])).sorted(), selected: rule.allowance_minutes, text: { "\($0) min" }) { rule.allowance_minutes = $0 }
				.accessibilityElement(children: .contain).accessibilityIdentifier("home.allowance.\(rule.days.first ?? 0)").accessibilityLabel("Daily allowance for " + rule.days.map { days[$0] }.joined(separator: ", ")).accessibilityValue("\(rule.allowance_minutes) minutes")
			VStack(alignment: .leading, spacing: 8) {
				Text(rule.windows.count == 1 ? "Hours" : "Hours (two windows)").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text_dim)
				ForEach(Array(rule.windows.indices), id: \.self) { index in
					HStack(spacing: 12) {
						DatePicker("From", selection: clock(index, \.start), displayedComponents: .hourAndMinute).labelsHidden().accessibilityLabel("Window \(index + 1) starts")
						Text("to").supporting()
						DatePicker("Until", selection: clock(index, \.end), displayedComponents: .hourAndMinute).labelsHidden().accessibilityLabel("Window \(index + 1) ends")
						Spacer(minLength: 0)
						if rule.windows.count > 1 {
							Button { rule.windows.remove(at: index) } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 36, height: 36) }.buttonStyle(.plain).foregroundStyle(Theme.text_faint).accessibilityLabel("Remove window \(index + 1)")
						}
					}
				}
				if rule.windows.count < 2 {
					Button { let last = rule.windows.last; rule.windows.append(HomeWindow(start: last?.end ?? "19:00", end: "21:00")) } label: { Label("Add a second window", systemImage: "plus") }.buttonStyle(TextButtonStyle())
				}
			}
			Text("Outside these hours, or away from home, nothing is blocked.").font(.system(size: 11)).foregroundStyle(Theme.text_faint)
		}
	}
	private func clock(_ index: Int, _ key: WritableKeyPath<HomeWindow, String>) -> Binding<Date> {
		Binding(get: { guard rule.windows.indices.contains(index) else { return .now }; return Calendar.current.date(byAdding: .minute, value: ScheduleWindow.minutes(rule.windows[index][keyPath: key]) ?? 0, to: Calendar.current.startOfDay(for: .now)) ?? .now }, set: { value in guard rule.windows.indices.contains(index) else { return }; let parts = Calendar.current.dateComponents([.hour, .minute], from: value); rule.windows[index][keyPath: key] = ScheduleWindow.clock((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) })
	}
}
