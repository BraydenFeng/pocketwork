import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionController: ObservableObject {
	@Published private(set) var product: Product?
	@Published private(set) var busy = false
	@Published private(set) var environment: PurchaseEnvironment?
	@Published var message: String?
	private weak var cloud: CloudController?
	private var updates: Task<Void, Never>?
	private var refreshing = false
	private var loading = false
	private var product_id: String { Bundle.main.object(forInfoDictionaryKey: "PocketworkProProductID") as? String ?? "" }
	var configured: Bool { Bundle.main.object(forInfoDictionaryKey: "PocketworkSubscriptionsEnabled") as? Bool == true && cloud?.website != nil }
	var is_sandbox: Bool { environment == .sandbox }
	func attach(_ cloud: CloudController) async {
		guard self.cloud == nil else { return }; self.cloud = cloud
		guard configured, !CommandLine.arguments.contains("--ui-testing") else { return }
		updates = Task { [weak self] in
			for await result in Transaction.updates {
				guard let self else { return }
				guard self.cloud?.account_id != nil else { continue }
				do { _ = try await self.deliver(result) } catch { self.message = "Purchase needs attention: " + error.localizedDescription }
			}
		}
		await load_product()
	}
	func load_product() async {
		// AppTransaction may request Apple authentication; guests have not asked to buy anything.
		guard configured, cloud?.account_id != nil, !loading, !CommandLine.arguments.contains("--ui-testing") else { return }
		loading = true; defer { loading = false }
		do {
			guard case .verified(let app) = try await AppTransaction.shared else { throw DocumentError.invalid("Apple could not verify this app installation.") }
			environment = try Self.purchase_environment(app.environment)
			let found = try await Product.products(for: [product_id]).first
			guard let found, found.type == .autoRenewable, found.subscription?.subscriptionPeriod.unit == .month, found.subscription?.subscriptionPeriod.value == 1 else { throw DocumentError.invalid("The monthly subscription is not available yet.") }
			product = found
			message = nil
		} catch { message = "Could not load subscription: " + error.localizedDescription }
	}
	static func purchase_environment(_ value: AppStore.Environment) throws -> PurchaseEnvironment {
		if value == .production { return .production }
		if value == .sandbox { return .sandbox }
		throw DocumentError.invalid("Local StoreKit test purchases cannot unlock this account.")
	}
	func refresh() async {
		guard configured, !refreshing, !busy, let account = cloud?.account_id, !CommandLine.arguments.contains("--ui-testing") else { return }
		refreshing = true; defer { refreshing = false }
		do { try await refresh_entitlements(for: account) }
		catch { message = "Could not refresh purchases: " + error.localizedDescription }
	}
	private func refresh_entitlements(for account: UUID) async throws {
		if environment == nil || product == nil { await load_product() }
		guard environment != nil else { throw DocumentError.invalid("Purchase environment is unavailable. Try again when online.") }
		for await result in Transaction.unfinished {
			guard cloud?.account_id == account else { return }
			if case .verified(let transaction) = result, transaction.productID == product_id, transaction.appAccountToken == account { _ = try await deliver(result) }
		}
		// Includes refunded/expired purchases that no longer appear in currentEntitlements.
		if let latest = await Transaction.latest(for: product_id) {
			guard cloud?.account_id == account else { return }
			guard case .verified(let transaction) = latest else { throw DocumentError.invalid("Apple could not verify your purchase history.") }
			if transaction.appAccountToken == account { _ = try await deliver(latest) }
			else { cloud?.clear_test_plan() }
		} else {
			guard cloud?.account_id == account else { return }
			cloud?.clear_test_plan()
		}
		guard cloud?.account_id == account else { return }
		try await cloud?.refresh_plan()
	}
	private func deliver(_ result: VerificationResult<Transaction>) async throws -> Bool {
		guard case .verified(let transaction) = result else { throw DocumentError.invalid("Apple could not verify this purchase.") }
		guard transaction.productID == product_id else { return false }
		guard let cloud, let account = cloud.account_id, transaction.appAccountToken == account else { throw DocumentError.invalid("Restore using the Pocketwork account that bought this subscription.") }
		if environment == nil { await load_product() }
		let source = try Self.purchase_environment(transaction.environment)
		guard source == environment else { throw DocumentError.invalid("This purchase belongs to a different App Store environment.") }
		let active = try await cloud.refresh_plan(transaction_id: String(transaction.id), environment: source)
		await transaction.finish()
		return active
	}
	func purchase() async {
		guard !busy, !refreshing, let product, let cloud, let account = cloud.account_id else { message = "Sign in and wait for purchase loading to finish."; return }
		busy = true; message = nil; defer { busy = false }
		do {
			switch try await product.purchase(options: [.appAccountToken(account)]) {
			case .success(let result):
				let active = try await deliver(result)
				message = active ? (is_sandbox ? "Test purchase verified. Pro is active on this phone, not the live website. You were not charged." : "Your subscription is ready.") : "Apple verified the purchase, but it is no longer active."
			case .pending: message = "Purchase pending Apple's approval. No upgrade has been applied yet."
			case .userCancelled: message = "Purchase cancelled."
			@unknown default: message = "Check your purchase status with Restore purchases."
			}
		} catch { message = "Purchase needs attention: " + error.localizedDescription }
	}
	func restore() async {
		guard !busy, !refreshing, let account = cloud?.account_id else { return }
		busy = true; message = nil; defer { busy = false }
		do {
			try await AppStore.sync()
			guard cloud?.account_id == account else { throw DocumentError.invalid("Your account changed. Restore again after signing in.") }
			try await refresh_entitlements(for: account)
			message = "Purchase status refreshed."
		} catch { message = "Restore failed: " + error.localizedDescription }
	}
}
