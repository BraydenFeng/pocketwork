import SwiftUI

struct AccountView: View {
	@EnvironmentObject private var cloud: CloudController
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if cloud.configured {
				Text(cloud.email ?? "Your routines, on both devices").heading_font(15)
				Text(cloud.status).supporting()
				if cloud.signed_in {
					HStack {
						Button("Sync now") { Task { await cloud.sync() } }.buttonStyle(QuietButtonStyle())
						Button("Sign out") { cloud.sign_out() }.buttonStyle(TextButtonStyle())
					}
				} else {
					HStack {
						Button("Sign in with Apple") { cloud.sign_in(provider: "apple") }.buttonStyle(PrimaryButtonStyle())
						if Bundle.main.object(forInfoDictionaryKey: "SupabaseGoogleEnabled") as? Bool == true { Button("Google") { cloud.sign_in(provider: "google") }.buttonStyle(QuietButtonStyle()) }
					}.disabled(cloud.busy)
				}
				if let error = cloud.error_message { Text(error).font(.system(size: 13)).foregroundStyle(Theme.danger) }
			} else { Text("Cloud sync is not configured in this build.").supporting() }
		}
		.padding(Theme.pad)
	}
}
