import XCTest

// Walks the app on a simulator and saves a screenshot of each screen, so the UI can be seen without a Mac.
final class ScreenshotTests: XCTestCase {
	private var app: XCUIApplication!
	private var output: URL?

	override func setUpWithError() throws {
		continueAfterFailure = false
		if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !directory.isEmpty {
			output = URL(fileURLWithPath: directory, isDirectory: true)
			try FileManager.default.createDirectory(at: output!, withIntermediateDirectories: true)
		}
		app = XCUIApplication()
		app.launchArguments = ["--reset-library", "--ui-testing"]
		app.launch()
	}

	func test_walkthrough_screens() throws {
		XCTAssertTrue(app.navigationBars["My routines"].waitForExistence(timeout: 10))
		try snap("01-home-empty")
		XCTAssertFalse(app.buttons["Use this routine"].exists)
		app.buttons["New routine"].tap()
		XCTAssertTrue(app.navigationBars["New routine"].waitForExistence(timeout: 10))
		XCTAssertTrue(app.textFields["editor.name"].exists || app.textViews["editor.name"].exists)
		try snap("02-new-page")
		app.buttons["Cancel"].tap()
		XCTAssertFalse(app.buttons["Open My new routine"].exists)
		app.buttons["New routine"].tap()
		element("editor.add-block").tap()
		XCTAssertTrue(app.navigationBars["Add block"].waitForExistence(timeout: 10))
		try snap("03-block-picker")
		element("add.checklist").tap()
		XCTAssertTrue(app.buttons["block.checklist"].waitForExistence(timeout: 10))
		try snap("04-page-editor")
		app.buttons["Save"].tap()
		XCTAssertTrue(app.buttons["Open My new routine"].waitForExistence(timeout: 10))
		try snap("05-home-with-routine")
		app.buttons["Edit My new routine"].tap()
		XCTAssertTrue(app.navigationBars["My new routine"].waitForExistence(timeout: 10))
		XCTAssertTrue(app.textFields["page.name"].waitForExistence(timeout: 10))
		XCTAssertFalse(app.navigationBars["Edit routine"].exists)
		try snap("09-routine-inline-edit")
		app.buttons["page.add-block"].tap()
		app.buttons["Note"].tap()
		app.buttons["Cancel"].tap()
		XCTAssertFalse(app.staticTexts["A note to myself"].exists)
		app.buttons["tool.edit"].tap()
		app.buttons["page.add-block"].tap()
		app.buttons["Note"].tap()
		app.buttons["Save"].tap()
		XCTAssertTrue(app.staticTexts["A note to myself"].waitForExistence(timeout: 10))
		try snap("10-routine-after-save")
		app.navigationBars["My new routine"].buttons["My routines"].tap()
		app.swipeUp()
		element("home.groups").tap()
		XCTAssertTrue(app.navigationBars["App groups"].waitForExistence(timeout: 10))
		try snap("06-app-groups")
		let name = app.textFields["groups.new"]
		name.tap(); name.typeText("Distractions")
		app.buttons["Add"].tap()
		app.swipeDown()
		let group = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "group.")).firstMatch
		XCTAssertTrue(group.waitForExistence(timeout: 10)); group.tap()
		XCTAssertTrue(app.navigationBars["Distractions"].waitForExistence(timeout: 10))
		try snap("07-choose-apps")
	}

	func test_home_allowance_can_be_edited() throws {
		app.terminate()
		app.launchEnvironment["POCKETWORK_UI_LIBRARY"] = """
		{"schema_version":1,"tools":[{"updated_at":"2026-09-13T00:00:00.000Z","document":{"schema_version":2,"id":"home-distraction-allowance","name":"Home distraction allowance","description":"Only distraction time at home counts.","enabled":false,"rules":{"block_during_focus":true,"notify_on_complete":false},"blocks":[{"id":"heading","type":"heading","title":"Home allowance","subtitle":""},{"id":"schedule","type":"schedule","title":"Weekly windows","days":[1,2,3,4,5,6,7],"start":"00:00","end":"23:59"},{"id":"shield","type":"screen_time","title":"Distractions","mode":"block","groups":["Distractions"]}],"home_allowance":{"timezone":"America/Los_Angeles","away_usage_counts":false,"outside_windows":"block_at_home","rules":[{"days":[2,3,4,5],"allowance_minutes":30,"windows":[{"start":"18:00","end":"18:30"},{"start":"19:00","end":"20:50"}]},{"days":[6],"allowance_minutes":120,"windows":[{"start":"14:30","end":"20:20"}]},{"days":[1,7],"allowance_minutes":180,"windows":[{"start":"06:30","end":"20:30"}]}]}}}],"groups":[{"id":"distractions","name":"Distractions"}]}
		"""
		app.launch()
		element("home.edit.home-distraction-allowance").tap()
		XCTAssertTrue(app.navigationBars["Home allowance"].waitForExistence(timeout: 10))
		try snap("08-home-allowance-editor")
		let allowance = app.buttons["home.allowance.2-Increment"]
		allowance.tap()
		XCTAssertEqual(allowance.value as? String, "35 minutes")
		app.buttons["Save"].tap()
		XCTAssertTrue(app.buttons["tool.edit"].waitForExistence(timeout: 10))
		app.buttons["tool.edit"].tap()
		XCTAssertTrue(allowance.waitForExistence(timeout: 10))
		XCTAssertEqual(allowance.value as? String, "35 minutes")
		allowance.tap()
		app.buttons["Cancel"].tap()
		app.buttons["tool.edit"].tap()
		XCTAssertEqual(allowance.value as? String, "35 minutes")
		app.buttons["Cancel"].tap()
		app.navigationBars["Home allowance"].buttons["My routines"].tap()
		app.swipeUp()
		element("home.group.distractions").tap()
		XCTAssertTrue(app.navigationBars["Distractions"].waitForExistence(timeout: 10))
	}

	// SwiftUI exposes list rows and toolbar items as different element types; a typed query per kind stays fast.
	private func element(_ identifier: String) -> XCUIElement {
		let candidates = [app.buttons[identifier], app.cells[identifier], app.otherElements[identifier], app.staticTexts[identifier]]
		for candidate in candidates where candidate.waitForExistence(timeout: 5) { return candidate }
		XCTFail("Missing \(identifier)")
		return candidates[0]
	}

	private func snap(_ name: String) throws {
		let screenshot = app.screenshot()
		let attachment = XCTAttachment(screenshot: screenshot)
		attachment.name = name
		attachment.lifetime = .keepAlways
		add(attachment)
		if let output { try screenshot.pngRepresentation.write(to: output.appendingPathComponent("\(name).png")) }
	}
}
