import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionController: ObservableObject {
	@Published private(set) var product: Product?
	@Published private(set) var busy = false
	@Published var message: String?
	private weak var cloud: CloudController?
	private var updates: Task<Void, Never>?
	private var product_id: String { Bundle.main.object(forInfoDictionaryKey: "PocketworkProProductID") as? String ?? "" }
	var configured: Bool { Bundle.main.object(forInfoDictionaryKey: "PocketworkSubscriptionsEnabled") as? Bool == true && cloud?.website != nil }
	func attach(_ cloud: CloudController) async {
		guard self.cloud == nil else { return }; self.cloud = cloud
		guard configured, !CommandLine.arguments.contains("--ui-testing") else { return }
		updates = Task { [weak self] in
			for await result in Transaction.updates {
				guard let self else { return }
				do { try await self.deliver(result) } catch { self.message = "Purchase needs attention: " + error.localizedDescription }
			}
		}
		do {
			let found = try await Product.products(for: [product_id]).first
			guard let found, found.type == .autoRenewable, found.subscription?.subscriptionPeriod.unit == .month, found.subscription?.subscriptionPeriod.value == 1 else { throw DocumentError.invalid("The monthly subscription is not available yet.") }
			product = found
		} catch { message = "Could not load subscription: " + error.localizedDescription }
	}
	func refresh() async {
		guard configured, cloud?.account_id != nil else { return }
		do {
			for await result in Transaction.unfinished { try await deliver(result) }
			for await result in Transaction.currentEntitlements { try await deliver(result) }
			try await cloud?.refresh_plan()
		} catch { message = error.localizedDescription }
	}
	private func deliver(_ result: VerificationResult<Transaction>) async throws {
		guard case .verified(let transaction) = result else { throw DocumentError.invalid("Apple could not verify this purchase.") }
		guard transaction.productID == product_id else { return }
		guard let cloud, let account = cloud.account_id, transaction.appAccountToken == account else { throw DocumentError.invalid("Restore using the Pocketwork account that bought this subscription.") }
		try await cloud.refresh_plan(transaction_id: String(transaction.id))
		await transaction.finish()
	}
	func purchase() async {
		guard !busy, let product, let cloud, let account = cloud.account_id else { message = "Sign in before subscribing."; return }
		busy = true; message = nil; defer { busy = false }
		do {
			switch try await product.purchase(options: [.appAccountToken(account)]) {
			case .success(let result): try await deliver(result); message = "Your subscription is ready."
			case .pending: message = "Purchase pending Apple's approval. No upgrade has been applied yet."
			case .userCancelled: message = "Purchase cancelled."
			@unknown default: message = "Check your purchase status with Restore purchases."
			}
		} catch { message = error.localizedDescription }
	}
	func restore() async {
		guard !busy else { return }; busy = true; defer { busy = false }
		do { try await AppStore.sync(); await refresh() } catch { message = "Restore failed: " + error.localizedDescription }
	}
}
