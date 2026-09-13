import Foundation

// Screen Time IPC can block; a serial worker preserves app-operation order without blocking SwiftUI.
enum HomeWorker {
	private static let queue = DispatchQueue(label: "pocketwork.home.worker", qos: .userInitiated)
	static func run<T>(_ operation: @escaping () throws -> T) async throws -> T {
		try await withCheckedThrowingContinuation { continuation in
			queue.async {
				do { continuation.resume(returning: try operation()) }
				catch { continuation.resume(throwing: error) }
			}
		}
	}
}
