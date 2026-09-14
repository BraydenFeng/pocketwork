import Foundation

// What the home screen widget needs to know about each routine, written by the app into the App Group so the widget never loads the library.
struct RoutineTile: Codable, Equatable, Identifiable {
	var id: String
	var name: String
	var summary: String
	var status: String
	var standing: Bool
	var enabled: Bool
	var running: Bool
	var ends_at: Date?
}

enum WidgetSnapshotError: LocalizedError {
	case no_app_group
	var errorDescription: String? { "App Group is not configured, so widgets cannot be updated." }
}

struct WidgetSnapshot: Codable, Equatable {
	static let key = "widget_snapshot.v1"
	static let scheme = "com.braydenfeng.pocketwork"

	var tiles: [RoutineTile]
	var updated_at: Date

	static func url(for routine_id: String) -> URL? { URL(string: "\(scheme)://routine/\(routine_id)") }

	static func routine_id(from url: URL) -> String? {
		guard url.scheme == scheme, url.host == "routine" else { return nil }
		let id = url.lastPathComponent
		return id.isEmpty ? nil : id
	}

	// Both the app and the widget read the same App Group; the group name travels in each target's Info.plist.
	static func defaults(bundle: Bundle = .main) -> UserDefaults? {
		guard let group = bundle.object(forInfoDictionaryKey: "PocketworkAppGroup") as? String else { return nil }
		return UserDefaults(suiteName: group)
	}

	static func load(bundle: Bundle = .main) -> WidgetSnapshot? {
		guard let data = defaults(bundle: bundle)?.data(forKey: key) else { return nil }
		do { return try JSONDecoder().decode(WidgetSnapshot.self, from: data) }
		catch { return nil }
	}

	func save(bundle: Bundle = .main) throws {
		guard let defaults = Self.defaults(bundle: bundle) else { throw WidgetSnapshotError.no_app_group }
		defaults.set(try JSONEncoder().encode(self), forKey: Self.key)
	}
}
