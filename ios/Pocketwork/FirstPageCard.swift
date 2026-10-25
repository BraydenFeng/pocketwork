import FamilyControls
import ManagedSettings
import SwiftUI

// A first page built by filling in one sentence. Every blank is the person's own choice and the result is a real
// scheduled blocker, so the first thing they make is something they would actually use.
enum FirstPage {
	struct DayChoice: Hashable { let label: String; let days: [Int] }
	static let day_choices = [
		DayChoice(label: "every day", days: ScheduleWindow.all_days),
		DayChoice(label: "on school nights", days: [1, 2, 3, 4, 5]),
		DayChoice(label: "on weekdays", days: ScheduleWindow.weekdays),
		DayChoice(label: "on weekends", days: [1, 7]),
	]
	static let group_name = "Distractions"
	static let trial_minutes = 15

	static func day_label(_ days: [Int]) -> String {
		day_choices.first { $0.days == days.sorted() }?.label ?? "on " + ScheduleWindow.format_days(days)
	}

	static func document(group: String, start: String, end: String, days: [Int]) throws -> AppDocument {
		var schedule = BlockDocument.make(.schedule)
		schedule.title = "When it's on"; schedule.days = days.sorted(); schedule.start = start; schedule.end = end
		var shield = BlockDocument.make(.screen_time)
		shield.title = "Blocked apps"; shield.mode = .block; shield.groups = [group]
		var document = AppDocument.blank()
		document.name = "No \(group.lowercased()) \(ScheduleWindow.format_clock(start))–\(ScheduleWindow.format_clock(end))"
		document.blocks = [schedule, shield]
		document.rules = RuleDocument(block_during_focus: true, notify_on_complete: false)
		document.enabled = false
		try document.validate()
		return document
	}

	// The same apps blocked right away, for long enough that iOS will monitor it, so the block screen can be seen before the schedule starts.
	static func trial(of page: AppDocument) throws -> AppDocument {
		guard let shield = page.shield else { throw DocumentError.invalid("This page doesn't block any apps.") }
		var timer = BlockDocument.make(.timer)
		timer.title = "Try it now"; timer.minutes = trial_minutes
		var document = AppDocument.blank()
		document.name = "Trying \(page.name)"
		document.blocks = [timer, shield]
		document.rules = RuleDocument(block_during_focus: true, notify_on_complete: false)
		try document.validate()
		return document
	}
}

struct FirstPageResult: Identifiable {
	let id = UUID()
	let document: AppDocument
}

struct FirstPageCard: View {
	let created: (AppDocument) -> Void
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@State private var selection = FamilyActivitySelection()
	@State private var draft = FamilyActivitySelection()
	@State private var picking = false
	@State private var finish_after_picking = false
	@State private var start = "21:00"
	@State private var end = "07:00"
	@State private var days = ScheduleWindow.all_days
	@State private var editing: TimeBlank?
	@State private var working = false
	@State private var failure: String?

	enum TimeBlank: String, Identifiable { case start, end; var id: String { rawValue } }

	var body: some View {
		Card {
			VStack(alignment: .leading, spacing: 14) {
				SectionLabel(text: "Your first page")
				VStack(alignment: .leading, spacing: 10) {
					HStack(alignment: .center, spacing: 8) { word("Block"); apps_blank }
					ViewThatFits(in: .horizontal) {
						HStack(alignment: .center, spacing: 8) { word("from"); time_blank(.start); word("to"); time_blank(.end) }
						VStack(alignment: .leading, spacing: 10) {
							HStack(alignment: .center, spacing: 8) { word("from"); time_blank(.start) }
							HStack(alignment: .center, spacing: 8) { word("to"); time_blank(.end) }
						}
					}
					HStack(alignment: .center, spacing: 2) { days_blank; word(".") }
				}
				Text("Tap the blue parts to make it yours. You can change anything later.").supporting()
				if let failure { Text(failure).font(.system(size: 13)).foregroundStyle(Theme.danger) }
				Button { Task { await turn_on() } } label: { Text(working ? "Turning it on…" : "Turn it on") }
					.buttonStyle(PrimaryButtonStyle(accent: true))
					.disabled(working || sessions.is_busy)
					.accessibilityIdentifier("first-page.create")
			}
		}
		.onAppear { if let group = existing_group, SharedStore.count(selection) == 0 { selection = sessions.group_selection(group) } }
		.sheet(isPresented: $picking) { picker }
		.sheet(item: $editing) { blank in time_sheet(blank) }
	}

	private var existing_group: AppGroup? { library.groups.first { $0.name.lowercased() == FirstPage.group_name.lowercased() } }

	private func word(_ text: String) -> some View {
		Text(text).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
	}

	private func chip(_ text: String) -> some View {
		Text(text)
			.font(.system(size: 22, weight: .semibold))
			.foregroundStyle(Theme.accent)
			.padding(.horizontal, 8).padding(.vertical, 2)
			.background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radius_small))
	}

	private var apps_blank: some View {
		Button { Task { await choose_apps() } } label: {
			if SharedStore.count(selection) == 0 { chip("pick apps") }
			else {
				HStack(spacing: 4) {
					ForEach(Array(selection.applicationTokens.prefix(3)), id: \.self) { token in Label(token).labelStyle(.iconOnly) }
					chip(apps_summary)
				}
			}
		}
		.buttonStyle(.plain)
		.accessibilityIdentifier("first-page.apps")
	}

	private var apps_summary: String {
		let counts = [(selection.applicationTokens.count, "app", "apps"), (selection.categoryTokens.count, "category", "categories"), (selection.webDomainTokens.count, "site", "sites")]
		return counts.filter { $0.0 > 0 }.map { "\($0.0) \($0.0 == 1 ? $0.1 : $0.2)" }.joined(separator: ", ")
	}

	private func time_blank(_ blank: TimeBlank) -> some View {
		Button { editing = blank } label: { chip(ScheduleWindow.format_clock(blank == .start ? start : end)) }
			.buttonStyle(.plain)
			.accessibilityIdentifier("first-page.\(blank.rawValue)")
	}

	private var days_blank: some View {
		Menu {
			ForEach(FirstPage.day_choices, id: \.self) { choice in Button(choice.label) { days = choice.days } }
		} label: { chip(FirstPage.day_label(days)) }
		.accessibilityIdentifier("first-page.days")
	}

	private var picker: some View {
		NavigationStack {
			FamilyActivityPicker(selection: $draft)
				.navigationTitle("Apps to block")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) { Button("Cancel") { finish_after_picking = false; picking = false } }
					ToolbarItem(placement: .confirmationAction) {
						Button("Done") {
							selection = draft; picking = false
							if finish_after_picking { finish_after_picking = false; Task { await turn_on() } }
						}
					}
				}
		}
	}

	private func time_sheet(_ blank: TimeBlank) -> some View {
		NavigationStack {
			DatePicker(blank == .start ? "Starts at" : "Ends at", selection: time_binding(blank), displayedComponents: .hourAndMinute)
				.datePickerStyle(.wheel)
				.labelsHidden()
				.frame(maxWidth: .infinity)
				.navigationTitle(blank == .start ? "Starts at" : "Ends at")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = nil } } }
		}
		.presentationDetents([.height(320)])
	}

	private func time_binding(_ blank: TimeBlank) -> Binding<Date> {
		Binding(
			get: {
				let minutes = ScheduleWindow.minutes(blank == .start ? start : end) ?? 0
				return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
			},
			set: { date in
				let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
				let clock = ScheduleWindow.clock((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
				if blank == .start { start = clock } else { end = clock }
			}
		)
	}

	// Screen Time access comes first because the app picker only lists apps once it is granted.
	private func choose_apps() async {
		failure = nil
		if AuthorizationCenter.shared.authorizationStatus != .approved {
			guard await sessions.authorize_screen_time() else { failure = sessions.error_message ?? "Allow Screen Time access to pick apps."; return }
		}
		draft = selection
		picking = true
	}

	private func turn_on() async {
		failure = nil
		guard SharedStore.count(selection) > 0 else { finish_after_picking = true; await choose_apps(); return }
		working = true
		defer { working = false }
		do {
			var document = try FirstPage.document(group: existing_group?.name ?? FirstPage.group_name, start: start, end: end, days: days)
			if AuthorizationCenter.shared.authorizationStatus != .approved {
				guard await sessions.authorize_screen_time() else { failure = sessions.error_message ?? "Allow Screen Time access to block apps."; return }
			}
			// Group failures are already shown by the home screen's alert.
			guard let group = existing_group ?? library.add_group(FirstPage.group_name) else { return }
			let shared = try SharedStore()
			try shared.save_group_selection(selection, for: group.id)
			if let data = shared.group_selection_data(group.id) { library.set_group_apps(group.id, apps: data.base64EncodedString()) }
			sessions.objectWillChange.send()
			// Switched on before it is saved, so a refusal leaves no half-made page and this card stays up to show why.
			guard sessions.set_standing(document, enabled: true, groups: library.groups) else { failure = sessions.error_message ?? "Pocketwork couldn't turn this on. Please try again."; return }
			document.enabled = true
			guard library.save(document) else { _ = sessions.set_standing(document, enabled: false, groups: library.groups); return }
			created(document)
		} catch { failure = error.localizedDescription }
	}
}

// What happens right after the first page is turned on: when it starts, and a way to see the block screen now.
struct FirstPageDoneSheet: View {
	let document: AppDocument
	let open: () -> Void
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@Environment(\.dismiss) private var dismiss
	@State private var trial_id: String?
	@State private var failure: String?

	private var active_now: Bool { document.schedule.map { ScheduleWindow.status($0, at: .now).active } ?? false }
	private var trying: Bool { trial_id != nil && sessions.session?.document_id == trial_id }
	private var start: String { ScheduleWindow.format_clock(document.schedule?.start ?? "") }
	private var end: String { ScheduleWindow.format_clock(document.schedule?.end ?? "") }

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(Theme.success)
					Text("It's on.").heading_font(24)
					if active_now {
						Text("Your apps are blocked until \(end). Go to your Home Screen and open one of them to see what happens.").supporting()
					} else if trying {
						Text("Your apps are blocked for the next \(FirstPage.trial_minutes) minutes. Open one of them from your Home Screen, then come back here.").supporting()
						Button("End the test") { sessions.stop(); trial_id = nil }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("first-page.end-trial")
					} else {
						Text("It starts at \(start) \(FirstPage.day_label(document.schedule?.days ?? [])). Want to see it work first? Block the same apps for \(FirstPage.trial_minutes) minutes now. You can end it early.").supporting()
						Button("Try it for \(FirstPage.trial_minutes) minutes") { Task { await try_it() } }
							.buttonStyle(QuietButtonStyle()).disabled(sessions.is_busy || sessions.session != nil)
							.accessibilityIdentifier("first-page.trial")
					}
					if let failure { Text(failure).font(.system(size: 13)).foregroundStyle(Theme.danger) }
					Button("Open my page") { dismiss(); open() }
						.buttonStyle(PrimaryButtonStyle(accent: true)).padding(.top, 8)
						.accessibilityIdentifier("first-page.open")
				}
				.padding(Theme.pad)
				.readable()
			}
			.page()
			.navigationTitle(document.name)
			.navigationBarTitleDisplayMode(.inline)
		}
	}

	private func try_it() async {
		failure = nil
		do {
			let trial = try FirstPage.trial(of: document)
			await sessions.start(trial, groups: library.groups)
			if sessions.session?.document_id == trial.id { trial_id = trial.id } else { failure = sessions.error_message ?? "The test couldn't start. Please try again." }
		} catch { failure = error.localizedDescription }
	}
}
