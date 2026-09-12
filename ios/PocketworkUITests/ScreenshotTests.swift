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
		app.launchArguments = ["--reset-library"]
		app.launch()
	}

	func test_walkthrough_screens() throws {
		XCTAssertTrue(app.navigationBars["My tools"].waitForExistence(timeout: 10))
		try snap("01-home-empty")

		element("routine.deep-work").tap()
		XCTAssertTrue(app.navigationBars["Deep work"].waitForExistence(timeout: 10))
		try snap("02-tool-deep-work")

		element("tool.edit").tap()
		XCTAssertTrue(app.navigationBars["Edit tool"].waitForExistence(timeout: 10))
		try snap("03-editor")

		element("block.timer").tap()
		XCTAssertTrue(app.navigationBars["Focus timer"].waitForExistence(timeout: 10))
		try snap("04-block-editor-timer")

		app.navigationBars["Focus timer"].buttons.firstMatch.tap()
		app.buttons["Cancel"].tap()
		app.navigationBars["Deep work"].buttons.firstMatch.tap()
		XCTAssertTrue(app.navigationBars["My tools"].waitForExistence(timeout: 10))
		try snap("05-home-with-tool")

		element("routine.bedtime").tap()
		XCTAssertTrue(app.navigationBars["Phone-free bedtime"].waitForExistence(timeout: 10))
		try snap("06-tool-bedtime")
	}

	// SwiftUI exposes list rows and toolbar items as different element types, so match on identifier alone.
	private func element(_ identifier: String) -> XCUIElement {
		let match = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
		XCTAssertTrue(match.waitForExistence(timeout: 10), "Missing \(identifier)")
		return match
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
