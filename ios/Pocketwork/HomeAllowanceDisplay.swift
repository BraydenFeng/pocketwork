import Combine
import Foundation

@MainActor
final class HomeAllowanceDisplay: ObservableObject {
	@Published private(set) var remaining: Int?
	@Published private(set) var state: HomeState?
	private var refreshing = false
	private let read_state: () async throws -> HomeState
	private let now: () -> Date

	init(
		read_state: @escaping () async throws -> HomeState = { try await HomeWorker.run { try HomeEngine.snapshot() } },
		now: @escaping () -> Date = { .now }
	) {
		self.read_state = read_state
		self.now = now
	}

	func refresh(policy: HomePolicy?) async throws {
		guard !refreshing else { return }
		refreshing = true
		defer { refreshing = false }
		// Only read the ledger; restarting the meter here would interrupt usage tracking.
		let state = try await read_state()
		try Task.checkCancellation()
		let date = now()
		let same_day = state.ledger.day == policy?.day_key(date)
		let base = policy?.rule(at: date)?.allowance_minutes ?? 0
		let budget = same_day ? state.ledger.budget(base) : base
		remaining = max(0, budget - (same_day ? state.ledger.used_minutes : 0))
		self.state = state
	}
}
