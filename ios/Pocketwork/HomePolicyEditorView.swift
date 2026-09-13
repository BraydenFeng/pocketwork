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
					Text("Outside these windows, distractions are blocked at home. Each day's allowance resets at midnight in Los Angeles.").supporting()
				}.padding(24)
			}.paper_page().navigationTitle("Edit home allowance").navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
				ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).foregroundStyle(Theme.accent).disabled(saving) }
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

private struct HomeRuleEditor: View {
	@Binding var rule: HomeDayRule
	private let days = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text(rule.days.map { days[$0] }.joined(separator: ", ")).heading_font(20)
			Stepper(value: $rule.allowance_minutes, in: 1...180, step: 5) {
				VStack(alignment: .leading, spacing: 4) { Text("\(rule.allowance_minutes) minutes total").heading_font(17); Text("Shared daily allowance").supporting() }
			}
			ForEach(Array(rule.windows.indices), id: \.self) { index in
				HStack(spacing: 12) {
					DatePicker("From", selection: clock(index, \.start), displayedComponents: .hourAndMinute).labelsHidden().accessibilityLabel("Window \(index + 1) starts")
					Text("to").supporting()
					DatePicker("Until", selection: clock(index, \.end), displayedComponents: .hourAndMinute).labelsHidden().accessibilityLabel("Window \(index + 1) ends")
					Spacer(minLength: 0)
				}
			}
		}
	}
	private func clock(_ index: Int, _ key: WritableKeyPath<HomeWindow, String>) -> Binding<Date> {
		Binding(get: { Calendar.current.date(byAdding: .minute, value: ScheduleWindow.minutes(rule.windows[index][keyPath: key]) ?? 0, to: Calendar.current.startOfDay(for: .now)) ?? .now }, set: { value in let parts = Calendar.current.dateComponents([.hour, .minute], from: value); rule.windows[index][keyPath: key] = ScheduleWindow.clock((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) })
	}
}
