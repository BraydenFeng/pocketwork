import Foundation

@MainActor
enum AccountCleanup {
	// A failed device service must not leave the deleted account signed in or skip other cleanup.
	static func run(_ steps: [(String, () async throws -> Void)]) async -> [String] {
		var failures: [String] = []
		for (name, action) in steps {
			do { try await action() }
			catch { failures.append(name + ": " + error.localizedDescription) }
		}
		return failures
	}
}
