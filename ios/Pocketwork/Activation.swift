import FamilyControls
import SwiftUI
import UIKit

// What a page still needs before its routine can be switched on or started, in the order to fix them.
enum ActivationStep: Hashable, Identifiable {
	case screen_time
	case create_group(name: String)
	case group_apps(id: String, name: String)
	case own_apps
	case home
	case always_location
	var id: String {
		switch self {
		case .screen_time: return "screen-time"
		case .create_group(let name): return "create-\(name.lowercased())"
		case .group_apps(let id, _): return "apps-\(id)"
		case .own_apps: return "own-apps"
		case .home: return "home"
		case .always_location: return "always-location"
		}
	}
}

struct ActivationContext {
	var screen_time_approved: Bool
	var groups: [AppGroup]
	var group_count: (AppGroup) -> Int
	var own_app_count: Int
	var has_home: Bool
	var always_location: Bool
}

enum Activation {
	@MainActor static func context(for document: AppDocument, library: LibraryController, sessions: SessionController, home: HomeLocationController) -> ActivationContext {
		ActivationContext(screen_time_approved: AuthorizationCenter.shared.authorizationStatus == .approved, groups: library.groups, group_count: { sessions.group_count($0) }, own_app_count: sessions.selected_count(for: document), has_home: home.has_home, always_location: home.always_allowed)
	}

	static func missing(for document: AppDocument, in context: ActivationContext) -> [ActivationStep] {
		var steps: [ActivationStep] = []
		let blocks_apps = document.home_allowance != nil || (document.rules.block_during_focus && document.shield != nil)
		if blocks_apps {
			if !context.screen_time_approved { steps.append(.screen_time) }
			if let shield = document.shield {
				if shield.group_names.isEmpty {
					if context.own_app_count == 0 { steps.append(.own_apps) }
				} else {
					for name in shield.group_names {
						if let group = context.groups.first(where: { $0.name.lowercased() == name.lowercased() }) {
							if context.group_count(group) == 0 { steps.append(.group_apps(id: group.id, name: group.name)) }
						} else { steps.append(.create_group(name: name)) }
					}
				}
			}
		}
		if document.home_allowance != nil {
			if !context.has_home { steps.append(.home) }
			if !context.always_location { steps.append(.always_location) }
		}
		return steps
	}
}

// Shown when someone flips a routine on (or taps Start) and something is missing. Only the missing steps appear;
// each checks itself off as it is done, and the routine runs once all of them are.
struct ActivationSheet: View {
	let document: AppDocument
	let verb: String
	let run: () -> Void
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	@EnvironmentObject private var home: HomeLocationController
	@ObservedObject private var authorization = AuthorizationCenter.shared
	@Environment(\.dismiss) private var dismiss
	@State private var steps: [ActivationStep] = []
	@State private var picking_group: AppGroup?
	@State private var picking_own = false
	@State private var own_selection = FamilyActivitySelection()

	private var missing: [ActivationStep] {
		// Reading the published status keeps this view updating as Screen Time access changes.
		_ = authorization.authorizationStatus
		return Activation.missing(for: document, in: Activation.context(for: document, library: library, sessions: sessions, home: home))
	}
	// Steps stay listed (checked off) once done; a step that only appears later, like choosing apps for a group just created, is added at the end.
	private var shown: [ActivationStep] { steps + missing.filter { !steps.contains($0) } }

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 14) {
					Text(missing.isEmpty ? "Ready to go." : "\(document.name) needs \(missing.count == 1 ? "one more thing" : "\(missing.count) more things") before it can run.").supporting()
					ForEach(shown) { step in row(step, done: !missing.contains(step)) }
					if let message = home.error_message ?? sessions.error_message { Text(message).font(.system(size: 13)).foregroundStyle(Theme.danger) }
					Button(verb) { run(); dismiss() }
						.buttonStyle(PrimaryButtonStyle(accent: true)).disabled(!missing.isEmpty || sessions.is_busy).padding(.top, 8)
						.accessibilityIdentifier("activation.run")
				}
				.padding(Theme.pad)
				.readable()
			}
			.page()
			.navigationTitle("\(verb) \(document.name)")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
			.onAppear { if steps.isEmpty { steps = missing } }
			.sheet(item: $picking_group) { group in AppGroupSelectionSheet(group: group) }
			.sheet(isPresented: $picking_own) {
				NavigationStack {
					FamilyActivityPicker(selection: $own_selection)
						.navigationTitle("Choose apps to block")
						.toolbar {
							ToolbarItem(placement: .cancellationAction) { Button("Cancel") { picking_own = false } }
							ToolbarItem(placement: .confirmationAction) { Button("Done") { sessions.save_selection(own_selection, for: document); picking_own = false } }
						}
				}
			}
		}
	}

	private func row(_ step: ActivationStep, done: Bool) -> some View {
		Card(tinted: !done) {
			HStack(alignment: .top, spacing: 12) {
				Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 20)).foregroundStyle(done ? Theme.success : Theme.text_faint)
				VStack(alignment: .leading, spacing: 4) {
					Text(title(step)).heading_font(15)
					Text(detail(step)).supporting()
					if !done, step == .always_location {
						Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.buttonStyle(TextButtonStyle())
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				if !done { Button(action_title(step)) { act(step) }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("activation.\(step.id)") }
			}
		}
	}

	private func title(_ step: ActivationStep) -> String {
		switch step {
		case .screen_time: return "Allow Screen Time"
		case .create_group(let name): return "Create the \(name) group"
		case .group_apps(_, let name): return "Choose apps for \(name)"
		case .own_apps: return "Choose apps to block"
		case .home: return "Set your home"
		case .always_location: return "Allow location all the time"
		}
	}

	private func detail(_ step: ActivationStep) -> String {
		switch step {
		case .screen_time: return "Lets Pocketwork lock the apps you pick. You approve it with Face ID or your passcode."
		case .create_group(let name): return "This page blocks \(name), which doesn't exist yet."
		case .group_apps(_, let name): return "Pick what \(name) locks. Pocketwork never sees which apps you chose."
		case .own_apps: return "Pick the apps, categories, or websites this page locks."
		case .home: return "Do this while you're at home. Usage only counts within 150 m of this spot."
		case .always_location: return "So Pocketwork notices when you get home, even when it's closed. Choose Always Allow. If iOS doesn't ask, open Settings › Pocketwork › Location and pick Always."
		}
	}

	private func action_title(_ step: ActivationStep) -> String {
		switch step {
		case .screen_time, .always_location: return "Allow"
		case .create_group: return "Create"
		case .group_apps, .own_apps: return "Choose"
		case .home: return "I'm home"
		}
	}

	private func act(_ step: ActivationStep) {
		switch step {
		case .screen_time: Task { _ = await sessions.authorize_screen_time() }
		case .create_group(let name): if let group = library.add_group(name) { picking_group = group }
		case .group_apps(let id, _): picking_group = library.groups.first { $0.id == id }
		case .own_apps: own_selection = sessions.selection(for: document); picking_own = true
		case .home: home.set_here()
		case .always_location: home.allow_background()
		}
	}
}

// The sheet's request: which page, what the final button says, and what runs once everything is ready.
struct PendingActivation: Identifiable {
	let id = UUID()
	let document: AppDocument
	let verb: String
	let run: () -> Void
}
