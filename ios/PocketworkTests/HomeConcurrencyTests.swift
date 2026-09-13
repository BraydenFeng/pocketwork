import Darwin
import XCTest
@testable import Pocketwork

final class HomeConcurrencyTests: XCTestCase {
	enum Failure: Error { case expected }
	func test_slow_setup_leaves_main_queue_responsive() async throws {
		let started = expectation(description: "worker started")
		let responsive = expectation(description: "main queue remained responsive")
		let release = DispatchSemaphore(value: 0)
		let work = Task {
			try await HomeWorker.run {
				XCTAssertFalse(Thread.isMainThread)
				started.fulfill()
				XCTAssertEqual(release.wait(timeout: .now() + 3), .success)
			}
		}
		await fulfillment(of: [started], timeout: 2)
		DispatchQueue.main.async { responsive.fulfill(); release.signal() }
		await fulfillment(of: [responsive], timeout: 2)
		try await work.value
	}
	func test_worker_propagates_failure_and_accepts_next_operation() async throws {
		do { try await HomeWorker.run { throw Failure.expected }; XCTFail("Expected setup failure") }
		catch Failure.expected {} catch { XCTFail("Unexpected error: \(error)") }
		let value = try await HomeWorker.run { 7 }
		XCTAssertEqual(value, 7)
	}
	func test_lock_releases_on_error_and_never_waits_forever() throws {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { do { try FileManager.default.removeItem(at: folder) } catch { XCTFail("Cleanup failed: \(error)") } }
		let file = folder.appendingPathComponent("home.lock")
		XCTAssertThrowsError(try HomeFileLock.with_lock(at: file) { throw Failure.expected })
		try HomeFileLock.with_lock(at: file) {
			let start = ProcessInfo.processInfo.systemUptime
			XCTAssertThrowsError(try HomeFileLock.with_lock(at: file, timeout: 0.02) { XCTFail("Contending lock acquired") })
			XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 0.5)
		}
		XCTAssertEqual(try HomeFileLock.with_lock(at: file) { 1 }, 1)
	}
}
