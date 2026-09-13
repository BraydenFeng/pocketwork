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
		XCTAssertTrue(app.navigationBars["Edit routine"].waitForExistence(timeout: 10))
		app.buttons["Cancel"].tap()
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
