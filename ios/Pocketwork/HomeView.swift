import FamilyControls
import OSLog
import SwiftUI
import UniformTypeIdentifiers

// The front door: saved pages as a grid of tiles. Tapping a tile opens the page, where its routines sit above its data.
struct HomeView: View {
	@EnvironmentObject private var cloud: CloudController
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var sessions: SessionController
	private struct RoutineRoute: Hashable { let id: String; var editing = false }
	@State private var path: [RoutineRoute] = []
	@State private var showing_groups = false
	@State private var showing_import = false
	@State private var pending_delete: LibraryEntry?
	@State private var editing: RoutineDraft?
	@State private var picking_group: AppGroup?
	@State private var account_intent: AccountIntent?
	private let logger = Logger(subsystem: "Pocketwork", category: "FileImport")

	var body: some View {
		NavigationStack(path: $path) {
			ScrollView {
				VStack(alignment: .leading, spacing: 0) {
					intro
					if !cloud.signed_in {
						VStack(alignment: .leading, spacing: Theme.gap) {
							Text("Save your pages to an account").heading_font(15)
							Text("Open them on your iPhone, iPad, or computer. You can also keep using this device without an account.").supporting()
							ViewThatFits(in: .horizontal) {
								HStack(spacing: Theme.gap) { account_buttons }
								VStack(alignment: .leading, spacing: Theme.gap) { account_buttons }
							}
						}.padding(Theme.pad)
					}
					Hairline()
					section(number: "01", label: "My pages", heading: library.sorted_tools.isEmpty ? "Nothing here yet." : nil, supporting: library.sorted_tools.isEmpty ? "Create a page here, or sign in to bring in pages from your computer." : nil) {
						if library.storage_blocked { storage_warning }
						Button { editing = RoutineDraft(document: AppDocument.blank(), is_new: true) } label: { Label("New page", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle(accent: true))
						// Two tiles across on iPhone; more on iPad.
						LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 280), spacing: 12)], spacing: 12) {
							ForEach(library.sorted_tools) { entry in page_tile(entry) }
						}
					}
					Hairline()
					section(number: "02", label: "Groups of apps", heading: nil, supporting: "Make your own groups, like Social, Games, or School, and choose the apps in each. Any page can block or limit a group.") {
						ForEach(library.groups) { group in
							Button { picking_group = group } label: {
								DocumentRow(icon: "square.grid.2x2") {
									HStack {
										VStack(alignment: .leading, spacing: 4) { Text(group.name).heading_font(15); Text("\(sessions.group_count(group)) selected · choose apps").supporting() }
										Spacer(); Image(systemName: "chevron.right").foregroundStyle(Theme.text_faint)
									}
								}
							}.buttonStyle(.plain).accessibilityIdentifier("home.group.\(group.id)")
							Hairline()
						}
						Button { showing_groups = true } label: { Label("New group", systemImage: "plus") }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("home.groups")
					}

				}
				.readable(900)
			}
			.refreshable { await cloud.sync() }
			.page()
			.navigationTitle("My pages")
			.navigationBarTitleDisplayMode(.inline)
			.navigationDestination(for: RoutineRoute.self) { route in ToolView(document_id: route.id, edit_on_open: route.editing) }
			.navigationDestination(isPresented: $showing_groups) { GroupsView() }
			.toolbar {
				ToolbarItem(placement: .topBarLeading) { brand }
				ToolbarItem(placement: .topBarTrailing) {
					Menu {
						Button("Account & sync", systemImage: "person.crop.circle") { account_intent = cloud.signed_in ? .manage : .sign_in }
						Button("Groups of apps", systemImage: "square.grid.2x2") { showing_groups = true }
						Button("Add from file", systemImage: "square.and.arrow.down") { showing_import = true }
						Button(role: .destructive) { Task { for id in await sessions.clear_everything() { library.set_enabled(id, false) } } } label: { Label("Clear all focus restrictions", systemImage: "lock.open") }.disabled(sessions.is_busy)
					} label: { Image(systemName: "ellipsis") }
				}
			}
			.sheet(item: $editing) { item in RoutineEditorSheet(item: item) }
			.sheet(item: $picking_group) { group in AppGroupSelectionSheet(group: group) }
			// A widget tap arrives as com.braydenfeng.pocketwork://routine/<id>; the sign-in callback uses a different host and is handled elsewhere.
			.onOpenURL { url in if let id = WidgetSnapshot.routine_id(from: url), library.tool(id) != nil { path = [RoutineRoute(id: id)] } }
			.sheet(item: $account_intent) { intent in NavigationStack { ScrollView { AccountView(intent: intent) }.page().navigationTitle(cloud.signed_in ? "Account & sync" : intent.title).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button(cloud.signed_in ? "Done" : "Not now") { account_intent = nil }.accessibilityIdentifier("account.dismiss") } } } }
			.fileImporter(isPresented: $showing_import, allowedContentTypes: [.json]) { result in import_file(result) }
			.confirmationDialog("Delete \"\(pending_delete?.document.name ?? "this page")\"? This cannot be undone.", isPresented: Binding(get: { pending_delete != nil }, set: { if !$0 { pending_delete = nil } }), titleVisibility: .visible) {
				Button("Delete", role: .destructive) {
					if let entry = pending_delete { Task { await sessions.forget(entry.document.id); library.delete(entry.document.id) } }
					pending_delete = nil
				}
				Button("Cancel", role: .cancel) { pending_delete = nil }
			}
			.alert("Couldn’t complete that action", isPresented: Binding(get: { library.error_message != nil }, set: { if !$0 { library.error_message = nil } })) {
				Button("OK") { library.error_message = nil }
			} message: { Text(library.error_message ?? "") }
		}
	}

	private var account_buttons: some View {
		Group {
			Button { account_intent = .create } label: { Text("Create account").frame(maxWidth: .infinity) }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("home.create-account")
			Button { account_intent = .sign_in } label: { Text("Sign in").frame(maxWidth: .infinity) }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("home.sign-in")
		}
	}

	private var brand: some View {
		HStack(spacing: 6) {
			Image(systemName: "square.stack.3d.up").font(.system(size: 15, weight: .medium))
			Text("pocketwork").font(.system(size: 17, weight: .semibold)).tracking(-0.3) + Text(".").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text_faint)
		}
		.foregroundStyle(Theme.text)
	}

	private var intro: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Each page holds routines and the data they track.").supporting()
			HStack(spacing: 8) {
				Circle().fill(library.storage_blocked ? Theme.danger : Theme.success).frame(width: 6, height: 6)
				Text(library.storage_blocked ? "Saved pages need attention" : "\(library.sorted_tools.count) saved on this \(UIDevice.current.model)").font(.system(size: 13)).foregroundStyle(library.storage_blocked ? Theme.danger : Theme.text_faint)
			}.padding(.top, 4)
		}
		.padding(Theme.pad)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Theme.surface)
	}

	private var storage_warning: some View {
		Card(tinted: true) {
			VStack(alignment: .leading, spacing: 10) {
				Label("Your saved pages could not be opened. Nothing has been overwritten.", systemImage: "exclamationmark.triangle").font(.system(size: 13)).foregroundStyle(Theme.danger)
				Button("Replace unreadable data") { library.replace_unreadable() }.buttonStyle(QuietButtonStyle(danger: true))
			}
		}
	}

	private func section<Content: View>(number: String, label: String, heading: String?, supporting: String?, @ViewBuilder content: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: Theme.gap) {
			VStack(alignment: .leading, spacing: 6) {
				SectionLabel(number: number, text: label)
				if let heading { Text(heading).heading_font(20) }
				if let supporting { Text(supporting).supporting() }
			}
			content()
		}
		.padding(Theme.pad)
	}

	private func page_tile(_ entry: LibraryEntry) -> some View {
		let document = entry.document
		let running = sessions.session?.document_id == document.id
		return Button { path = [RoutineRoute(id: document.id)] } label: {
			VStack(alignment: .leading, spacing: 8) {
				HStack(alignment: .top, spacing: 6) {
					Text(document.name).heading_font(16).multilineTextAlignment(.leading).lineLimit(3)
					Spacer(minLength: 0)
					if running || document.enabled == true { Circle().fill(Theme.success).frame(width: 7, height: 7).padding(.top, 6).accessibilityHidden(true) }
				}
				Spacer(minLength: 0)
				Text(status_line(entry)).font(.system(size: 12)).foregroundStyle(Theme.text_faint).multilineTextAlignment(.leading).lineLimit(2)
			}
			.padding(14)
			.frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
			.background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
			.overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Open \(document.name)")
		.accessibilityIdentifier("tool.\(document.id)")
		.contextMenu {
			Button("Duplicate", systemImage: "doc.on.doc") { _ = library.duplicate(document.id) }.disabled(document.home_allowance != nil)
			Button("Delete", systemImage: "trash", role: .destructive) { pending_delete = entry }
		}
	}

	private func status_line(_ entry: LibraryEntry) -> String {
		let document = entry.document
		if let session = sessions.session, session.document_id == document.id {
			return "Running · ends \(session.ends_at.formatted(date: .omitted, time: .shortened))"
		}
		if document.home_allowance != nil { return document.enabled == true ? "Home allowance · on" : "Home allowance · off" }
		if let schedule = document.schedule { return ScheduleWindow.describe_status(schedule, enabled: document.enabled == true, at: .now) }
		if let minutes = document.blocks.first(where: { $0.type == .timer })?.minutes { return "\(minutes)-minute timer" }
		return ToolCopy.edited(entry, now: .now)
	}

	private func import_file(_ result: Result<URL, Error>) {
		do {
			let url = try result.get()
			guard url.startAccessingSecurityScopedResource() else { throw DocumentError.invalid("Permission to read this file was not granted.") }
			defer { url.stopAccessingSecurityScopedResource() }
			let handle = try FileHandle(forReadingFrom: url)
			defer { do { try handle.close() } catch { logger.error("Could not close imported file: \(error.localizedDescription, privacy: .public)") } }
			let data = try handle.read(upToCount: 100_001) ?? Data()
			if let document = library.import_document(try AppDocument.decode(data)) { path = [RoutineRoute(id: document.id)] }
		} catch { library.report(error) }
	}
}
