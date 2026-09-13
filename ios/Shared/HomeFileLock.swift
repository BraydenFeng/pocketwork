import Darwin
import Foundation

enum HomeFileLock {
	static func with_lock<T>(at file: URL, timeout: TimeInterval = 2, _ action: () throws -> T) throws -> T {
		let descriptor = open(file.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
		guard descriptor >= 0 else { throw DocumentError.invalid("Could not open the home allowance lock.") }
		defer { close(descriptor) }
		let deadline = ProcessInfo.processInfo.systemUptime + timeout
		while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
			guard errno == EWOULDBLOCK || errno == EAGAIN, ProcessInfo.processInfo.systemUptime < deadline else { throw DocumentError.invalid("Home allowance is updating. Try again in a moment.") }
			usleep(5_000)
		}
		defer { flock(descriptor, LOCK_UN) }
		return try action()
	}
}
