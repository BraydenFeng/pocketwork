import Combine
import Foundation
import OSLog

// Owns the list of tools on this phone. Saves after every change; a save failure is reported, never swallowed.
@MainActor
final class LibraryController: ObservableObject {
	@Published private(set) var library = ToolLibrary.empty
	@Published private(set) var routines: [Routine] = []
	@Published var error_message: String?
	@Published private(set) var storage_blocked = false
	private let defaults: UserDefaults
	private let logger = Logger(subsystem: "Pocketwork", category: "LibraryController")
	static let library_key = "tool_library.v1"
	static let legacy_key = "personal_tool"

	init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
		self.defaults = defaults
		do { routines = try RoutineCatalog.bundled(in: bundle).routines } catch { report(error) }
		do { library = try Self.load(from: defaults) }
		catch { storage_blocked = true; report(error) }
	}

	// A phone that only has the old single imported tool sees it as its first tool; the old key stays until a save succeeds.
	static func load(from defaults: UserDefaults) throws -> ToolLibrary {
		if let data = defaults.data(forKey: library_key) { return try ToolLibrary.decode(data) }
		if let legacy = defaults.data(forKey: legacy_key) {
			let document = try AppDocument.decode(legacy)
			return try ToolLibrary.empty.upserting(document, now: .now)
		}
		return .empty
	}

	var sorted_tools: [LibraryEntry] { library.sorted }
	var groups: [AppGroup] { library.groups ?? [] }
	func tool(_ id: String) -> AppDocument? { library.find(id) }

	@discardableResult
	func add_group(_ name: String) -> AppGroup? {
		do { let next = try library.adding_group(name); try persist(next); return next.group(named: name) }
		catch { report(error); return nil }
	}

	func rename_group(_ id: String, to name: String) {
		do { try persist(library.renaming_group(id, to: name, now: .now)) } catch { report(error) }
	}

	@discardableResult
	func remove_group(_ id: String) -> Bool {
		do { try persist(library.removing_group(id)); return true } catch { report(error); return false }
	}

	func report(_ error: Error) {
		logger.error("Library operation failed: \(error.localizedDescription, privacy: .public)")
		error_message = error.localizedDescription
	}

	@discardableResult
	func save(_ document: AppDocument) -> Bool {
		do { try persist(library.upserting(document, now: .now)); return true }
		catch { report(error); return false }
	}

	func create(from routine: Routine) -> AppDocument? { add(routine.instantiate()) }
	func create_blank() -> AppDocument? { add(AppDocument.blank()) }

	func duplicate(_ id: String) -> AppDocument? {
		do { let result = try library.duplicating(id, now: .now); try persist(result.library); return result.document }
		catch { report(error); return nil }
	}

	func import_document(_ document: AppDocument) -> AppDocument? {
		do { let result = try library.importing(document, now: .now); try persist(result.library); return result.document }
		catch { report(error); return nil }
	}

	func delete(_ id: String) {
		do { try persist(library.deleting(id)) } catch { report(error) }
	}

	func set_enabled(_ id: String, _ enabled: Bool) {
		guard var document = library.find(id), document.is_standing else { return }
		document.enabled = enabled
		do { try persist(library.upserting(document, now: .now)) } catch { report(error) }
	}

	// Discards unreadable saved data at the user's explicit request so the app becomes usable again.
	func replace_unreadable() {
		storage_blocked = false
		do { try persist(library) } catch { report(error) }
	}

	private func add(_ document: AppDocument) -> AppDocument? {
		do { try persist(library.upserting(document, now: .now)); return document }
		catch { report(error); return nil }
	}

	private func persist(_ next: ToolLibrary) throws {
		guard !storage_blocked else { throw DocumentError.invalid("Saved tools need attention before new changes can be kept. Choose Replace unreadable data from the menu.") }
		defaults.set(try next.encoded(), forKey: Self.library_key)
		defaults.removeObject(forKey: Self.legacy_key)
		library = next
	}
}
