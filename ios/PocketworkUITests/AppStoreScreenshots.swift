import XCTest

// App Store screenshots with a realistic sample library. Runs only from the App Store screenshots workflow.
final class AppStoreScreenshots: XCTestCase {
	private var app: XCUIApplication!
	private var output: URL?
	private let la = TimeZone(identifier: "America/Los_Angeles")!

	override func setUpWithError() throws {
		try XCTSkipUnless(ProcessInfo.processInfo.environment["APP_STORE_SCREENSHOTS"] == "1", "Set APP_STORE_SCREENSHOTS=1 to capture App Store screenshots.")
		continueAfterFailure = false
		if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !directory.isEmpty {
			output = URL(fileURLWithPath: directory, isDirectory: true)
			try FileManager.default.createDirectory(at: output!, withIntermediateDirectories: true)
		}
		app = XCUIApplication()
		app.launchArguments = ["--reset-library", "--ui-testing"]
		app.launchEnvironment["POCKETWORK_UI_LIBRARY"] = Self.library
		app.launchEnvironment["POCKETWORK_UI_SESSION_HISTORY"] = session_history()
		app.launchEnvironment["POCKETWORK_UI_HOME_STATE"] = home_state()
		app.launch()
	}

	func test_app_store_screenshots() throws {
		XCTAssertTrue(app.buttons["Edit Homework block"].waitForExistence(timeout: 15))
		try snap("01-routines")

		app.buttons["Edit Homework block"].tap()
		XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
		app.buttons["Cancel"].tap()
		XCTAssertTrue(app.navigationBars["Homework block"].waitForExistence(timeout: 10))
		try snap("02-routine")
		app.navigationBars["Homework block"].buttons["Routines"].tap()

		app.tabBars.buttons["Data"].tap()
		XCTAssertTrue(app.navigationBars["Data"].waitForExistence(timeout: 10))
		// Charts render a moment after the tab appears.
		_ = app.descendants(matching: .any)["data.focus"].waitForExistence(timeout: 10)
		try snap("03-data")
		app.tabBars.buttons["Routines"].tap()

		app.buttons["Edit Home allowance"].tap()
		XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
		app.buttons["Cancel"].tap()
		XCTAssertTrue(app.navigationBars["Home allowance"].waitForExistence(timeout: 10))
		try snap("04-home-allowance")
		app.navigationBars["Home allowance"].buttons["Routines"].tap()

		app.buttons["New routine"].tap()
		let add = app.buttons["editor.add-block"].waitForExistence(timeout: 10) ? app.buttons["editor.add-block"] : app.descendants(matching: .any)["editor.add-block"]
		add.tap()
		XCTAssertTrue(app.navigationBars["Add block"].waitForExistence(timeout: 10))
		try snap("05-add-block")
	}

	private func snap(_ name: String) throws {
		let screenshot = app.screenshot()
		let attachment = XCTAttachment(screenshot: screenshot)
		attachment.name = name
		attachment.lifetime = .keepAlways
		add(attachment)
		if let output { try screenshot.pngRepresentation.write(to: output.appendingPathComponent("\(name).png")) }
	}

	// Two weeks of focus minutes, oldest first, ending today.
	private func session_history() -> String {
		let minutes = [45, 90, 0, 45, 135, 45, 0, 90, 45, 90, 0, 135, 45, 90]
		var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
		let today = calendar.startOfDay(for: .now)
		var days: [String] = []
		for (index, value) in minutes.enumerated() where value > 0 {
			let date = calendar.date(byAdding: .day, value: index - (minutes.count - 1), to: today)!
			let parts = calendar.dateComponents([.year, .month, .day], from: date)
			days.append(String(format: "\"%04d-%02d-%02d\":{\"minutes\":%d,\"sessions\":%d}", parts.year!, parts.month!, parts.day!, value, max(1, value / 45)))
		}
		return "{\"days\":{\(days.joined(separator: ","))}}"
	}

	// The allowance ledger keys days as Y-M-D in Los Angeles time and stores [used, budget] per past day.
	private func home_state() -> String {
		var calendar = Calendar(identifier: .gregorian); calendar.timeZone = la
		let today = calendar.startOfDay(for: .now)
		func key(_ date: Date) -> String { let c = calendar.dateComponents([.year, .month, .day], from: date); return "\(c.year!)-\(c.month!)-\(c.day!)" }
		func budget(_ date: Date) -> Int { switch calendar.component(.weekday, from: date) { case 2...5: return 30; case 6: return 120; default: return 180 } }
		let fractions = [0.9, 1.0, 0.6, 0.8, 1.0, 0.5, 0.7, 1.0, 0.4, 0.9, 0.6, 1.0, 0.8]
		var history: [String] = []
		for (index, fraction) in fractions.enumerated() {
			let date = calendar.date(byAdding: .day, value: index - fractions.count, to: today)!
			let limit = budget(date)
			history.append("\"\(key(date))\":[\(Int(Double(limit) * fraction)),\(limit)]")
		}
		let used = budget(today) / 2
		return "{\"at_home\":true,\"enabled\":true,\"outside_migrated\":true,\"ledger\":{\"day\":\"\(key(today))\",\"used_minutes\":\(used),\"segment_base\":\(used),\"bonuses\":{},\"history\":{\(history.joined(separator: ","))}}}"
	}

	private static let library = #"""
{"schema_version":1,"groups":[{"id":"social","name":"Social"},{"id":"distractions","name":"Distractions"}],"tools":[
{"updated_at":"2026-10-01T22:00:00.000Z","document":{"schema_version":1,"id":"homework-block","name":"Homework block","description":"45 minutes with social apps locked.","rules":{"block_during_focus":true,"notify_on_complete":true},"blocks":[{"id":"heading","type":"heading","title":"Homework first","subtitle":"Phone face down until the timer ends."},{"id":"timer","type":"timer","title":"Focus","minutes":45},{"id":"tasks","type":"checklist","title":"Tonight","items":[{"id":"t1","text":"Math problem set"},{"id":"t2","text":"Read chapter 12"},{"id":"t3","text":"Outline the essay"}]},{"id":"shield","type":"screen_time","title":"Social apps locked","mode":"block","groups":["Social"]}]}},
{"updated_at":"2026-09-30T22:00:00.000Z","document":{"schema_version":1,"id":"bedtime","name":"Phone-free bedtime","description":"Social apps lock every night.","enabled":true,"rules":{"block_during_focus":true,"notify_on_complete":false},"blocks":[{"id":"heading","type":"heading","title":"Lights out","subtitle":"Social apps stay locked until morning."},{"id":"window","type":"schedule","title":"Every night","days":[1,2,3,4,5,6,7],"start":"22:30","end":"07:00"},{"id":"shield","type":"screen_time","title":"Social apps locked","mode":"block","groups":["Social"]}]}},
{"updated_at":"2026-09-29T22:00:00.000Z","document":{"schema_version":2,"id":"home-allowance","name":"Home allowance","description":"Distraction time only counts at home.","enabled":true,"rules":{"block_during_focus":true,"notify_on_complete":false},"blocks":[{"id":"heading","type":"heading","title":"Home allowance","subtitle":""},{"id":"schedule","type":"schedule","title":"Weekly windows","days":[1,2,3,4,5,6,7],"start":"00:00","end":"23:59"},{"id":"shield","type":"screen_time","title":"Distractions","mode":"block","groups":["Distractions"]}],"home_allowance":{"timezone":"America/Los_Angeles","away_usage_counts":false,"outside_windows":"unrestricted","rules":[{"days":[2,3,4,5],"allowance_minutes":30,"windows":[{"start":"18:00","end":"18:30"},{"start":"19:00","end":"20:50"}]},{"days":[6],"allowance_minutes":120,"windows":[{"start":"14:30","end":"20:20"}]},{"days":[1,7],"allowance_minutes":180,"windows":[{"start":"06:30","end":"20:30"}]}]}}}
]}
"""#
}
