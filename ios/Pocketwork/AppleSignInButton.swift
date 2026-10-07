import AuthenticationServices
import SwiftUI

// Apple's own Sign in with Apple button. App Review rejects home-made versions: the artwork and wording must be Apple's.
// It starts the same account sign-in as before.
struct AppleSignInButton: View {
	let action: @MainActor () -> Void
	var body: some View {
		SystemButton(action: action).frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
	}

	private struct SystemButton: UIViewRepresentable {
		let action: @MainActor () -> Void
		@Environment(\.isEnabled) private var is_enabled
		func makeCoordinator() -> Coordinator { Coordinator(action: action) }
		func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
			// The app always uses the light appearance, where Apple's guidelines call for the black button.
			let button = ASAuthorizationAppleIDButton(authorizationButtonType: .continue, authorizationButtonStyle: .black)
			button.cornerRadius = Theme.radius_small
			button.accessibilityIdentifier = "account.apple"
			button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
			return button
		}
		func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
			context.coordinator.action = action
			button.isEnabled = is_enabled
			button.alpha = is_enabled ? 1 : 0.4
		}
		@MainActor final class Coordinator: NSObject {
			var action: @MainActor () -> Void
			init(action: @escaping @MainActor () -> Void) { self.action = action }
			@objc func tapped() { action() }
		}
	}
}
