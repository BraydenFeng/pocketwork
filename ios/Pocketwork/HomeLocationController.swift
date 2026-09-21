import UIKit
import Combine
import CoreLocation
import Foundation

@MainActor
final class HomeLocationController: NSObject, ObservableObject, CLLocationManagerDelegate {
	static let shared = HomeLocationController()
	@Published var status = "Set home while you are there."
	@Published var error_message: String?
	@Published var has_home = false
	@Published var at_location: Bool?
	@Published var always_allowed = false
	private let manager = CLLocationManager()
	private var setting_home = false
	private var generation = 0
	override init() {
		super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest
		if !CommandLine.arguments.contains("--ui-testing") { restore() }
	}
	func restore() {
		let epoch = generation
		Task { do {
			let state = try await HomeWorker.run { try HomeEngine.refresh_on_launch(); return try HomeEngine.snapshot() }
			guard epoch == generation else { return }; has_home = state.place != nil
			always_allowed = manager.authorizationStatus == .authorizedAlways
			if let place = state.place, always_allowed { monitor(place) }
		} catch { error_message = error.localizedDescription } }
	}
	func forget_account_data() async throws {
		generation += 1; setting_home = false; manager.stopUpdatingLocation()
		for region in manager.monitoredRegions where region.identifier == "pocketwork.home" { manager.stopMonitoring(for: region) }
		has_home = false; at_location = nil
		do {
			try await HomeWorker.run { try HomeEngine.forget_account_data() }
			status = "Saved location removed."; error_message = nil
		} catch { status = "Saved location could not be removed."; throw error }
	}
	func set_here() {
		setting_home = true
		if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
		else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { error_message = "Allow Location access in Settings first."; setting_home = false }
		else { manager.requestLocation() }
	}
	func allow_background() { manager.requestAlwaysAuthorization() }
	private func monitor(_ place: HomePlace) {
		guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { error_message = "Home detection is unavailable on this device."; return }
		let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude), radius: place.radius, identifier: "pocketwork.home")
		region.notifyOnEntry = true; region.notifyOnExit = true
		manager.startMonitoring(for: region); manager.requestState(for: region)
	}
	func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
		always_allowed = manager.authorizationStatus == .authorizedAlways
		if setting_home, manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { manager.requestLocation() }
		if always_allowed { restore() }
		else { update(false); status = "Allow Always location access for automatic home detection." }
	}
	func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
		guard setting_home, let location = locations.last else { return }
		guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100, abs(location.timestamp.timeIntervalSinceNow) < 60 else { error_message = "Could not locate home accurately. Try again near a window with Precise Location enabled."; setting_home = false; return }
		setting_home = false
		let epoch = generation
		Task { do { guard epoch == generation else { return }; let place = HomePlace(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude); try await HomeWorker.run { try HomeEngine.set_home(place) }; guard epoch == generation else { return }; has_home = true; monitor(place); if always_allowed { update(true) }; status = "Home saved on this iPhone." }
		catch { error_message = error.localizedDescription } }
	}
	func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) { if region.identifier == "pocketwork.home" { update(state == .inside && always_allowed) } }
	func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) { if region.identifier == "pocketwork.home" { update(always_allowed) } }
	func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) { if region.identifier == "pocketwork.home" { update(false) } }
	func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { error_message = error.localizedDescription; setting_home = false }
	func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) { error_message = error.localizedDescription; update(false) }
	private func update(_ at_home: Bool) {
		guard has_home || !at_home else { at_location = nil; return }
		let epoch = generation
		at_location = has_home && always_allowed ? at_home : nil
		Task { do { guard epoch == generation else { return }; try await HomeWorker.run { try HomeEngine.location_changed(at_home) }; guard epoch == generation else { return }; status = at_home ? "At home · home rules apply" : "Away or location unknown · usage does not count" }
		catch { error_message = error.localizedDescription } }
	}
}

@MainActor
final class HomeAppDelegate: NSObject, UIApplicationDelegate {
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
		if !CommandLine.arguments.contains("--ui-testing") { HomeLocationController.shared.restore() }
		return true
	}
}
