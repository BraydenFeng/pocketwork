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

		element("routine.deep-work").tap()
		XCTAssertTrue(app.navigationBars["Deep work"].waitForExistence(timeout: 10))
		try snap("02-tool-deep-work")

		element("tool.edit").tap()
		XCTAssertTrue(app.navigationBars["Edit routine"].waitForExistence(timeout: 10))
		try snap("03-editor")

		element("block.timer").tap()
		XCTAssertTrue(app.navigationBars["Focus timer"].waitForExistence(timeout: 10))
		try snap("04-block-editor-timer")

		app.navigationBars["Focus timer"].buttons.firstMatch.tap()
		app.buttons["Cancel"].tap()
		app.navigationBars["Deep work"].buttons.firstMatch.tap()
		XCTAssertTrue(app.navigationBars["My routines"].waitForExistence(timeout: 10))
		try snap("05-home-with-routine")

		element("routine.bedtime").tap()
		XCTAssertTrue(app.navigationBars["Phone-free bedtime"].waitForExistence(timeout: 10))
		try snap("06-routine-bedtime-standing")

		element("tool.edit").tap()
		XCTAssertTrue(app.navigationBars["Edit routine"].waitForExistence(timeout: 10))
		element("block.schedule").tap()
		XCTAssertTrue(app.navigationBars["Schedule"].waitForExistence(timeout: 10))
		try snap("07-block-editor-schedule")
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
