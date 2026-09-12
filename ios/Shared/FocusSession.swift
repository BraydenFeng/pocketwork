import Foundation

struct FocusSession: Codable, Equatable {
	let activity_name: String
	let document_id: String
	let ends_at: Date
	let blocks_apps: Bool

	func remaining(at now: Date) -> Int { max(0, Int(ceil(ends_at.timeIntervalSince(now)))) }
	func has_ended(at now: Date) -> Bool { now >= ends_at }
}
