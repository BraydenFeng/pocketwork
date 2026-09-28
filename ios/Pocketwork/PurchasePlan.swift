import Foundation

enum PurchaseEnvironment: String {
	case production = "Production"
	case sandbox = "Sandbox"
	var verification_path: String { self == .sandbox ? "api/subscription/sandbox" : "api/subscription" }
}

struct PurchasePlan: Decodable {
	let pro: Bool
	let expires_at: String?
	let configured: Bool
	let environment: String?

	func active_until(in expected: PurchaseEnvironment, now: Date = .now) throws -> Date? {
		let actual = environment ?? "Production"
		guard actual == expected.rawValue else { throw DocumentError.invalid("The purchase response came from the wrong environment.") }
		guard configured else { throw DocumentError.invalid("Subscriptions are not configured on the server.") }
		guard pro else { return nil }
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		guard let raw = expires_at else { throw DocumentError.invalid("The purchase response has no expiration.") }
		let fractional = formatter.date(from: raw)
		formatter.formatOptions = [.withInternetDateTime]
		guard let expiration = fractional ?? formatter.date(from: raw) else { throw DocumentError.invalid("The purchase expiration is unreadable.") }
		return expiration > now ? expiration : nil
	}
}
