import SwiftUI

enum AccountIntent: String, Identifiable {
	case create, sign_in, manage
	var id: String { rawValue }
	var title: String {
		switch self {
		case .create: return "Create account"
		case .sign_in: return "Sign in"
		case .manage: return "Account & sync"
		}
	}
}

struct AccountView: View {
	var intent: AccountIntent = .manage
	@EnvironmentObject private var cloud: CloudController
	@EnvironmentObject private var sessions: SessionController
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var subscriptions: SubscriptionController
	@State private var deleting = false
	@State private var confirmation = ""
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if cloud.signed_in {
				Text(cloud.email ?? "Your routines, on both devices").heading_font(15)
				Text(cloud.status).supporting()
				Text(library.has_pro ? "Pocketwork Pro · up to 50 pages" : "Free · 3 pages at a time").heading_font(15)
				Text(subscriptions.configured ? "Sync and MCP are included. Existing pages stay available if you cancel Pro." : "Sync and MCP are included.").supporting()
				if subscriptions.configured {
					if let product = subscriptions.product, !library.has_pro { Button("Subscribe · " + product.displayPrice + " / month") { Task { await subscriptions.purchase() } }.buttonStyle(PrimaryButtonStyle()).disabled(subscriptions.busy) }
					else if !library.has_pro {
						Text("Subscription product is not available yet.").supporting()
						Button("Retry loading subscription") { Task { await subscriptions.load_product() } }.buttonStyle(TextButtonStyle()).disabled(subscriptions.busy)
					}
					Button("Restore purchases") { Task { await subscriptions.restore() } }.buttonStyle(TextButtonStyle()).disabled(subscriptions.busy)
					if subscriptions.is_sandbox {
						Text("TestFlight purchase testing. No charge. Test Pro applies to this phone only; extra test pages are not synced to the live website.").supporting()
					} else { Text("Renews monthly until cancelled in your Apple account. Payment is charged to your Apple account.").supporting() }
				}
				if subscriptions.configured || library.has_pro { Link("Manage subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!) }
				if let message = subscriptions.message { Text(message).supporting() }
				Hairline()
				HStack {
					Button("Sync now") { Task { await cloud.sync() } }.buttonStyle(QuietButtonStyle())
					Button("Sign out") { cloud.sign_out() }.buttonStyle(TextButtonStyle())
				}.disabled(cloud.busy)
				Hairline()
				ToggleRow(title: "Share status with your agents", description: cloud.share_status ? (cloud.status_shared_at.map { "Minutes left, running sessions, and a 30-day history. Last shared \($0.formatted(date: .omitted, time: .shortened))." } ?? "Minutes left, running sessions, and a 30-day history.") : "Off. Usage stays on this iPhone.", is_on: $cloud.share_status)
					.accessibilityIdentifier("account.share-status")
				Button("Delete account", role: .destructive) { confirmation = ""; deleting = true }.disabled(cloud.busy)
			} else {
				Text(intent == .create ? "Your pages, on both devices" : "Welcome back").heading_font(20)
				Text(intent == .create ? "Save your pages and open them on your iPhone, iPad, or computer." : "Use the same account you used before.").supporting()
				Text("Your first sign-in creates your Pocketwork account. No separate password needed.").supporting()
				if !cloud.configured {
					Text("Account access is unavailable in this build. You can still use pages on this device. Please try again after updating Pocketwork.").supporting().accessibilityIdentifier("account.unavailable")
				}
				Button("Continue with Apple") { cloud.sign_in(provider: "apple") }.buttonStyle(PrimaryButtonStyle()).disabled(!cloud.configured || cloud.busy).accessibilityIdentifier("account.apple")
				if Bundle.main.object(forInfoDictionaryKey: "SupabaseGoogleEnabled") as? Bool == true {
					Button("Continue with Google") { cloud.sign_in(provider: "google") }.buttonStyle(QuietButtonStyle()).disabled(!cloud.configured || cloud.busy).accessibilityIdentifier("account.google")
				}
				if cloud.busy { ProgressView("Opening sign-in…") }
			}
			if let error = sessions.error_message { Text(error).font(.system(size: 13)).foregroundStyle(Theme.danger) }
			if let error = cloud.error_message { Text(error).font(.system(size: 13)).foregroundStyle(Theme.danger).accessibilityIdentifier("account.error") }
			if let website = cloud.website {
				HStack { Link("Privacy", destination: website.appendingPathComponent("privacy")); Link("Terms", destination: website.appendingPathComponent("terms")); Link("Support", destination: website.appendingPathComponent("support")) }
			} else { Text("Public privacy and support links are not configured in this build.").supporting() }
		}
		.padding(Theme.pad)
		.alert("Permanently delete your account?", isPresented: $deleting) {
			TextField("Type DELETE", text: $confirmation).textInputAutocapitalization(.characters)
			Button("Delete account", role: .destructive) { Task { await cloud.delete_account() } }.disabled(confirmation != "DELETE")
			Button("Cancel", role: .cancel) { }
		} message: { Text("This deletes your cloud pages and this device's account library. Export anything you want to keep. " + (subscriptions.configured ? "Cancel your Apple subscription separately first. " : "") + "Apple sign-in requires one more confirmation.") }
	}
}
