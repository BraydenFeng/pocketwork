import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import UIKit

struct CloudUser: Codable { let id: String; let email: String? }
struct CloudSession: Codable {
	let access_token: String
	let refresh_token: String
	let expires_in: Double
	let user: CloudUser
	var saved_at: Date? = nil
	var needs_refresh: Bool { Date().timeIntervalSince(saved_at ?? .distantPast) > expires_in - 60 }
}

@MainActor
final class CloudController: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
	@Published private(set) var email: String?
	@Published private(set) var signed_in = false
	@Published private(set) var busy = false
	@Published private(set) var status = "Sign in on both devices with the same account."
	@Published var error_message: String?
	@Published var share_status = StatusReporter.sharing { didSet { StatusReporter.sharing = share_status; Task { await publish_status(force: true) } } }
	@Published private(set) var status_shared_at: Date?
	private var last_report: StatusReport?
	private var session: CloudSession?
	private var web_session: ASWebAuthenticationSession?
	private var syncing = false
	private var generation = 0
	private weak var library: LibraryController?
	private weak var sessions: SessionController?
	private var pending_save: Task<Void, Never>?
	private var endpoint: String { Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? "" }
	private var public_key: String { Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? "" }
	var configured: Bool { endpoint.hasPrefix("https://") && !public_key.isEmpty }
	var account_id: UUID? { session.flatMap { UUID(uuidString: $0.user.id) } }
	var website: URL? {
		guard let raw = Bundle.main.object(forInfoDictionaryKey: "PocketworkWebsiteURL") as? String, let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
		return url
	}
	private var deleting = false
	private var keychain_query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Pocketwork.Cloud", kSecAttrAccount as String: endpoint] }

	func attach(_ library: LibraryController, _ sessions: SessionController) async {
		guard self.library == nil else { return }
		self.library = library; self.sessions = sessions
		library.on_local_change = { [weak self] in
			self?.pending_save?.cancel()
			self?.pending_save = Task { [weak self] in
				do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
				await self?.sync()
			}
		}
		guard configured, !CommandLine.arguments.contains("--ui-testing") else { return }
		do {
			var query = keychain_query; query[kSecReturnData as String] = true
			var value: CFTypeRef?
			let code = SecItemCopyMatching(query as CFDictionary, &value)
			if code == errSecItemNotFound { return }
			guard code == errSecSuccess, let data = value as? Data else { throw DocumentError.invalid("Could not read your saved sign-in.") }
			let saved = try JSONDecoder().decode(CloudSession.self, from: data)
			try library.switch_account(saved.user.id)
			session = saved; email = saved.user.email; signed_in = true
			await sync()
		} catch { fail(error) }
	}

	func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
		UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
	}

	func sign_in(provider: String) {
		guard configured, !busy, !signed_in else { return }
		busy = true; error_message = nil
		// PKCE binds the callback code to this particular login attempt.
		let verifier = UUID().uuidString + UUID().uuidString
		let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
		var url = URLComponents(string: endpoint + "/auth/v1/authorize")!
		url.queryItems = [URLQueryItem(name: "provider", value: provider), URLQueryItem(name: "redirect_to", value: "com.braydenfeng.pocketwork://auth/callback"), URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "code_challenge_method", value: "s256")]
		web_session = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "com.braydenfeng.pocketwork") { [weak self] callback, error in
			Task { @MainActor in
				guard let self else { return }
				defer { self.busy = false; self.web_session = nil }
				do {
					if let error { throw error }
					guard let callback, callback.host == "auth", callback.path == "/callback", let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else { throw DocumentError.invalid("Sign-in did not return a code. Check the Supabase mobile redirect URL.") }
					let data = try await self.request("auth/v1/token?grant_type=pkce", method: "POST", body: JSONSerialization.data(withJSONObject: ["auth_code": code, "code_verifier": verifier]))
					var found = try JSONDecoder().decode(CloudSession.self, from: data); found.saved_at = .now
					try self.library?.switch_account(found.user.id)
					try self.store(found)
					self.session = found; self.email = found.user.email; self.signed_in = true; self.generation += 1
					await self.sync()
				} catch { self.fail(error) }
			}
		}
		web_session?.presentationContextProvider = self
		web_session?.prefersEphemeralWebBrowserSession = true
		if web_session?.start() != true { busy = false; fail(DocumentError.invalid("Could not open sign-in. Please try again.")) }
	}

	func sign_out() {
		guard !syncing, !busy else { return }
		busy = true
		Task {
		defer { busy = false }
		do {
			let code = SecItemDelete(keychain_query as CFDictionary)
			guard code == errSecSuccess || code == errSecItemNotFound else { throw DocumentError.invalid("Could not clear the saved sign-in.") }
			for id in await sessions?.clear_everything() ?? [] { library?.set_enabled(id, false) }
			try library?.switch_account(nil)
			generation += 1; session = nil; signed_in = false; email = nil; status = "Signed out. Your cloud routines are kept in your account."
		} catch { fail(error) }
		}
	}
	func api_request(_ path: String, body: [String: String]? = nil) async throws -> Data {
		guard let website, var credentials = session else { throw DocumentError.invalid("Sign in and configure the public website first.") }
		let epoch = generation
		if credentials.needs_refresh {
			let data = try await request("auth/v1/token?grant_type=refresh_token", method: "POST", body: JSONSerialization.data(withJSONObject: ["refresh_token": credentials.refresh_token]))
			credentials = try JSONDecoder().decode(CloudSession.self, from: data); credentials.saved_at = .now
			guard epoch == generation else { throw DocumentError.invalid("Your account changed. Try again.") }
			try store(credentials); session = credentials
		}
		var request = URLRequest(url: website.appendingPathComponent(path)); request.timeoutInterval = 30
		request.setValue("Bearer " + credentials.access_token, forHTTPHeaderField: "Authorization")
		if let body { request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
		let (data, response) = try await URLSession.shared.data(for: request)
		guard epoch == generation else { throw DocumentError.invalid("Your account changed. Try again.") }
		guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
			struct Failure: Decodable { let error: String }
			let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? "Account service unavailable. Please retry."
			throw DocumentError.invalid(message)
		}
		return data
	}
	struct PagePlan: Decodable { let pro: Bool; let expires_at: String?; let configured: Bool }
	func refresh_plan(transaction_id: String? = nil) async throws {
		guard website != nil, signed_in, Bundle.main.object(forInfoDictionaryKey: "PocketworkSubscriptionsEnabled") as? Bool == true else { return }
		let data = try await api_request("api/subscription", body: transaction_id.map { ["transaction_id": $0] })
		let plan = try JSONDecoder().decode(PagePlan.self, from: data)
		let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		library?.pro_until = plan.pro ? plan.expires_at.flatMap { formatter.date(from: $0) } : nil
	}
	func delete_account() async {
		guard !busy, !syncing, signed_in else { return }
		busy = true; deleting = true; pending_save?.cancel(); error_message = nil
		do {
			struct Reply: Decodable { let deleted: Bool; let authorize_url: String?; let state: String? }
			let reply = try JSONDecoder().decode(Reply.self, from: try await api_request("api/account/delete", body: ["confirm": "DELETE", "platform": "ios"]))
			if reply.deleted { try await finish_deletion(); busy = false; deleting = false; return }
			guard let raw = reply.authorize_url, let url = URL(string: raw), url.scheme == "https", url.host == "appleid.apple.com", let state = reply.state else { throw DocumentError.invalid("Apple confirmation could not start.") }
			web_session = ASWebAuthenticationSession(url: url, callbackURLScheme: "com.braydenfeng.pocketwork") { [weak self] callback, error in
				Task { @MainActor in
					guard let self else { return }; defer { self.busy = false; self.deleting = false; self.web_session = nil }
					do {
						if let error { throw error }
						guard let callback, callback.host == "account", callback.path == "/deleted", let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems, items.first(where: { $0.name == "state" })?.value == state, items.first(where: { $0.name == "deleted" })?.value == "true" else { throw DocumentError.invalid("Deletion did not finish. Start again from Account.") }
						try await self.finish_deletion()
					} catch { self.fail(error) }
				}
			}
			web_session?.presentationContextProvider = self
			if web_session?.start() != true { throw DocumentError.invalid("Could not open Apple's confirmation.") }
		} catch { busy = false; deleting = false; fail(error) }
	}
	private func finish_deletion() async throws {
		generation += 1; pending_save?.cancel()
		let document_ids = library?.library.tools.map(\.id) ?? []
		let group_ids = library?.groups.map(\.id) ?? []
		let failures = await AccountCleanup.run([
			("Sessions", {
				self.sessions?.error_message = nil
				for id in document_ids { await self.sessions?.forget(id) }
				_ = await self.sessions?.clear_everything()
				if let error = self.sessions?.error_message { throw DocumentError.invalid(error) }
			}),
			("Saved location", { try await HomeLocationController.shared.forget_account_data() }),
			("Page restrictions", { try await HomeWorker.run { try BuilderAppRules.clear() } }),
			("App selections", {
				let shared = try SharedStore()
				for id in document_ids { shared.remove_selection(for: id); shared.remove_plan(for: id); shared.set_standing(id, enabled: false) }
				for id in group_ids { shared.remove_group_selection(id) }
			}),
			("Saved sign-in", {
				let code = SecItemDelete(self.keychain_query as CFDictionary)
				guard code == errSecSuccess || code == errSecItemNotFound else { throw DocumentError.invalid("Could not remove this iPhone's saved sign-in (\(code)).") }
			})
		])
		library?.purge_account(); session = nil; signed_in = false; email = nil
		StatusReporter.sharing = false; share_status = false; last_report = nil; status_shared_at = nil
		if !failures.isEmpty {
			status = "Account deleted. This iPhone's cleanup needs attention."
			throw DocumentError.invalid("Your cloud account was deleted, but device cleanup did not fully finish. Use Clear all focus restrictions and remove local app data before reusing this iPhone. " + failures.joined(separator: " · "))
		}
		status = "Account deleted. Your cloud pages and this iPhone's account library were removed."
	}

	private func store(_ value: CloudSession) throws {
		let data = try JSONEncoder().encode(value)
		let updated = SecItemUpdate(keychain_query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
		if updated == errSecSuccess { return }
		guard updated == errSecItemNotFound else { throw DocumentError.invalid("Could not securely save your sign-in.") }
		var query = keychain_query; query[kSecValueData as String] = data
		query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw DocumentError.invalid("Could not securely save your sign-in.") }
	}

	private func request(_ path: String, method: String = "GET", body: Data? = nil, token: String? = nil, prefer: String? = nil) async throws -> Data {
		guard let url = URL(string: endpoint + "/" + path) else { throw DocumentError.invalid("Cloud address is not configured.") }
		var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 30
		request.setValue(public_key, forHTTPHeaderField: "apikey")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
		if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
		let (data, response) = try await URLSession.shared.data(for: request)
		guard let response = response as? HTTPURLResponse else { throw DocumentError.invalid("No response from the cloud. Try again when online.") }
		if response.statusCode == 409 { throw CloudConflict.changed }
		guard (200..<300).contains(response.statusCode) else { throw DocumentError.invalid("Cloud request failed (\(response.statusCode)). Check your connection or sign in again.") }
		return data
	}

	private enum CloudConflict: Error { case changed }
	private struct Row: Decodable { let library: ToolLibrary; let updated_at: String }
	private struct WriteRow: Encodable { let user_id: String; let library: ToolLibrary }

	func sync() async {
		guard var credentials = session, let library, !library.storage_blocked, !syncing, !deleting else { return }
		syncing = true; status = "Syncing…"
		let epoch = generation
		defer { syncing = false }
		do {
			if credentials.needs_refresh {
				let data = try await request("auth/v1/token?grant_type=refresh_token", method: "POST", body: JSONSerialization.data(withJSONObject: ["refresh_token": credentials.refresh_token]))
				credentials = try JSONDecoder().decode(CloudSession.self, from: data); credentials.saved_at = .now
				guard generation == epoch else { return }
				try store(credentials); session = credentials
			}
			for _ in 0..<5 {
				let path = "rest/v1/libraries?user_id=eq." + credentials.user.id
				let data = try await request(path + "&select=library,updated_at", token: credentials.access_token)
				guard generation == epoch else { return }
				let remote = try JSONDecoder().decode([Row].self, from: data).first
				if let remote { try remote.library.validate() }
				let old = library.library
				let merged = try remote.map { try old.merging($0.library) } ?? old
				if merged != old {
					try library.receive_cloud(merged)
					// Cloud settings take effect when this app opens, after on-device consent and selection.
					for entry in old.tools {
						if merged.find(entry.id) == nil { await sessions?.forget(entry.id) }
						else if entry.document.is_standing && merged.find(entry.id)?.is_standing != true { _ = await sessions?.set_routine(entry.document, enabled: false, groups: old.groups ?? []) }
					}
					for entry in merged.tools where entry.document.is_standing {
						if old.find(entry.id) != entry.document || old.groups != merged.groups {
							_ = await sessions?.set_routine(entry.document, enabled: entry.document.enabled == true, groups: merged.groups ?? [])
						}
					}
				}
				if remote?.library != merged {
					if merged.tools.count > 3 && merged.tools.contains(where: { remote?.library.find($0.id) == nil }) { try await refresh_plan() }
					let stamp = remote?.updated_at.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
					let write_path = remote == nil ? "rest/v1/libraries" : path + "&updated_at=eq." + stamp
					do {
						let written = try await request(write_path, method: remote == nil ? "POST" : "PATCH", body: JSONEncoder().encode(WriteRow(user_id: credentials.user.id, library: merged)), token: credentials.access_token, prefer: "return=representation")
						let rows = try JSONDecoder().decode([Row].self, from: written)
						if rows.isEmpty { continue }
					} catch CloudConflict.changed { continue }
				}
				if merged != library.library { continue }
				status = "Synced with your account"; error_message = nil
				await publish_status()
				return
			}
			throw DocumentError.invalid("Another device is saving. Pull to refresh to retry.")
		} catch { status = "Saved on this iPhone · sync needs attention"; fail(error) }
	}

	private struct StatusRow: Encodable { let user_id: String; let status: StatusReport }

	// Shares minute counts and running state with the account when the person has opted in. Silent when nothing changed.
	func publish_status(force: Bool = false) async {
		guard share_status, let credentials = session, let library else {
			if !share_status, let credentials = session { await clear_status(credentials) }
			return
		}
		let home = try? await HomeWorker.run { try HomeEngine.snapshot() }
		let report = StatusReporter.build(library: library.library, session: sessions?.session, home: home)
		var comparable = report; comparable.reported_at = ""
		var previous = last_report; previous?.reported_at = ""
		if !force, previous == comparable { return }
		do {
			_ = try await request("rest/v1/routine_status?on_conflict=user_id", method: "POST", body: JSONEncoder().encode(StatusRow(user_id: credentials.user.id, status: report)), token: credentials.access_token, prefer: "resolution=merge-duplicates,return=minimal")
			last_report = report; status_shared_at = .now
		} catch { fail(error) }
	}

	private func clear_status(_ credentials: CloudSession) async {
		guard last_report != nil || status_shared_at != nil else { return }
		do { _ = try await request("rest/v1/routine_status?user_id=eq." + credentials.user.id, method: "DELETE", token: credentials.access_token, prefer: "return=minimal"); last_report = nil; status_shared_at = nil }
		catch { fail(error) }
	}

	private func fail(_ error: Error) { error_message = error.localizedDescription }
}
