import Foundation

// A ready-made routine bundled with the app. The document is a template; instantiating it assigns a fresh ID so two copies can coexist.
struct Routine: Codable, Identifiable, Equatable {
	var template_id: String
	var tagline: String
	var document: AppDocument

	var id: String { template_id }
	var name: String { document.name }

	func instantiate() -> AppDocument {
		var copy = document
		copy.id = UUID().uuidString
		return copy
	}
}

struct RoutineCatalog: Codable, Equatable {
	var schema_version: Int
	var routines: [Routine]

	static func decode(_ data: Data) throws -> RoutineCatalog {
		let catalog: RoutineCatalog
		do { catalog = try JSONDecoder().decode(RoutineCatalog.self, from: data) }
		catch { throw DocumentError.invalid("The bundled routines could not be read. \(error.localizedDescription)") }
		guard catalog.schema_version == 1 else { throw DocumentError.invalid("The bundled routines use an unsupported version.") }
		for routine in catalog.routines { try routine.document.validate() }
		return catalog
	}

	static func bundled(in bundle: Bundle = .main) throws -> RoutineCatalog {
		guard let url = bundle.url(forResource: "routines.pocketwork", withExtension: "json") else {
			throw DocumentError.invalid("The bundled routines are missing from this build.")
		}
		return try decode(Data(contentsOf: url))
	}
}
