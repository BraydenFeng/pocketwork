import SwiftUI

struct AccountView: View {
	@EnvironmentObject private var cloud: CloudController
	@EnvironmentObject private var sessions: SessionController
	@EnvironmentObject private var library: LibraryController
	@EnvironmentObject private var subscriptions: SubscriptionController
	@State private var deleting = false
	@State private var confirmation = ""
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if cloud.configured {
				Text(cloud.email ?? "Your routines, on both devices").heading_font(15)
				Text(cloud.status).supporting()
				if cloud.signed_in {
					Text(library.has_pro ? "Pocketwork Pro · up to 50 pages" : "Free · 3 pages at a time").heading_font(15)
					Text("MCP and sync are included. Pages hold routines and data. Existing pages stay available if you cancel Pro.").supporting()
					if subscriptions.configured {
						if let product = subscriptions.product, !library.has_pro { Button("Subscribe · " + product.displayPrice + " / month") { Task { await subscriptions.purchase() } }.buttonStyle(PrimaryButtonStyle()).disabled(subscriptions.busy) }
						else if !library.has_pro { Text("Subscription product is not available yet.").supporting() }
						Button("Restore purchases") { Task { await subscriptions.restore() } }.buttonStyle(TextButtonStyle()).disabled(subscriptions.busy)
						Text("Renews monthly until cancelled in your Apple account. Payment is charged to your Apple account.").supporting()
					} else { Text("Pro purchases are not enabled in this build.").supporting() }
					Link("Manage subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
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
					HStack {
						Button("Sign in with Apple") { cloud.sign_in(provider: "apple") }.buttonStyle(PrimaryButtonStyle())
						if Bundle.main.object(forInfoDictionaryKey: "SupabaseGoogleEnabled") as? Bool == true { Button("Google") { cloud.sign_in(provider: "google") }.buttonStyle(QuietButtonStyle()) }
					}.disabled(cloud.busy)
				}
				if let error = sessions.error_message { Text(error).font(.system(size: 13)).foregroundStyle(Theme.danger) }
				if let error = cloud.error_message { Text(error).font(.system(size: 13)).foregroundStyle(Theme.danger) }
			} else { Text("Cloud sync is not configured in this build.").supporting() }
			if let website = cloud.website {
				HStack { Link("Privacy", destination: website.appendingPathComponent("privacy")); Link("Terms", destination: website.appendingPathComponent("terms")); Link("Support", destination: website.appendingPathComponent("support")) }
			} else { Text("Public privacy and support links are not configured in this build.").supporting() }
		}
		.padding(Theme.pad)
		.alert("Permanently delete your account?", isPresented: $deleting) {
			TextField("Type DELETE", text: $confirmation).textInputAutocapitalization(.characters)
			Button("Delete account", role: .destructive) { Task { await cloud.delete_account() } }.disabled(confirmation != "DELETE")
			Button("Cancel", role: .cancel) { }
		} message: { Text("This deletes your cloud pages and this phone's account library. Export anything you want to keep. Cancel your Apple subscription separately first. Apple sign-in requires one more confirmation.") }
	}
}
